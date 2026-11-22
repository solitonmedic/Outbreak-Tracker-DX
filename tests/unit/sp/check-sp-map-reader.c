/* Reusable synthetic SP map-reader checks. C11/LuaJIT, included reader + Windows
   stubs; no recordings, PINE or file writes. Inputs: zeroed synthetic32MiB RAM.
   Output: PASS; run check-sp-map-reader.sh from repo root. Exercises code guards,
   room/slot context, valid records, cycles, disabled/collected items and bad IDs. */
#include "main.c"
#include <assert.h>
#include <stdio.h>
unsigned char* test_memory;
size_t test_memory_size = 0x2000000;
static void put(unsigned a, unsigned v, int n)
{
    memcpy(test_memory + a, &v, n);
}
static int available(lua_State* L)
{
    lua_settop(L, 0);
    LGetSPMapState(L);
    lua_getfield(L, -1, "available");
    int v = lua_toboolean(L, -1);
    lua_pop(L, 1);
    return v;
}
int main(void)
{
    lua_State* L = luaL_newstate();
    test_memory = calloc(1, test_memory_size);
    assert(test_memory);
    info.CurrentFile = 2;
    put(0x59A880, 0x96840052, 4);
    put(0x59A8A0, 0x30841FFF, 4);
    put(0x58F9AC, 0x3C020049, 4);
    put(0x58F9E0, 0xA0220109, 4);
    put(0x4912B8, 300, 4);
    put(0x4912A0, 2, 1);
    put(0x3137BC, 1, 2);
    put(0x24AF48, 0x800000, 4);
    put(0x47BD30, 1, 1);
    put(0x47BD31, 1, 1);
    put(0x47BD30 + 0x1E2, 1, 2);
    unsigned a = 0x800000;
    int corners[] = {100, 100, 200, 100, 200, 200, 100, 200};
    memcpy(test_memory + a, corners, sizeof(corners));
    put(a + 32, 0, 4);
    put(a + 36, 100, 4);
    put(a + 48, 5, 1);
    put(a + 60, 1, 1);
    put(a + 82, 0x400a, 2);
    float x = 150, z = 150, h = 50;
    memcpy(test_memory + a + 0x44, &x, 4);
    memcpy(test_memory + a + 0x48, &h, 4);
    memcpy(test_memory + a + 0x4C, &z, 4);
    assert(available(L));
    lua_getfield(L, -1, "roomItems");
    assert(lua_objlen(L, -1) == 1);
    lua_rawgeti(L, -1, 1);
    lua_getfield(L, -1, "id");
    assert(lua_tonumber(L, -1) == 10);
    put(a + 40, a, 4);
    assert(!available(L));
    put(a + 40, 0, 4);
    put(a + 44, 4, 4);
    assert(!available(L));
    put(a + 44, 0, 4);
    put(0x490109, 9, 1);
    assert(!available(L));
    put(0x490109, 0, 1);
    put(0x4912BD, 4, 1);
    assert(!available(L));
    put(0x4912BD, 0, 1);
    put(0x59A880, 0, 4);
    assert(!available(L));
    put(0x59A880, 0x96840052, 4);
    put(a + 60, 2, 1);
    assert(!available(L));
    put(a + 60, 0, 1);
    assert(available(L));
    put(0x490109, 1, 1);
    put(0x491166, 10, 2);
    assert(available(L));
    lua_getfield(L, -1, "roomItems");
    lua_rawgeti(L, -1, 1);
    lua_getfield(L, -1, "collected");
    assert(lua_toboolean(L, -1));
    puts("PASS SP map native reader: valid/disabled/collected records, code guards, slot/count, cycle and "
         "reciprocal-link failures");
    lua_close(L);
    free(test_memory);
    return 0;
}
