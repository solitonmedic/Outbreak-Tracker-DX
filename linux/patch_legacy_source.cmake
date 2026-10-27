# Reusable CMake adapter for compiling the legacy C reader as C++17.
# Location/runtime: linux/patch_legacy_source.cmake; CMake 3.20+.
# Inputs: INPUT source path, OUTPUT generated copy, both passed with -D.
# Outputs: C++ casts/export, bounded room-item filter and read throttling.
# U.S. room authority refreshes each update; legacy releases retain throttling.
# Safety: edits OUTPUT only; no PINE, game, recording or workbook access.
# Run from repo root: cmake -DINPUT=$PWD/sources/main.c -DOUTPUT=/tmp/main_linux.cpp -P linux/patch_legacy_source.cmake
# Check: platform C++ build and outside-checkout room-item regression (build notes).
file(READ "${INPUT}" source)
# Convert the address after byte arithmetic; casting buffer first doubles offsets.
string(REPLACE "unsigned short* ptr2 = buffer+10+i*196;" "unsigned short* ptr2 = (unsigned short*)(buffer+10+i*196);" source "${source}")
string(REPLACE "unsigned short* ptr2 = buffer+10+(i)*192;" "unsigned short* ptr2 = (unsigned short*)(buffer+10+(i)*192);" source "${source}")
string(REPLACE "__declspec(dllexport) int luaopen_luaoutbreaktracker" "extern \"C\" __declspec(dllexport) int luaopen_luaoutbreaktracker" source "${source}")
string(REPLACE "if (RItems->RItem[j].ID == 0x00||\n\t\t\t\tRItems->RItem[j].Count == 0xFFFF||\n\t\t\t\tRItems->RItem[j].EN != 0xFFFF||\n\t\t\t\t//RItems->RItem[j].Pick > 0 && RItems->RItem[j].Present ==0||\n\t\t\t\tRItems->RItem[j].Mix == 0x20)" "if (RItems->RItem[j].ID == 0x00 ||\n\t\t\t\tRItems->RItem[j].ID > 0xFF ||\n\t\t\t\tRItems->RItem[j].Count == 0xFFFF ||\n\t\t\t\tRItems->RItem[j].EN != 0xFFFF ||\n\t\t\t\tRItems->RItem[j].Mix == 0x20)" source "${source}")
string(REPLACE "UpdatePickups();" "static unsigned int pickupUpdateCounter = 0;\n\tif ((pickupUpdateCounter++ % 6) == 0) UpdatePickups();" source "${source}")
string(REPLACE "UpdateEnemyList();" "static unsigned int enemyListUpdateCounter = 0;\n\tif ((enemyListUpdateCounter++ % 15) == 0) UpdateEnemyList();" source "${source}")
string(REPLACE "UpdateRoomMasters();" "static unsigned int roomMasterUpdateCounter = 0;\n\tif ((info.CurrentFile == 1 && F1_Release == F1_RELEASE_US) || (roomMasterUpdateCounter++ % 30) == 0) UpdateRoomMasters();" source "${source}")
file(WRITE "${OUTPUT}" "${source}")
