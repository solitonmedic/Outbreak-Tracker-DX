/* Stand-in for PCSX2 in the Windows gameplay-frame test.
 *
 * Purpose: the Windows reader (sources/main.c) finds the process named
 *   "pcsx2-qt.exe", loads its symbols with DbgHelp, looks up "EEmem" and reads
 *   the 8-byte pointer stored there as the base of the emulated EE RAM. This
 *   program is built as pcsx2-qt.exe, exports EEmem pointing at a buffer filled
 *   from one gameplay frame, prints "ready" and waits until it is stopped.
 * Location/language: tests/fakes/fake_pcsx2.c; C for MSVC (x64).
 * Build (x64 Visual Studio Developer Command Prompt; the PDB lets DbgHelp find
 *   EEmem, and the export is a second route):
 *   cl /nologo /O2 /Zi tests\fakes\fake_pcsx2.c /Fe:pcsx2-qt.exe /link /DEBUG
 * Inputs: argv[1] = frame file (tests/frames.py format: "OTFRAME1" and
 *   u32 address, u32 length, bytes records).
 * Outputs: "ready" on stdout once the memory is filled; exit codes 2-5 on bad
 *   arguments, allocation or frame errors.
 * Safety: holds test memory only; writes nothing; stopped by the test runner.
 *   The 32 MiB EE RAM sits in the middle of 96 MiB of zeros, so reads a little
 *   before or past it return zeros, as the other fakes do.
 * Run/check: started by tests/run_frames.py --platform windows --fake-pcsx2.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define EE_RAM_SIZE (32u * 1024u * 1024u)

__declspec(dllexport) unsigned char* EEmem = NULL;

static uint32_t u32(const unsigned char* p)
{
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

int main(int argc, char** argv)
{
    unsigned char header[8], record[8];
    unsigned char* region;
    FILE* frame;
    if (argc < 2)
    {
        fprintf(stderr, "usage: pcsx2-qt.exe FRAME.otf\n");
        return 2;
    }
    region = (unsigned char*)VirtualAlloc(NULL, 3 * EE_RAM_SIZE, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!region)
    {
        fprintf(stderr, "cannot allocate the emulated memory\n");
        return 3;
    }
    EEmem = region + EE_RAM_SIZE;
    frame = fopen(argv[1], "rb");
    if (!frame || fread(header, 1, 8, frame) != 8 || memcmp(header, "OTFRAME1", 8) != 0)
    {
        fprintf(stderr, "cannot read the frame file\n");
        return 4;
    }
    while (fread(record, 1, 8, frame) == 8)
    {
        uint32_t address = u32(record), length = u32(record + 4);
        if ((uint64_t)address + length > EE_RAM_SIZE || fread(EEmem + address, 1, length, frame) != length)
        {
            fprintf(stderr, "damaged frame file\n");
            return 5;
        }
    }
    fclose(frame);
    printf("ready\n");
    fflush(stdout);
    for (;;)
        Sleep(1000);
}
