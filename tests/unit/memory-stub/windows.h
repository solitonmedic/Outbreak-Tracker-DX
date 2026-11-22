/* Test stand-in for <windows.h>: serves EE RAM from an in-memory checkpoint. */
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
typedef uint32_t DWORD;
typedef uint64_t DWORD64;
typedef uint64_t ULONG64;
typedef int BOOL;
typedef unsigned char BYTE;
typedef size_t SIZE_T;
typedef void* HANDLE;
#define FALSE                0
#define TRUE                 1
#define INVALID_HANDLE_VALUE ((HANDLE) - 1)
#define PROCESS_VM_READ      0x0010
#define __declspec(x)
typedef struct
{
    uint32_t SizeOfStruct;
    uint64_t Address;
} SYMBOL_INFO;
extern unsigned char* test_memory;
extern size_t test_memory_size;
static HANDLE OpenProcess(DWORD a, BOOL b, DWORD c)
{
    return (HANDLE)1;
}
static BOOL CloseHandle(HANDLE h)
{
    return TRUE;
}
static BOOL SymInitialize(HANDLE h, const char* p, BOOL b)
{
    return TRUE;
}
static DWORD64 SymLoadModuleEx(HANDLE a, HANDLE b, const char* c, const char* d, DWORD64 e, DWORD f, void* g, DWORD h)
{
    return 1;
}
static BOOL SymFromName(HANDLE h, const char* n, SYMBOL_INFO* s)
{
    s->Address = 0;
    return FALSE;
}
static BOOL ReadProcessMemory(HANDLE h, const void* address, void* out, SIZE_T size, SIZE_T* done)
{
    intptr_t a = (intptr_t)address;
    if (a >= 0 && (size_t)a + size <= test_memory_size)
        memcpy(out, test_memory + a, size);
    else
        memset(out, 0xEE, size); /* out-of-range reads are visible in the dump */
    return TRUE;
}
