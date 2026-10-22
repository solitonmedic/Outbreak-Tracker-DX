// U.S. File 1 (SLUS-20765) address profile.
//
// The tracker keeps the Japanese File 1 (SLPM-65428) addresses from F1Addr.h and
// translates them here when the U.S. release is loaded. The U.S. build has no
// single global shift, so each region below lists the Japanese range it covers
// and the offset that moves it to the U.S. layout. Only regions whose fields are
// validated or supported in devlog/file1-us-database.xlsx are listed; every
// other Japanese address is unmapped for the U.S. release and reads as zero.
//
// Evidence comes from U.S. recordings made with the community update Ver2.162
// installed. Stock offline v2.00 behaviour has not been checked.

#define F1_RELEASE_JP 0
#define F1_RELEASE_US 1

// "BASLUS-20765" sits at this address in every checkpoint of the five U.S.
// recordings (menus, lobby and gameplay) and is absent there in the Japanese one.
const int F1_US_ReleaseMarker = 0x250510;
const char F1_US_ReleaseMarkerText[] = "BASLUS-20765";
#define F1_US_RELEASE_MARKER_SIZE 12

int F1_Release = F1_RELEASE_JP;

typedef struct
{
    int Start;  // first Japanese address of the region
    int Size;   // bytes covered
    int Shift;  // U.S. address minus Japanese address
} F1AddressRegion;

const F1AddressRegion F1_US_Regions[] =
{
    { 0x476DD0, 4 * 0x10E0, 0x2EE60 },  // player blocks 1-4 (layout validated for player 1)
    { 0x39680C, 255 * 60,   0x2EE60 },  // pickup array, 60-byte records
    { 0x420000, 12 * 0xD90, 0x2EE60 },  // enemy slots 1-12
    { 0x71A030, 80 * 0x60,  0x35220 },  // enemy list, 0x60-byte entries
    { 0x472F90, 0xAF0,      0x2EE60 },  // door HP words (supported)
    { 0x48AD90, 0x4E0,      0x2EE70 },  // door flag words (supported)
    { 0x48BDE2, 4 * 8,      0x2EE70 },  // dead inventories
    { 0x48BF60, 1,          0x2EE70 },  // scenario state (cleared)
    { 0x48BF78, 4,          0x2EE70 },  // scenario clock, 30 ticks per second
    { 0x48C01A, 1,          0x2EE70 },  // difficulty
    { 0x3065AA, 2,          0x1DE30 },  // scenario ID
    { 0x23BE14, 1,          0x27F08C },  // number of players present (supported)
    { 0x6E6C70, 12 * 4,     0x34140 },  // virus maximum per character type (byte-identical table)
    { 0x23BD90, 4,          0x1793D0 }, // room-item pointer (supported); the records it names are read as is
    { 0x23BB20, 4,          0x7D2B8 },  // ItemRandom: same start-up clear and running-maximum code as Japan
    { 0x23BBA0, 2,          0xE8918 },  // PuzzleRandom / ItemRandom2: state of the same 0xFF53 random generator
    { 0x629600, 30 * 0x15C, 0xA3EA0 },  // room-list slots: same 0x28C8 clear and field offsets in the lobby code
    { 0x62E230, 1,          0xAAB80 },  // host status, first byte of the lobby state cleared by the same reset code
    { 0x62E236, 2,          0xAAB80 },  // host scenario, same lobby-state offset (+6)
    { 0x62EB80, 2,          0xAAB88 },  // host countdown in seconds; U.S. lobby state +0x958 (Japan +0x950)
};

// Returns the U.S. address for a Japanese File 1 address, or 0 when the whole
// read is not inside a mapped region.
int F1_US_Translate(int address, int size)
{
    int count = sizeof(F1_US_Regions) / sizeof(F1_US_Regions[0]);
    for (int i = 0; i < count; i++)
    {
        const F1AddressRegion* region = &F1_US_Regions[i];
        if (address >= region->Start && address + size <= region->Start + region->Size)
            return address + region->Shift;
    }
    return 0;
}
