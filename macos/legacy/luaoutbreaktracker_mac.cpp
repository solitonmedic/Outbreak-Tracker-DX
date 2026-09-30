// luaoutbreaktracker_mac.cpp
// MacOS version of the Outbreak Tracker backend using PINE IPC

extern "C" {
    #include <lua.h>
    #include <lauxlib.h>
}

#include <stdint.h>
#include <string.h>
#include <exception>
#include <iostream>

#include "/Users/adjule/pine/src/pine.h"   // adjust if needed
#include "structs.h"
#include "F1Addr.h"
#include "F2Addr.h"

static PINE::PCSX2 g_pcsx2;    // auto-connects on creation
static GameInfo g_info;
static bool g_connected = false;
static int g_currentFile = 255;
static constexpr uint32_t EE_BASE = 0x20000000;

static void push_int_field(lua_State* L, const char* key, int val) {
    lua_pushstring(L, key);
    lua_pushinteger(L, val);
    lua_settable(L, -3);
}

static void push_string_field(lua_State* L, const char* key, const char* val) {
    lua_pushstring(L, key);
    lua_pushstring(L, val);
    lua_settable(L, -3);
}

// ---------------------------------------------------------------------
// Low-level PS2 memory readers (for your pine.h version)
// ---------------------------------------------------------------------


template<typename T>
static bool read_ps2(uint32_t ee_addr, T& out)
{
    try {
        uint32_t addr = ee_addr;

        // If it looks like a PS2 EE address (0x2xxxxxxx), convert to PINE's EEmem offset.
        if (addr >= 0x20000000 && addr < 0x30000000)
            addr -= EE_BASE;

        out = g_pcsx2.Read<T>(addr);
        return true;
    }
    catch (...) {
        return false;
    }
}



static int detect_file() {
    uint8_t f1 = 0, f2 = 0;
    read_ps2(0x2321B3, f1);
    read_ps2(0x23DFD3, f2);
    if (f1 == 0x53) return 1;
    if (f2 == 0x53) return 2;
    return -1;
}

static bool refresh_gameinfo() {
    memset(&g_info, 0, sizeof(g_info));

    if (!g_connected) return false;

    // For now, we assume you're always running File #1.
    const int file = 1;
    g_currentFile   = file;
    g_info.CurrentFile = file;

    bool ok = true;

    if (file == 1) {
        ok &= read_ps2<unsigned char >(F1_HostStatus,     g_info.HostStatus);
        ok &= read_ps2<unsigned short>(F1_HostPlayer,     g_info.HostPlayer);
        ok &= read_ps2<unsigned short>(F1_HostScenarioID, g_info.HostScenarioID);
        ok &= read_ps2<unsigned short>(F1_HostDifficulty, g_info.HostDifficulty);
        ok &= read_ps2<unsigned short>(F1_ScenarioIDAddr, g_info.ScenarioID);
        ok &= read_ps2<unsigned int  >(F1_FrameCounter,   g_info.FrameCounter);
    } else {
        // We keep the File #2 branch here for later if you want it:
        ok &= read_ps2<unsigned char >(F2_HostStatus,     g_info.HostStatus);
        ok &= read_ps2<unsigned short>(F2_HostPlayer,     g_info.HostPlayer);
        ok &= read_ps2<unsigned short>(F2_HostScenarioID, g_info.HostScenarioID);
        ok &= read_ps2<unsigned short>(F2_HostDifficulty, g_info.HostDifficulty);
        ok &= read_ps2<unsigned short>(F2_ScenarioIDAddr, g_info.ScenarioID);
        ok &= read_ps2<unsigned int  >(F2_FrameCounter,   g_info.FrameCounter);
    }

    return ok;
}

static int LInit(lua_State* L) {
    try {
        char* title = g_pcsx2.GetGameTitle();
        if (title) {
            printf("[luaoutbreaktracker] Connected to PCSX2. Game title: %s\n", title);
            delete[] title;
            g_connected = true;
            g_currentFile = 1;
        } else {
            g_connected = false;
            g_currentFile = 255;
        }
    } catch (...) {
        g_connected = false;
        g_currentFile = 255;
    }
    lua_pushboolean(L, g_connected ? 1 : 0);
    return 1;
}

static int LUpdate(lua_State* L) {
    refresh_gameinfo();
    return 0;
}

static int LGetGameInfo(lua_State* L) {
    lua_newtable(L);

    if (!refresh_gameinfo()) {
        push_int_field(L, "currentFile", 255);
        push_string_field(L, "scenario", "");
        push_int_field(L, "frames", 0);
        return 1;
    }

    push_int_field(L, "currentFile", g_info.CurrentFile);
    push_int_field(L, "hoststatus", g_info.HostStatus);
    push_int_field(L, "scenario", g_info.ScenarioID);
    push_int_field(L, "frames", g_info.FrameCounter);
    push_string_field(L, "hostdifficulty", GetDifficultyName((int)g_info.HostDifficulty));
    push_string_field(L, "difficulty", GetDifficultyName((int)g_info.Difficulty));

    return 1;
}

static const luaL_Reg tracker_funcs[] = {
    {"init", LInit},
    {"update", LUpdate},
    {"getGameInfo", LGetGameInfo},
    {NULL, NULL}
};

extern "C" int luaopen_luaoutbreaktracker(lua_State* L) {
    luaL_newlib(L, tracker_funcs);
    return 1;
}
