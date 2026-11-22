/* Test stand-in for <windows.h> used to build sources/main.c as C, the way the
 * Windows package compiles it, into a Lua module for macOS or Linux test runs.
 *
 * Memory comes from a gameplay frame (see tests/frames.py for the format) or a
 * full 32 MiB image, named by the environment when the module first reads:
 *   TRACKER_FRAME  frame file (OTFRAME1 ranges; bytes outside them read as 0)
 *   TRACKER_IMAGE  raw or gzip 32 MiB EE RAM image (local frame extraction only)
 *   TRACKER_TRACE  optional file that receives one "address length" line per read
 * Reads outside the 32 MiB EE RAM return zeros, as the fake PCSX2 process and
 * the fake PINE server do. "pcsx2-qt.exe" is always found; the EEmem symbol is
 * not, so the base pointer stays 0 and addresses are EE RAM offsets.
 * Safety: reads only the files named above; never contacts PCSX2.
 */
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>
typedef uint32_t DWORD; typedef uint64_t DWORD64; typedef uint64_t ULONG64;
typedef int BOOL; typedef unsigned char BYTE; typedef size_t SIZE_T; typedef void* HANDLE;
#define FALSE 0
#define TRUE 1
#define INVALID_HANDLE_VALUE ((HANDLE)-1)
#define PROCESS_VM_READ 0x0010
#define __declspec(x)
typedef struct { uint32_t SizeOfStruct; uint64_t Address; } SYMBOL_INFO;

#define TEST_MEMORY_SIZE (32u * 1024u * 1024u)
static unsigned char* test_memory;
static FILE* test_trace;

static uint32_t test_u32(const unsigned char* p) { return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }

static void test_load(void)
{
	if (test_memory) return;
	test_memory = calloc(1, TEST_MEMORY_SIZE);
	if (!test_memory) abort();
	const char* trace = getenv("TRACKER_TRACE");
	if (trace && *trace) test_trace = fopen(trace, "a"); /* appended: one trace can span several runs */
	const char* image = getenv("TRACKER_IMAGE");
	const char* frame = getenv("TRACKER_FRAME");
	if (image && *image) {
		gzFile gz = gzopen(image, "rb");
		if (!gz || gzread(gz, test_memory, TEST_MEMORY_SIZE) != (int)TEST_MEMORY_SIZE) {
			fprintf(stderr, "test reader: cannot read the 32 MiB image\n");
			abort();
		}
		gzclose(gz);
	} else if (frame && *frame) {
		FILE* f = fopen(frame, "rb");
		unsigned char header[8], record[8];
		if (!f || fread(header, 1, 8, f) != 8 || memcmp(header, "OTFRAME1", 8) != 0) {
			fprintf(stderr, "test reader: cannot read the frame file\n");
			abort();
		}
		while (fread(record, 1, 8, f) == 8) {
			uint32_t address = test_u32(record), length = test_u32(record + 4);
			if ((uint64_t)address + length > TEST_MEMORY_SIZE || fread(test_memory + address, 1, length, f) != length) {
				fprintf(stderr, "test reader: damaged frame file\n");
				abort();
			}
		}
		fclose(f);
	}
}

static HANDLE OpenProcess(DWORD a, BOOL b, DWORD c) { return (HANDLE)1; }
static BOOL CloseHandle(HANDLE h) { return TRUE; }
static BOOL SymInitialize(HANDLE h, const char* p, BOOL b) { return TRUE; }
static DWORD64 SymLoadModuleEx(HANDLE a, HANDLE b, const char* c, const char* d, DWORD64 e, DWORD f, void* g, DWORD h) { return 1; }
static BOOL SymFromName(HANDLE h, const char* n, SYMBOL_INFO* s) { s->Address = 0; return FALSE; }
static BOOL ReadProcessMemory(HANDLE h, const void* address, void* out, SIZE_T size, SIZE_T* done)
{
	uint64_t a = (uint64_t)(uintptr_t)address;
	test_load();
	if (test_trace) fprintf(test_trace, "%llu %llu\n", (unsigned long long)a, (unsigned long long)size);
	/* Written to avoid overflow: an address below the base wraps to a huge a. */
	if (a < TEST_MEMORY_SIZE && size <= TEST_MEMORY_SIZE - a) memcpy(out, test_memory + a, size);
	else {
		memset(out, 0, size);
		if (a < TEST_MEMORY_SIZE) memcpy(out, test_memory + a, TEST_MEMORY_SIZE - a);
	}
	if (done) *done = size;
	return TRUE;
}
