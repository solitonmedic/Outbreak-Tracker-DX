#pragma once
#include <cstring>
#include <windows.h>
constexpr DWORD TH32CS_SNAPPROCESS = 2; constexpr DWORD TH32CS_SNAPMODULE = 8;
struct PROCESSENTRY32 { DWORD dwSize = sizeof(PROCESSENTRY32); DWORD th32ProcessID = 1; char szExeFile[260] = {}; };
struct MODULEENTRY32 { DWORD dwSize = sizeof(MODULEENTRY32); BYTE* modBaseAddr = nullptr; DWORD modBaseSize = 0; char szModule[256] = "pcsx2-qt"; char szExePath[260] = "pcsx2-qt"; };
inline HANDLE CreateToolhelp32Snapshot(DWORD, DWORD) { return reinterpret_cast<HANDLE>(2); }
inline BOOL Process32First(HANDLE, PROCESSENTRY32* entry) { std::strncpy(entry->szExeFile, "pcsx2-qt.exe", sizeof(entry->szExeFile)-1); return TRUE; }
inline BOOL Process32Next(HANDLE, PROCESSENTRY32*) { return FALSE; }
inline BOOL Module32First(HANDLE, MODULEENTRY32*) { return TRUE; }
