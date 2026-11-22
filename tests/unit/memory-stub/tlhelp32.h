#pragma once
#define TH32CS_SNAPPROCESS 2
#define TH32CS_SNAPMODULE  8
typedef struct
{
    DWORD dwSize;
    DWORD th32ProcessID;
    char szExeFile[260];
} PROCESSENTRY32;
typedef struct
{
    DWORD dwSize;
    BYTE* modBaseAddr;
    DWORD modBaseSize;
    char szModule[256];
    char szExePath[260];
} MODULEENTRY32;
static HANDLE CreateToolhelp32Snapshot(DWORD a, DWORD b)
{
    return INVALID_HANDLE_VALUE;
}
static BOOL Process32First(HANDLE h, PROCESSENTRY32* e)
{
    return FALSE;
}
static BOOL Process32Next(HANDLE h, PROCESSENTRY32* e)
{
    return FALSE;
}
static BOOL Module32First(HANDLE h, MODULEENTRY32* e)
{
    return FALSE;
}
