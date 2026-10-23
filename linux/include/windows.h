#pragma once
#include <cstdint>
#include <algorithm>
#include <array>
#include <chrono>
#include <cstring>
#include <cstddef>
#include <string>
#include <unordered_map>
#include <vector>
#include <pine.h>
#include <cstdlib>

#define __declspec(x) __attribute__((visibility("default")))
using DWORD = std::uint32_t; using DWORD64 = std::uint64_t; using ULONG64 = std::uint64_t;
using BOOL = int; using BYTE = unsigned char; using SIZE_T = std::size_t; using HANDLE = void*;
constexpr BOOL FALSE = 0; constexpr BOOL TRUE = 1;
#define INVALID_HANDLE_VALUE ((HANDLE)-1)
constexpr DWORD PROCESS_VM_READ = 0x0010;

struct SYMBOL_INFO { std::uint32_t SizeOfStruct = 0; std::uint64_t Address = 0; };
inline PINE::PCSX2 mac_pine;

// The tracker reads hundreds of small fields per update, and each PINE request costs
// PCSX2 a wake-up of its PINE thread. Small reads in main RAM are therefore served
// from 4 KiB pages, each fetched with one batched request and reused for a few
// milliseconds, which covers one tracker update but not the next one.
namespace tracker_page_cache {
constexpr std::uint32_t kPageSize = 4096;
constexpr std::uint32_t kMainRamSize = 0x02000000;
constexpr auto kLifetime = std::chrono::milliseconds(25);
struct Page { std::chrono::steady_clock::time_point fetched{}; std::array<std::uint8_t, kPageSize> bytes{}; };
inline std::unordered_map<std::uint32_t, Page> pages;

inline const std::uint8_t* Get(std::uint32_t base) {
    auto found = pages.find(base);
    if (found != pages.end() && std::chrono::steady_clock::now() - found->second.fetched < kLifetime)
        return found->second.bytes.data();
    Page page;
    mac_pine.InitializeBatch();
    for (std::uint32_t offset = 0; offset < kPageSize; offset += 8)
        mac_pine.Read<std::uint64_t, true>(base + offset);
    auto batch = mac_pine.FinalizeBatch();
    mac_pine.SendCommand(batch);
    for (std::uint32_t i = 0; i < kPageSize / 8; ++i) {
        const std::uint64_t value = mac_pine.GetReply<PINE::PCSX2::MsgRead64>(batch, static_cast<int>(i));
        std::memcpy(page.bytes.data() + i * 8, &value, sizeof(value));
    }
    page.fetched = std::chrono::steady_clock::now();
    return (pages[base] = page).bytes.data();
}
}

inline HANDLE OpenProcess(DWORD, BOOL, DWORD) { return reinterpret_cast<HANDLE>(1); }
inline BOOL CloseHandle(HANDLE) { return TRUE; }
inline BOOL SymInitialize(HANDLE, const char*, BOOL) { return TRUE; }
inline DWORD64 SymLoadModuleEx(HANDLE, HANDLE, const char*, const char*, DWORD64, DWORD, void*, DWORD) { return 1; }
inline BOOL SymFromName(HANDLE, const char*, SYMBOL_INFO* symbol) { symbol->Address = 1; return TRUE; }

inline BOOL ReadProcessMemory(HANDLE, const void* address, void* output, SIZE_T size, SIZE_T*) {
    const auto raw = reinterpret_cast<std::uintptr_t>(address);
    if (raw == 1 && size == sizeof(std::uint64_t)) {
        const std::uint64_t ee_base = 0x20000000ULL;
        std::memcpy(output, &ee_base, sizeof(ee_base)); return TRUE;
    }
    const auto ee = static_cast<std::uint32_t>((raw >= 0x20000000ULL && raw < 0x30000000ULL) ? raw - 0x20000000ULL : raw);
    try {
        auto* bytes = static_cast<std::uint8_t*>(output);

        // Large legacy reads (the room pickup table is several kilobytes)
        // otherwise become thousands of individual PINE round trips. Batch
        // those reads while retaining the original ReadProcessMemory shape.
        if (size >= 32) {
            struct ReadOp { SIZE_T offset; SIZE_T width; };
            SIZE_T offset = 0;
            while (offset < size) {
                const SIZE_T batch_end = std::min(size, offset + static_cast<SIZE_T>(512));
                std::vector<ReadOp> ops;
                mac_pine.InitializeBatch();
                while (offset < batch_end) {
                    const SIZE_T remaining = batch_end - offset;
                    if (remaining >= 8) {
                        mac_pine.Read<std::uint64_t, true>(ee + static_cast<std::uint32_t>(offset));
                        ops.push_back({offset, 8}); offset += 8;
                    } else if (remaining >= 4) {
                        mac_pine.Read<std::uint32_t, true>(ee + static_cast<std::uint32_t>(offset));
                        ops.push_back({offset, 4}); offset += 4;
                    } else if (remaining >= 2) {
                        mac_pine.Read<std::uint16_t, true>(ee + static_cast<std::uint32_t>(offset));
                        ops.push_back({offset, 2}); offset += 2;
                    } else {
                        mac_pine.Read<std::uint8_t, true>(ee + static_cast<std::uint32_t>(offset));
                        ops.push_back({offset, 1}); offset += 1;
                    }
                }
                auto batch = mac_pine.FinalizeBatch();
                mac_pine.SendCommand(batch);
                for (std::size_t i = 0; i < ops.size(); ++i) {
                    const auto& op = ops[i];
                    if (op.width == 8) *reinterpret_cast<std::uint64_t*>(bytes + op.offset) = mac_pine.GetReply<PINE::PCSX2::MsgRead64>(batch, static_cast<int>(i));
                    else if (op.width == 4) *reinterpret_cast<std::uint32_t*>(bytes + op.offset) = mac_pine.GetReply<PINE::PCSX2::MsgRead32>(batch, static_cast<int>(i));
                    else if (op.width == 2) *reinterpret_cast<std::uint16_t*>(bytes + op.offset) = mac_pine.GetReply<PINE::PCSX2::MsgRead16>(batch, static_cast<int>(i));
                    else bytes[op.offset] = mac_pine.GetReply<PINE::PCSX2::MsgRead8>(batch, static_cast<int>(i));
                }
            }
            return TRUE;
        }

        if (ee < tracker_page_cache::kMainRamSize && size <= tracker_page_cache::kMainRamSize - ee) {
            for (SIZE_T copied = 0; copied < size;) {
                const std::uint32_t address = ee + static_cast<std::uint32_t>(copied);
                const std::uint32_t base = address & ~(tracker_page_cache::kPageSize - 1);
                const SIZE_T within = address - base;
                const SIZE_T count = std::min<SIZE_T>(size - copied, tracker_page_cache::kPageSize - within);
                std::memcpy(bytes + copied, tracker_page_cache::Get(base) + within, count);
                copied += count;
            }
            return TRUE;
        }

        SIZE_T offset = 0;
        for (; offset + 8 <= size; offset += 8) *reinterpret_cast<std::uint64_t*>(bytes + offset) = mac_pine.Read<std::uint64_t>(ee + (std::uint32_t)offset);
        for (; offset + 4 <= size; offset += 4) *reinterpret_cast<std::uint32_t*>(bytes + offset) = mac_pine.Read<std::uint32_t>(ee + (std::uint32_t)offset);
        for (; offset + 2 <= size; offset += 2) *reinterpret_cast<std::uint16_t*>(bytes + offset) = mac_pine.Read<std::uint16_t>(ee + (std::uint32_t)offset);
        for (; offset < size; ++offset) bytes[offset] = mac_pine.Read<std::uint8_t>(ee + (std::uint32_t)offset);
        return TRUE;
    } catch (...) { return FALSE; }
}

#define bool tracker_bool

struct mac_malloc_result {
    std::size_t size;
    template <typename T> operator T*() const { return static_cast<T*>(std::malloc(size)); }
};
#define malloc(size) mac_malloc_result{size}
