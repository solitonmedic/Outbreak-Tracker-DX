/* Test stand-in for <tlhelp32.h>: one process, "pcsx2-qt.exe", with one module.
 * See windows.h in this folder. */
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
    return (HANDLE)2;
}
static BOOL Process32First(HANDLE h, PROCESSENTRY32* e)
{
    e->th32ProcessID = 4242;
    strcpy(e->szExeFile, "pcsx2-qt.exe");
    return TRUE;
}
static BOOL Process32Next(HANDLE h, PROCESSENTRY32* e)
{
    return FALSE;
}
static BOOL Module32First(HANDLE h, MODULEENTRY32* e)
{
    e->modBaseAddr = NULL;
    e->modBaseSize = 0;
    strcpy(e->szModule, "pcsx2-qt.exe");
    strcpy(e->szExePath, "pcsx2-qt.exe");
    return TRUE;
}
