#include <windows.h>
#include <tlhelp32.h>
#include <string.h>
#include <stdlib.h>
#include <DbgHelp.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include "structs.h"
#include "F1Addr.h"
#include "F2Addr.h"
#include "F1USAddr.h"


DWORD ProcessID = 0;
HANDLE ProcessHandle = NULL;

GameInfo info;
Slot Slots[20];
SPlayer SPlayers[4];
RoomsType Rooms;
RItem RItems[MAX_ITEM];
Player Players[4];
Enemy Enemies[MAX_ENEMY];
Item Items[256];
Door Doors[MAX_DOOR];
Enemy2 Enemies2[80];

long long int BasePointer;

int GetProcessID(char* processname)
{
	/* Successfully copy-pasted from random StackOverflow answer since I don't know how to work with Windows' crappy API.*/
	HANDLE hProcessSnap;
	PROCESSENTRY32 pe32;
	int result = 0;
	hProcessSnap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
	if (INVALID_HANDLE_VALUE == hProcessSnap) return(FALSE);
	pe32.dwSize = sizeof(PROCESSENTRY32);
	if (!Process32First(hProcessSnap, &pe32))
	{
	  CloseHandle(hProcessSnap);
	  return(0);
	}
	do
	{
	  if (0 == strcmp(processname, pe32.szExeFile))
	  {
	      result = pe32.th32ProcessID;
	      break;
	  }
	} while (Process32Next(hProcessSnap, &pe32));
	CloseHandle(hProcessSnap);
	return result;
}

/* PCSX2 now binds the emulated games base address to the symbol pcsx2-qt.EEmem */
void BindBasePointer()
{
	HANDLE hModuleSnap = INVALID_HANDLE_VALUE;
	MODULEENTRY32 me32;

	//  Take a snapshot of all modules in the specified process. 
	hModuleSnap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE, ProcessID);
	if (hModuleSnap == INVALID_HANDLE_VALUE)
	{
		return;
	}

	//  Set the size of the structure before using it. 
	me32.dwSize = sizeof(MODULEENTRY32);

	//  Retrieve information about the first module
	if (!Module32First(hModuleSnap, &me32))
	{
		CloseHandle(hModuleSnap);     // Must clean up the snapshot object! 
		return;
	}

	//  Do not forget to clean up the snapshot object. 
	CloseHandle(hModuleSnap);

	HANDLE hHandle = OpenProcess(PROCESS_VM_READ, FALSE, ProcessID);

	// Initialize debug symbol loading
	if (!SymInitialize(hHandle, NULL, FALSE)) {
		CloseHandle(hHandle);
		return;
	}

	SymLoadModuleEx(
		hHandle, NULL, me32.szExePath, me32.szModule,
		(DWORD64)me32.modBaseAddr, me32.modBaseSize, NULL, 0);

	SYMBOL_INFO symbol = { 0 };
	symbol.SizeOfStruct = sizeof(symbol);
	if (!SymFromName(hHandle, "EEmem", &symbol) || symbol.Address == 0)
	{
		CloseHandle(hHandle);
		return;
	}
	ULONG64 EEmemPointer = symbol.Address;
	ReadProcessMemory(hHandle, (char *)EEmemPointer, &BasePointer, 8, NULL);
}

char GetFile()
{
	/* Pretty crappy, but eh. */
    int bytesRead = 0;
    char f1;
    char f2;
    char usMarker[F1_US_RELEASE_MARKER_SIZE];
    ReadProcessMemory(ProcessHandle, (char *)BasePointer+0x002321B3, &f1, 1, NULL);
    ReadProcessMemory(ProcessHandle, (char *)BasePointer+0x0023DFD3, &f2, 1, NULL);
    if (f1 == 0x53)
	{
        F1_Release = F1_RELEASE_JP;
        return 1;
	}
    ReadProcessMemory(ProcessHandle, (char *)BasePointer+F1_US_ReleaseMarker, usMarker, F1_US_RELEASE_MARKER_SIZE, NULL);
    if (memcmp(usMarker, F1_US_ReleaseMarkerText, F1_US_RELEASE_MARKER_SIZE) == 0)
	{
        F1_Release = F1_RELEASE_US;
        return 1;
	}
    F1_Release = F1_RELEASE_JP;
    if (f2 == 0x53)
	{
        return 2;
	}
	return -1;
}

/* Returns whether a File 1 field (given by its Japanese address) can be read on the loaded release. */
int F1_IsMapped(int address, int size)
{
	return F1_Release != F1_RELEASE_US || F1_US_Translate(address, size) != 0;
}

/* Reads a File 1 field given its Japanese address. On the U.S. release the
   address is translated through F1USAddr.h and unmapped fields read as zero. */
void ReadF1(int address, void* buffer, SIZE_T size)
{
	if (F1_Release == F1_RELEASE_US)
	{
		address = F1_US_Translate(address, (int)size);
		if (address == 0)
		{
			memset(buffer, 0, size);
			return;
		}
	}
	ReadProcessMemory(ProcessHandle, (char *)BasePointer+address, buffer, size, NULL);
}

/* Reads a File 2 address that the tracker also reads while File 1 is loaded.
   These have no U.S. File 1 mapping, so they read as zero on that release. */
void ReadLegacyF2(int address, void* buffer, SIZE_T size)
{
	if (F1_Release == F1_RELEASE_US)
	{
		memset(buffer, 0, size);
		return;
	}
	ReadProcessMemory(ProcessHandle, (char *)BasePointer+address, buffer, size, NULL);
}

const char* GetReleaseName()
{
	if (info.CurrentFile != 1)
		return "";
	return F1_Release == F1_RELEASE_US ? "us" : "jp";
}

/* U.S.-only structures do not have a direct Japanese address translation. */
static int ReadUSFile1(int address, void* buffer, SIZE_T size)
{
	memset(buffer, 0, size);
	if (address < 0 || size > 0x2000000 || (SIZE_T)address > 0x2000000 - size)
		return 0;
	if (!ReadProcessMemory(ProcessHandle, (char*)BasePointer+address, buffer, size, NULL))
	{
		memset(buffer, 0, size);
		return 0;
	}
	return 1;
}

unsigned short GetSlotNum(int slotNum)
{
  unsigned short buffer;
  int bytesRead = 0;
  if (info.CurrentFile == 1)
      ReadF1(F1_GetLobbyAddress(slotNum), &buffer, 2);
  else
      ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetLobbyAddress(slotNum), &buffer, 2, NULL);
  return buffer;
}

unsigned short GetSlotPlayer(int slotNum)
{
  unsigned short buffer;
  int bytesRead = 0;
  if (info.CurrentFile == 1)
      ReadF1(F1_GetLobbyAddress(slotNum) + F2_SlotPlayer, &buffer, 2);
  else
      ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetLobbyAddress(slotNum) + F2_SlotPlayer, &buffer, 2, NULL);
  return buffer;
}

unsigned short GetSlotMaxPlayer(int slotNum)
{
  unsigned short buffer;
  int bytesRead = 0;
  if (info.CurrentFile == 1)
      ReadF1(F1_GetLobbyAddress(slotNum) + F2_SlotMaxPlayer, &buffer, 2);
  else
      ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetLobbyAddress(slotNum) + F2_SlotMaxPlayer, &buffer, 2, NULL);
  return buffer;
}

unsigned char GetSlotStatus(int slotNum)
{
  unsigned char buffer;
  int bytesRead = 0;
  if (info.CurrentFile == 1)
      ReadF1(F1_GetLobbyAddress(slotNum) + F2_SlotStatus, &buffer, 1);
  else
      ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetLobbyAddress(slotNum) + F2_SlotStatus, &buffer, 1, NULL);
  return buffer;
}

unsigned char GetSlotPass(int slotNum)
{
  unsigned char buffer;
  int bytesRead = 0;
  if (info.CurrentFile == 1)
      ReadF1(F1_GetLobbyAddress(slotNum) + F2_SlotPass, &buffer, 1);
  else
      ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetLobbyAddress(slotNum) + F2_SlotPass, &buffer, 1, NULL);
  return buffer;
}

unsigned short GetSlotScenarioID(int slotNum)
{
	unsigned short buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
	    ReadF1(F1_GetLobbyAddress(slotNum) + F2_SlotScenarioID, &buffer, 2);
	else
	    ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetLobbyAddress(slotNum) + F2_SlotScenarioID, &buffer, 2, NULL);
	return buffer;
}

unsigned short GetSlotVersion(int slotNum)
{
	unsigned short buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
	    ReadF1(F1_GetLobbyAddress(slotNum) + F2_SlotVersion, &buffer, 2);
	else
	    ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetLobbyAddress(slotNum) + F2_SlotVersion, &buffer, 2, NULL);
	return buffer;
}

unsigned char GetHostStatus()
{
	unsigned char buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
	    ReadF1(F1_HostStatus, &buffer, 1);
	else
	    ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_HostStatus, &buffer, 1, NULL);
	return buffer;
}

unsigned short GetHostMaxPlayer()
{
	unsigned short buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
	    ReadF1(F1_HostMaxPlayer, &buffer, 2);
	else
	    ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_HostMaxPlayer, &buffer, 2, NULL);
	return buffer;
}

unsigned short GetHostPlayer()
{
	unsigned short buffer = 0;
	int bytesRead = 0;
	if (info.CurrentFile == 1 && F1_Release == F1_RELEASE_US)
	{
		unsigned char owner = 0, room = 0, status = 0;
		unsigned char ownerAfter = 0, roomAfter = 0, statusAfter = 0;
		unsigned short entry[2] = {0, 0};
		if (!ReadUSFile1(F1_US_HostStatus, &status, 1) || status != 4 ||
			!ReadUSFile1(F1_US_HostOwner, &owner, 1) || owner != 1 ||
			!ReadUSFile1(F1_US_CurrentRoom, &room, 1) || room < 1 || room > 30)
			return 0;
		if (!ReadUSFile1(F1_US_RoomPlayerCount + (room-1)*F1_US_RoomEntrySize, entry, sizeof(entry)) ||
			entry[1] < 2 || entry[1] > 4 || entry[0] < 1 || entry[0] > entry[1])
			return 0;
		/* The lobby overlay and selected room can change between reads. */
		if (!ReadUSFile1(F1_US_HostStatus, &statusAfter, 1) || statusAfter != status ||
			!ReadUSFile1(F1_US_HostOwner, &ownerAfter, 1) || ownerAfter != owner ||
			!ReadUSFile1(F1_US_CurrentRoom, &roomAfter, 1) || roomAfter != room)
			return 0;
		return entry[0];
	}
	if (info.CurrentFile == 1)
	    ReadF1(F1_HostPlayer, &buffer, 2);
	else
	    ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_HostPlayer, &buffer, 2, NULL);
	return buffer;
}

unsigned short GetHostTime()
{
	unsigned short buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
	    ReadF1(F1_HostTime, &buffer, 2);
	else
	    ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_HostTime, &buffer, 2, NULL);
	return buffer;
}

unsigned short GetHostScenarioID()
{
	unsigned short buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
	    ReadF1(F1_HostScenarioID, &buffer, 2);
	else
	    ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_HostScenarioID, &buffer, 2, NULL);
	return buffer;
}

unsigned short GetHostDifficulty()
{
	unsigned short buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
	    ReadF1(F1_HostDifficulty, &buffer, 2);
	else
	    ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_HostDifficulty, &buffer, 2, NULL);
	return buffer;
}

/* slot player enable */
char GetSlotCharacterEnabled(int characterID)
{
    char buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
		ReadF1(F1_GetSlotCharAddress(characterID), &buffer, 1);
	else
		ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetSlotCharAddress(characterID) + 6, &buffer, 1, NULL);
	return buffer;
}

/* 0=main char 1=npc */
char GetSlotNPCType(int characterID)
{
	char buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
		ReadF1(F1_GetSlotCharAddress(characterID) + 230, &buffer, 1);
	else
		ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetSlotCharAddress(characterID) + 2, &buffer, 1, NULL);
	return buffer;
}
/* slot player name */
char GetSlotNameID(int characterID)
{
    char buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
		ReadF1(F1_GetSlotCharAddress(characterID) + 228, &buffer, 1);
	else
		ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetSlotCharAddress(characterID), &buffer, 1, NULL);
	return buffer;
}

unsigned short GetScenarioID()
{
	unsigned short buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
	    ReadF1(F1_ScenarioIDAddr, &buffer, 2);
	else
	    ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_ScenarioIDAddr, &buffer, 2, NULL);
	return buffer;
}

// The game's own local-player slot (0-based), one byte after the clock. The
// first active player record is not the local player in online rooms.
unsigned char GetLocalSlot()
{
	unsigned char buffer;
	if (info.CurrentFile == 1)
	    ReadF1(F1_LocalSlot, &buffer, 1);
	else
	    ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_LocalSlot, &buffer, 1, NULL);
	return buffer;
}

unsigned int GetFrames()
{
	unsigned int buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
	    ReadF1(F1_FrameCounter, &buffer, 4);
	else
	    ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_FrameCounter, &buffer, 4, NULL);
	return buffer;
}

unsigned char GetCleared()
{
	unsigned char buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
	    ReadF1(F1_Cleared, &buffer, 1);
	else
	    ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_Cleared, &buffer, 1, NULL);
	return buffer;
}

unsigned short GetWTTime()
{
	unsigned short buffer;
	int bytesRead = 0;
	    ReadLegacyF2(F2_WTTime, &buffer, 2);
	return buffer;
}

unsigned short GetEscapeTime()
{
	unsigned short buffer;
	int bytesRead = 0;
	    ReadLegacyF2(F2_EscapeTime, &buffer, 2);
	return buffer;
}

unsigned int GetFightTime()
{
	unsigned int buffer;
	int bytesRead = 0;
	    ReadLegacyF2(F2_DTFightTime, &buffer, 4);
	return buffer;
}

unsigned short GetFightTime2()
{
	unsigned short buffer;
	int bytesRead = 0;
	    ReadLegacyF2(F2_DTFightTime2, &buffer, 2);
	return buffer;
}

unsigned int GetGarageTime()
{
	unsigned int buffer;
	int bytesRead = 0;
	    ReadLegacyF2(F2_DTGarageTime, &buffer, 4);
	return buffer;
}

unsigned int GetGasTime()
{
	unsigned int buffer;
	int bytesRead = 0;
	    ReadLegacyF2(F2_DTGasTime, &buffer, 4);
	return buffer;
}

unsigned int GetGasFlag()
{
	unsigned int buffer;
	int bytesRead = 0;
	    ReadLegacyF2(F2_DTGasFlag, &buffer, 4);
	return buffer;
}

unsigned char GetGasRandom()
{
	unsigned char buffer;
	int bytesRead = 0;
	    ReadLegacyF2(F2_DTGasRandom, &buffer, 1);
	return buffer;
}

unsigned char GetItemRandom()
{
	unsigned char buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
	    ReadF1(F1_ItemRandom, &buffer, 1);
	else
	    ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_ItemRandom, &buffer, 1, NULL);
	return buffer;
}

unsigned char GetItemRandom2()
{
	unsigned char buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
	    ReadF1(F1_ItemRandom2, &buffer, 1);
	else
	    ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_ItemRandom2, &buffer, 1, NULL);
	return buffer;
}

unsigned char GetPuzzleRandom()
{
	unsigned char buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
	    ReadF1(F1_PuzzleRandom, &buffer, 1);
	else
	    ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_PuzzleRandom, &buffer, 1, NULL);
	return buffer;
}

/* File 1 SP item set selector; File 2 has no SP sets. */
void UpdateSPSet()
{
	unsigned char buffer = 0;
	info.SPSetAvailable = info.CurrentFile == 1 && F1_IsMapped(F1_SPSetSelector, 1);
	if (info.SPSetAvailable)
	    ReadF1(F1_SPSetSelector, &buffer, 1);
	info.SPSetSelector = buffer;
}

unsigned char GetCoin()
{
	unsigned char buffer1;
	unsigned char buffer2;
	unsigned char buffer3;
	unsigned char buffer4;
	int bytesRead = 0;
	    ReadLegacyF2(F2_Coin, &buffer1, 1);
	    ReadLegacyF2(F2_Coin+2, &buffer2, 1);
	    ReadLegacyF2(F2_Coin+4, &buffer3, 1);
	    ReadLegacyF2(F2_Coin+6, &buffer4, 1);
	return buffer1+buffer2+buffer3+buffer4;
}

unsigned char GetKilledZombies()
{
	unsigned char buffer;
	int bytesRead = 0;
	    ReadLegacyF2(F2_KilledZombie, &buffer, 1);
	return buffer;
}

unsigned char GetPassWT()
{
	unsigned char buffer;
	int bytesRead = 0;
	    ReadLegacyF2(F2_PassWT, &buffer, 1);
	return buffer;
}

unsigned short GetPassDT1()
{
	unsigned short buffer;
	int bytesRead = 0;
	    ReadLegacyF2(F2_PassDT1, &buffer, 2);
	return buffer;
}

unsigned char GetPassDT2()
{
	unsigned char buffer;
	int bytesRead = 0;
	    ReadLegacyF2(F2_PassDT2, &buffer, 1);
	return buffer;
}

unsigned char GetPassDT3()
{
	unsigned char buffer;
	int bytesRead = 0;
	    ReadLegacyF2(F2_PassDT3, &buffer, 1);
	return buffer;
}

unsigned char GetPass1()
{
	unsigned char buffer;
	int bytesRead = 0;
	    ReadF1(F1_Pass1, &buffer, 1);
	return buffer;
}

unsigned char GetPass2()
{
	unsigned char buffer;
	int bytesRead = 0;
	    ReadF1(F1_Pass2, &buffer, 1);
	return buffer;
}

unsigned char GetPass3()
{
	unsigned char buffer = 0;
	int bytesRead = 0;
	if (info.CurrentFile == 1 && F1_Release == F1_RELEASE_US && info.ScenarioID != 41)
		return 0;
	    ReadF1(F1_Pass3, &buffer, 1);
	return buffer;
}

unsigned short GetPassUB1()
{
	unsigned short buffer;
	int bytesRead = 0;
	    ReadLegacyF2(F2_PassUB1, &buffer, 2);
	return buffer;
}

unsigned char GetPassUB2()
{
	unsigned char buffer;
	int bytesRead = 0;
	    ReadLegacyF2(F2_PassUB2, &buffer, 1);
	return buffer;
}

unsigned char GetPassUB3()
{
	unsigned char buffer;
	int bytesRead = 0;
	    ReadLegacyF2(F2_PassUB3, &buffer, 1);
	return buffer;
}

unsigned short GetPass4()
{
	unsigned short buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
	    ReadF1(F1_Pass4, &buffer, 2);
	else
	    ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_Pass4, &buffer, 2, NULL);
	return buffer;
}

unsigned char GetPass5()
{
	unsigned char buffer;
	int bytesRead = 0;
	    ReadF1(F1_Pass5, &buffer, 1);
	return buffer;
}

unsigned char GetPass6()
{
	unsigned char buffer = 0;
	int bytesRead = 0;
	if (info.CurrentFile == 1 && F1_Release == F1_RELEASE_US && info.ScenarioID != 41)
		return 0;
	    ReadF1(F1_Pass6, &buffer, 1);
	return buffer;
}

void UpdateHiveCodes()
{
	unsigned char digits[24] = {0}, after[24] = {0};
	unsigned int b2fInstruction = 0, roofInstruction = 0;
	unsigned short scenarioAfter = 0;
	unsigned char stateAfter = 0;
	char updateTag[sizeof(F1_US_UpdateTagText)-1];
	info.HiveCodesAvailable = 0;
	info.HiveB2FCode = 0;
	info.HiveRoofCode = 0;
	if (info.CurrentFile != 1 || F1_Release != F1_RELEASE_US || info.ScenarioID != 28 ||
		info.FrameCounter == 0 || info.Cleared < 2 || info.Cleared > 4)
		return;
	if (!ReadUSFile1(F1_US_UpdateTag, updateTag, sizeof(updateTag)) ||
		memcmp(updateTag, F1_US_UpdateTagText, sizeof(updateTag)) != 0 ||
		!ReadUSFile1(F1_US_HiveB2FCompare, &b2fInstruction, 4) || b2fInstruction != F1_US_HiveB2FInstruction ||
		!ReadUSFile1(F1_US_HiveRoofCompare, &roofInstruction, 4) || roofInstruction != F1_US_HiveRoofInstruction ||
		!ReadUSFile1(F1_US_HiveCodes, digits, sizeof(digits)))
		return;
	for (int i = 0; i < 24; i++)
		if (digits[i] > 9)
			return;
	for (int i = 0; i < 4; i++)
		if (digits[i] != digits[i+4] || digits[i] != digits[i+8] ||
			digits[i+12] != digits[i+16] || digits[i+12] != digits[i+20])
			return;
	/* Reject an overlay replacement or a partial code-table rewrite. */
	if (!ReadUSFile1(0x3243DA, &scenarioAfter, 2) || scenarioAfter != info.ScenarioID ||
		!ReadUSFile1(0x4BADD0, &stateAfter, 1) || stateAfter < 2 || stateAfter > 4 ||
		!ReadUSFile1(F1_US_HiveCodes, after, sizeof(after)) || memcmp(digits, after, sizeof(digits)) != 0)
		return;
	for (int i = 0; i < 4; i++)
	{
		info.HiveB2FCode = info.HiveB2FCode*10 + digits[i];
		info.HiveRoofCode = info.HiveRoofCode*10 + digits[i+12];
	}
	if (info.HiveB2FCode == 0 || info.HiveRoofCode == 0)
	{
		info.HiveB2FCode = 0;
		info.HiveRoofCode = 0;
		return;
	}
	info.HiveCodesAvailable = 1;
}

unsigned char GetDifficulty()
{
	unsigned char buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
	    ReadF1(F1_Difficulty, &buffer, 1);
	else
		ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_Difficulty, &buffer, 1, NULL);
	return buffer;
}
/*
unsigned int GetE1HP()//enemy HP
{
	unsigned int Pointer;
	unsigned short buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
	{
		ReadProcessMemory(ProcessHandle, (char *)F1_Pointer, &Pointer,4,0);
	    ReadProcessMemory(ProcessHandle, (char *)Pointer+0x20000000 + F1_EHPOffset, &buffer, 2, NULL);
	}
	else
	{
		ReadProcessMemory(ProcessHandle, (char *)F2_Pointer, &Pointer,4,0);
		ReadProcessMemory(ProcessHandle, (char *)Pointer+0x20000000 + F2_EHPOffset, &buffer, 2, NULL);
	}
	return buffer;
}
*/
void UpdatePickups()
{
    for (int i=0; i < 255; i++)
    {
        unsigned char numberBuffer;
        unsigned short typeBuffer;
        unsigned short countBuffer;
        unsigned short pickBuffer;
        unsigned int presentBuffer;
        unsigned char mixBuffer;
        unsigned char roomidBuffer;
        float positionXBuffer = 0, positionYBuffer = 0;
        int bytesRead = 0;
        if (info.CurrentFile == 1)
        {
            ReadF1(F1_PickupSpaceStart + (F1_PickupStructSize * i) + F1_NumberOffset, &numberBuffer, 1);
            ReadF1(F1_PickupSpaceStart + (F1_PickupStructSize * i) + F1_IDOffset, &typeBuffer, 2);
            ReadF1(F1_PickupSpaceStart + (F1_PickupStructSize * i) + F1_PickupCountOffset, &countBuffer, 2);
            ReadF1(F1_PickupSpaceStart + (F1_PickupStructSize * i) + F1_PickupOffset, &pickBuffer, 2);
            ReadF1(F1_PickupSpaceStart + (F1_PickupStructSize * i) + F1_PresentOffset, &presentBuffer, 4);
            ReadF1(F1_PickupSpaceStart + (F1_PickupStructSize * i) + F1_MixOffset, &mixBuffer, 1);
            ReadF1(F1_PickupSpaceStart + (F1_PickupStructSize * i) + F1_ItemRoomIDOffset, &roomidBuffer, 1);
            ReadF1(F1_PickupSpaceStart + (F1_PickupStructSize * i) + F1_ItemPositionXOffset, &positionXBuffer, 4);
            ReadF1(F1_PickupSpaceStart + (F1_PickupStructSize * i) + F1_ItemPositionYOffset, &positionYBuffer, 4);
        }
        else if (info.CurrentFile == 2)
        {
            ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_PickupSpaceStart + (F2_PickupStructSize * i) + F2_NumberOffset, &numberBuffer, 1, NULL);
            ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_PickupSpaceStart + (F2_PickupStructSize * i) + F2_IDOffset, &typeBuffer, 2, NULL);
            ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_PickupSpaceStart + (F2_PickupStructSize * i) + F2_PickupCountOffset, &countBuffer, 2, NULL);
            ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_PickupSpaceStart + (F2_PickupStructSize * i) + F2_PickupOffset, &pickBuffer, 2, NULL);
            ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_PickupSpaceStart + (F2_PickupStructSize * i) + F2_PresentOffset, &presentBuffer, 4, NULL);
            ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_PickupSpaceStart + (F2_PickupStructSize * i) + F2_MixOffset, &mixBuffer, 1, NULL);
            ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_PickupSpaceStart + (F2_PickupStructSize * i) + F2_ItemRoomIDOffset, &roomidBuffer, 1, NULL);
            ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_PickupSpaceStart + (F2_PickupStructSize * i) + F2_ItemPositionXOffset, &positionXBuffer, 4, NULL);
            ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_PickupSpaceStart + (F2_PickupStructSize * i) + F2_ItemPositionYOffset, &positionYBuffer, 4, NULL);
        }
        Items[i].Number = numberBuffer;
        Items[i].ID = i+1;
        Items[i].Type = typeBuffer;
        Items[i].Count = countBuffer;
        Items[i].Pick = pickBuffer;
        Items[i].Present = presentBuffer;
        Items[i].Mix = mixBuffer;
        Items[i].RoomID = roomidBuffer;
        Items[i].PositionX = positionXBuffer;
        Items[i].PositionY = positionYBuffer;
    }
}

unsigned short GetDoorHP(int doorID)
{
  unsigned short buffer;
  int bytesRead = 0;
  if (info.CurrentFile == 1)
      ReadF1(F1_GetDoorHP(doorID), &buffer, 2);
  else
      ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetDoorHP(doorID), &buffer, 2, NULL);
  return buffer;
}

unsigned short GetDoorFlag(int doorID)
{
  unsigned short buffer;
  int bytesRead = 0;
  if (info.CurrentFile == 1)
      ReadF1(F1_GetDoorFlag(doorID), &buffer, 2);
  else
      ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetDoorFlag(doorID), &buffer, 2, NULL);
  return buffer;
}

unsigned short GetRoomID(int characterID)
{
  unsigned short buffer;
  int bytesRead = 0;
  if (info.CurrentFile == 1)
      ReadF1(F1_GetCharAddress(characterID) + F1_RoomIDOffset, &buffer, 2);
  else
      ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetCharAddress(characterID) + F2_RoomIDOffset, &buffer, 2, NULL);
  return buffer;
}

unsigned short GetHealth(int characterID)
{
  unsigned short buffer;
  int bytesRead = 0;
  if (info.CurrentFile == 1)
      ReadF1(F1_GetCharAddress(characterID) + F1_HPOffset, &buffer, 2);
  else
      ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetCharAddress(characterID) + F2_HPOffset, &buffer, 2, NULL);
  return buffer;
}

unsigned short GetMaxHealth(int characterID)
{
  unsigned short buffer;
  int bytesRead = 0;
  if (info.CurrentFile == 1)
      ReadF1(F1_GetCharAddress(characterID) + F1_MaxHPOffset, &buffer, 2);
  else
      ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetCharAddress(characterID) + F2_MaxHPOffset, &buffer, 2, NULL);
  return buffer;
}

char GetCharacterType(int characterID)
{
	char buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
		ReadF1(F1_GetCharAddress(characterID) + F1_CharacterTypeOffset, &buffer, 1);
	else
		ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetCharAddress(characterID) + F2_CharacterTypeOffset, &buffer, 1, NULL);
	return buffer;
}

char* GetInventory(int characterID)
{
	char* buffer = malloc(4);
	int bytesRead = 0;
	if (info.CurrentFile == 1)
		ReadF1(F1_GetCharAddress(characterID) + F1_InventoryOffset, buffer, 4);
	else
		ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetCharAddress(characterID) + F2_InventoryOffset, buffer, 4, NULL);
	return buffer;
}

char GetSpecialItem(int characterID)
{
	char buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
		ReadF1(F1_GetCharAddress(characterID) + F1_InventoryOffset + 4, &buffer, 1);
	else
		ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetCharAddress(characterID) + F2_InventoryOffset + 4, &buffer, 1, NULL);
	return buffer;
}

char* GetSpecialInventory(int characterID)
{
	char* buffer = malloc(4);
	int bytesRead = 0;
	if (info.CurrentFile == 1)
		ReadF1(F1_GetCharAddress(characterID) + F1_InventoryOffset + 5, buffer, 4);
	else
		ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetCharAddress(characterID) + F2_InventoryOffset + 5, buffer, 4, NULL);
	return buffer;
}

char* GetDeadInventory(int characterID)
{
	char* buffer = malloc(4);
	int bytesRead = 0;
	if (info.CurrentFile == 1)
		ReadF1(F1_DeadInventoryStart + 8*characterID, buffer, 4);
	else
		ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_DeadInventoryStart + 8*characterID, buffer, 4, NULL);
	return buffer;
}

char* GetDeadSpecialInventory(int characterID)
{
	char* buffer = malloc(4);
	int bytesRead = 0;
	if (info.CurrentFile == 1)
		ReadF1(F1_DeadInventoryStart + 8*characterID + 4, buffer, 4);
	else
		ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_DeadInventoryStart + 8*characterID + 4, buffer, 4, NULL);
	return buffer;
}

void GetCindyBag(int cid)
{
	if (Players[cid].CharacterType == 7)
	{
		unsigned char* buffer = malloc(36);
		int bytesRead = 0;
		if (info.CurrentFile == 1)
			ReadF1(F1_GetCharAddress(cid) + F1_InventoryOffset + 5, buffer, 36);
		else
			ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetCharAddress(cid) + F2_InventoryOffset + 5, buffer, 36, NULL);
		
		/* Warning! Unexplainable magic below! */
		for (int i=0; i < 4; i++)
		{
			unsigned char* ptr = buffer+i*9;
			Players[cid].CindyBag[i].ID = *ptr;
			if ((*ptr) != 0x00)
			{
				if (i != 3)
				{
					Players[cid].CindyBag[i].Count = 0;
					for (int j=0; j < 9; j++)
					{
						if (*(ptr+j) != 0x00)
						{
							Players[cid].CindyBag[i].Type = Items[*(ptr+j)-1].Type;
							Players[cid].CindyBag[i].Count += Items[*(ptr+j)-1].Count;
						}
					}
				}
				else
				{
					Players[cid].CindyBag[i].Type = Items[(*ptr)-1].Type;
					Players[cid].CindyBag[i].Count = 1;
				}
			}
		}

		free(buffer);
		buffer = NULL;
	}
}

unsigned short GetBleedTime(int characterID)
{
  unsigned short buffer;
  int bytesRead = 0;
  if (info.CurrentFile == 1)
      ReadF1(F1_GetCharAddress(characterID) + F1_BleedTimeOffset, &buffer, 2);
  else
      ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetCharAddress(characterID) + F2_BleedTimeOffset, &buffer, 2, NULL);
  return buffer;
}

unsigned short GetAntiVirusGTime(int characterID)
{
  unsigned short buffer;
  int bytesRead = 0;
  if (info.CurrentFile == 1)
      ReadF1(F1_GetCharAddress(characterID) + F1_AntiVirusGTimeOffset, &buffer, 2);
  return buffer;
}

unsigned short GetHerbTime(int characterID)
{
  unsigned short buffer;
  int bytesRead = 0;
  if (info.CurrentFile == 1)
      ReadF1(F1_GetCharAddress(characterID) + F1_HerbTimeOffset, &buffer, 2);
  else
      ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetCharAddress(characterID) + F2_HerbTimeOffset, &buffer, 2, NULL);
  return buffer;
}

unsigned short GetAntiVirusTime(int characterID)
{
  unsigned short buffer;
  int bytesRead = 0;
  if (info.CurrentFile == 1)
      ReadF1(F1_GetCharAddress(characterID) + F1_AntiVirusTimeOffset, &buffer, 2);
  else
      ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetCharAddress(characterID) + F2_AntiVirusTimeOffset, &buffer, 2, NULL);
  return buffer;
}

double GetPower(int characterID)
{
  float buffer;
  int bytesRead = 0;
  if (info.CurrentFile == 1)
      ReadF1(F1_GetCharAddress(characterID) + F1_PowerOffset, &buffer, 4);
  else
      ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetCharAddress(characterID) + F2_PowerOffset, &buffer, 4, NULL);
  return (double)buffer;
}

double GetSize(int characterID)
{
  float buffer;
  int bytesRead = 0;
  if (info.CurrentFile == 1)
      ReadF1(F1_GetCharAddress(characterID) + F1_SizeOffset, &buffer, 4);
  else
      ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetCharAddress(characterID) + F2_SizeOffset, &buffer, 4, NULL);
  return (double)buffer;
}

double GetSpeed(int characterID)
{
  float buffer;
  int bytesRead = 0;
  if (info.CurrentFile == 1)
      ReadF1(F1_GetCharAddress(characterID) + F1_SpeedOffset, &buffer, 4);
  else
      ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetCharAddress(characterID) + F2_SpeedOffset, &buffer, 4, NULL);
  return (double)buffer;
}
double GetPositionX(int characterID)
{
  float buffer;
  int bytesRead = 0;
  if (info.CurrentFile == 1)
      ReadF1(F1_GetCharAddress(characterID) + F1_PositionX, &buffer, 4);
  else
      ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetCharAddress(characterID) + F2_PositionX, &buffer, 4, NULL);
  return (double)buffer;
}

// Facing: the player transform's forward axis in map coordinates is
// (+0x70, +0x50). It matched the walking direction (median 6 degrees) in a
// Japanese File 2 run and SP prompt reach in a U.S. File 1 run.
double GetForward(int characterID, int f1Offset, int f2Offset)
{
  float buffer;
  if (info.CurrentFile == 1)
      ReadF1(F1_GetCharAddress(characterID) + f1Offset, &buffer, 4);
  else
      ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetCharAddress(characterID) + f2Offset, &buffer, 4, NULL);
  return (double)buffer;
}

double GetPositionY(int characterID)
{
  float buffer;
  int bytesRead = 0;
  if (info.CurrentFile == 1)
      ReadF1(F1_GetCharAddress(characterID) + F1_PositionY, &buffer, 4);
  else
      ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetCharAddress(characterID) + F2_PositionY, &buffer, 4, NULL);
  return (double)buffer;
}

double GetPercentage(int characterID)
{
	int currentBuffer;
	int maxBuffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
	{
		ReadF1(F1_GetCharAddress(characterID) + F1_VirusOffset, &currentBuffer, 4);
		ReadF1(F1_VirusMaxStart + 4 * Players[characterID].CharacterType, &maxBuffer, 4);
	}
	else
	{
		ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetCharAddress(characterID) + F2_VirusOffset, &currentBuffer, 4, NULL);
		ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_VirusMaxStart + 4 * Players[characterID].CharacterType, &maxBuffer, 4, NULL);
	}

	return (double)currentBuffer/(double)maxBuffer*100.0;
}

double GetCritBonus(int characterID)
{
	float buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
		ReadF1(F1_GetCharAddress(characterID) + F1_CritBonusOffset, &buffer, 4);
	else
		ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetCharAddress(characterID) + F2_CritBonusOffset, &buffer, 4, NULL);
	return (double)buffer;
}

char GetNameID(int characterID)
{
    char buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
		ReadF1(F1_GetCharAddress(characterID) + F1_NameTypeOffset, &buffer, 1);
	else
		ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetCharAddress(characterID) + F2_NameTypeOffset, &buffer, 1, NULL);
	return buffer;
}

char GetEquippedItem(int characterID)
{
    char buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
		ReadF1(F1_GetCharAddress(characterID) + F1_EquippedItemOffset, &buffer, 1);
	else
		ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetCharAddress(characterID) + F2_EquippedItemOffset, &buffer, 1, NULL);
	return buffer;
}

char GetCharacterStatus(int characterID)
{
    char buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
		ReadF1(F1_GetCharAddress(characterID) + F1_CharacterStatusOffset, &buffer, 1);
	else
		ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetCharAddress(characterID) + F2_CharacterStatusOffset, &buffer, 1, NULL);
	return buffer;
}

char GetCharacterEnabled(int characterID)
{
    char buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
		ReadF1(F1_GetCharAddress(characterID) + F1_CharacterEnabled, &buffer, 1);
	else
		ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetCharAddress(characterID) + F2_CharacterEnabled, &buffer, 1, NULL);
	return buffer;
}

char GetCharacterInGame(int characterID)
{
    char buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
		ReadF1(F1_GetCharAddress(characterID) + F1_CharacterInGame, &buffer, 1);
	else
		ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetCharAddress(characterID) + F2_CharacterInGame, &buffer, 1, NULL);
	return buffer;
}

void UpdateRoomMasters()
{
	unsigned char buffer[128 * MAX_PLAYER_SLOTS];
	Rooms.Enabled = false;
	memset(Rooms.Room, 0, sizeof(Rooms.Room));
	if (info.CurrentFile != 1 && info.CurrentFile != 2)
		return;
	if (info.CurrentFile == 1 && !F1_IsMapped(F1_RoomPriorty, 128 * MAX_PLAYER_SLOTS))
		return;

	if (info.CurrentFile == 1)
	{
		if (F1_Release == F1_RELEASE_US)
		{
			unsigned int code[7];
			unsigned int codeAfter[7];
			unsigned char after[sizeof(buffer)];
			unsigned short scenarioAfter = 0;
			unsigned char stateAfter = 0;
			if (info.FrameCounter == 0 || info.Cleared < 2 || info.Cleared > 4 ||
				!ReadUSFile1(F1_US_RoomPriorityLookup, code, sizeof(code)) ||
				code[0] != 0x3C020081 || code[4] != 0x24425830 || code[6] != 0x90420000)
				return;
			int address = F1_US_Translate(F1_RoomPriorty, sizeof(buffer));
			if (!ReadUSFile1(address, buffer, sizeof(buffer)) ||
				!ReadUSFile1(address, after, sizeof(after)) || memcmp(buffer, after, sizeof(buffer)) != 0 ||
				!ReadUSFile1(F1_US_RoomPriorityLookup, codeAfter, sizeof(codeAfter)) || memcmp(code, codeAfter, sizeof(code)) != 0 ||
				!ReadUSFile1(0x3243DA, &scenarioAfter, 2) || scenarioAfter != info.ScenarioID ||
				!ReadUSFile1(0x4BADD0, &stateAfter, 1) || stateAfter < 2 || stateAfter > 4)
				return;
		}
		else if (!ReadProcessMemory(ProcessHandle, (char*)BasePointer + F1_RoomPriorty, buffer, sizeof(buffer), NULL))
			return;
	}
	else if (!ReadProcessMemory(ProcessHandle, (char*)BasePointer + F2_RoomPriorty, buffer, sizeof(buffer), NULL))
		return;

	/* An unloaded or partially replaced table must not produce crowns. */
	for (int i = 0; i < sizeof(buffer); i++)
	{
		if (buffer[i] > 3 && buffer[i] != 0xFF)
			return;
	}
	for (int i = 0; i < 128; i++)
		Rooms.Room[i].RoomMaster = buffer[i * 4] < 4 ? buffer[i * 4] + 1 : 0;
	Rooms.Enabled = true;
}

void GetRoomItemF1()
{
		if (!F1_IsMapped(F1_RoomItem, 4))
		{
			/* No room-item pointer is known for this release; leave the list empty. */
			memset(RItems, 0, sizeof(RItems));
			return;
		}

		int Pointer;
		ReadF1(F1_RoomItem, &Pointer, 4);

		/* The pointer is 0 or stale while rooms load; only read a window inside EE RAM. */
		int windowStart = Pointer+0x40-(196*MAX_ITEM/2);
		if (Pointer == 0 || windowStart < 0 || windowStart + 196*MAX_ITEM > 0x2000000)
		{
			memset(RItems, 0, sizeof(RItems));
			return;
		}

		unsigned char* buffer = malloc(196*MAX_ITEM);
		int bytesRead = 0;

		ReadProcessMemory(ProcessHandle, (char *)BasePointer+windowStart, buffer, 196*MAX_ITEM, NULL);

		/* Warning! Unexplainable magic below! */
		for (int i=0; i < MAX_ITEM; i++)
		{
			unsigned char* ptr = buffer+i*196;
			unsigned short* ptr2 = buffer+10+i*196;
			RItems->RItem[i].ID = *ptr;
			RItems->RItem[i].EN = *ptr2;
			if ((*ptr) != 0x00)
			{
				RItems->RItem[i].Count = 0;
				RItems->RItem[i].Pick = 0;
				RItems->RItem[i].Present = 0;
				RItems->RItem[i].Mix = 0;
				RItems->RItem[i].PositionX = 0;
				RItems->RItem[i].PositionY = 0;
				for (int j=0; j < 1; j++)
				{
					if (*(ptr+j) != 0x00)
					{
						RItems->RItem[i].Type = Items[*(ptr+j)-1].Type;
						RItems->RItem[i].Count = Items[*(ptr+j)-1].Count;
						RItems->RItem[i].Pick = Items[*(ptr+j)-1].Pick;
						RItems->RItem[i].Present = Items[*(ptr+j)-1].Present;
						RItems->RItem[i].Mix = Items[*(ptr+j)-1].Mix;
						RItems->RItem[i].PositionX = Items[*(ptr+j)-1].PositionX;
						RItems->RItem[i].PositionY = Items[*(ptr+j)-1].PositionY;
					}
				}
			}
		}

		free(buffer);
		buffer = NULL;
}

void GetRoomItemF2()
{
		unsigned int Pointer = 0;
		unsigned char buffer[192*MAX_ITEM];

		/* Do not retain an earlier room when a load or memory read is incomplete. */
		memset(RItems, 0, sizeof(RItems));
		if (!ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_RoomItem, &Pointer, 4, NULL))
			return;

		/* Validate the pointer before arithmetic, then the entire 32-record window. */
		if (Pointer == 0 || Pointer >= 0x2000000)
			return;
		int windowStart = (int)Pointer+0x40-(192*MAX_ITEM/2);
		if (windowStart < 0 || windowStart > 0x2000000-192*MAX_ITEM)
			return;
		if (!ReadProcessMemory(ProcessHandle, (char *)BasePointer+windowStart, buffer, sizeof(buffer), NULL))
			return;

		/* Warning! Unexplainable magic below! */
		for (int i=0; i < MAX_ITEM; i++)
		{
			unsigned char* ptr = buffer+(i)*192;
			unsigned short* ptr2 = buffer+10+(i)*192;
			RItems->RItem[i].ID = *ptr;
			RItems->RItem[i].EN = *ptr2;
			if ((*ptr) != 0x00)
			{
				RItems->RItem[i].Count = 0;
				RItems->RItem[i].Pick = 0;
				RItems->RItem[i].Present = 0;
				RItems->RItem[i].Mix = 0;
				RItems->RItem[i].PositionX = 0;
				RItems->RItem[i].PositionY = 0;
				for (int j=0; j < 1; j++)
				{
					if (*(ptr+j) != 0x00)
					{
						RItems->RItem[i].Type = Items[*(ptr+j)-1].Type;
						RItems->RItem[i].Count = Items[*(ptr+j)-1].Count;
						RItems->RItem[i].Pick = Items[*(ptr+j)-1].Pick;
						RItems->RItem[i].Present = Items[*(ptr+j)-1].Present;
						RItems->RItem[i].Mix = Items[*(ptr+j)-1].Mix;
						RItems->RItem[i].PositionX = Items[*(ptr+j)-1].PositionX;
						RItems->RItem[i].PositionY = Items[*(ptr+j)-1].PositionY;
					}
				}
			}
		}
}

char GetEnemyNameID(int enemyID)
{
    char buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
		ReadF1(F1_GetEnemyAddress(enemyID) + F1_EnemyNameIDOffset, &buffer, 1);
	else
		ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetEnemyAddress(enemyID) + F2_EnemyNameIDOffset, &buffer, 1, NULL);
	return buffer;
}

char GetEnemyType(int enemyID)
{
	char buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
		ReadF1(F1_GetEnemyAddress(enemyID) + F1_EnemyTypeOffset, &buffer, 1);
	else
		ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetEnemyAddress(enemyID) + F2_EnemyTypeOffset, &buffer, 1, NULL);
	return buffer;
}

unsigned short GetEnemyHealth(int enemyID)
{
  unsigned short buffer;
  int bytesRead = 0;
  if (info.CurrentFile == 1)
      ReadF1(F1_GetEnemyAddress(enemyID) + F1_EHPOffset, &buffer, 2);
  else
      ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetEnemyAddress(enemyID) + F2_EHPOffset, &buffer, 2, NULL);
  return buffer;
}

unsigned short GetEnemyMaxHealth(int enemyID)
{
  unsigned short buffer;
  int bytesRead = 0;
  if (info.CurrentFile == 1)
      ReadF1(F1_GetEnemyAddress(enemyID) + F1_EMaxHPOffset, &buffer, 2);
  else
      ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetEnemyAddress(enemyID) + F2_EMaxHPOffset, &buffer, 2, NULL);
  return buffer;
}

// Enemy slots share the player block layout: float X at +0x38, float map Y
// (the game's Z) at +0x40 and the room ID at +0x1E2. Only enabled, in-game
// slots hold a live position; the others keep stale values.
double GetEnemyPositionX(int enemyID)
{
  float buffer;
  if (info.CurrentFile == 1)
      ReadF1(F1_GetEnemyAddress(enemyID) + F1_PositionX, &buffer, 4);
  else
      ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetEnemyAddress(enemyID) + F2_PositionX, &buffer, 4, NULL);
  return (double)buffer;
}

double GetEnemyPositionY(int enemyID)
{
  float buffer;
  if (info.CurrentFile == 1)
      ReadF1(F1_GetEnemyAddress(enemyID) + F1_PositionY, &buffer, 4);
  else
      ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetEnemyAddress(enemyID) + F2_PositionY, &buffer, 4, NULL);
  return (double)buffer;
}

unsigned char GetEnemyRoomID(int enemyID)
{
  unsigned char buffer;
  if (info.CurrentFile == 1)
      ReadF1(F1_GetEnemyAddress(enemyID) + F1_RoomIDOffset, &buffer, 1);
  else
      ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetEnemyAddress(enemyID) + F2_RoomIDOffset, &buffer, 1, NULL);
  return buffer;
}

char GetEnemyEnabled(int enemyID)
{
    char buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
		ReadF1(F1_GetEnemyAddress(enemyID) + F1_EnemyEnabled, &buffer, 1);
	else
		ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetEnemyAddress(enemyID) + F2_EnemyEnabled, &buffer, 1, NULL);
	return buffer;
}

char GetEnemyInGame(int enemyID)
{
    char buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
		ReadF1(F1_GetEnemyAddress(enemyID) + F1_EnemyInGame, &buffer, 1);
	else
		ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_GetEnemyAddress(enemyID) + F2_EnemyInGame, &buffer, 1, NULL);
	return buffer;
}

void UpdateEnemyList()
{
    for (int i=0; i < 80; i++)
    {
        unsigned char number;
        unsigned char flag;
        unsigned char type;
        unsigned char name;
        unsigned char room;
        unsigned short hp;
        unsigned short maxhp;
        unsigned char status;
        int bytesRead = 0;
        if (info.CurrentFile == 1)
        {
            ReadF1(F1_EnemyListOffset + (0x60 * i), &number, 1);
            ReadF1(F1_EnemyListOffset + (0x60 * i) + 1, &flag, 1);
            ReadF1(F1_EnemyListOffset + (0x60 * i) + 2, &name, 1);
            ReadF1(F1_EnemyListOffset + (0x60 * i) + 3, &type, 1);
            ReadF1(F1_EnemyListOffset + (0x60 * i) + 0x22, &room, 1);
            ReadF1(F1_EnemyListOffset + (0x60 * i) + 0x1C, &hp, 2);
            ReadF1(F1_EnemyListOffset + (0x60 * i) + 0x1E, &maxhp, 2);
            ReadF1(F1_EnemyListOffset + (0x60 * i) + 0x45, &status, 1);
		}
		else if (info.CurrentFile == 2)
		{
            ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_EnemyListOffset + (0x60 * i), &number, 1, NULL);
            ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_EnemyListOffset + (0x60 * i) + 1, &flag, 1, NULL);
            ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_EnemyListOffset + (0x60 * i) + 2, &name, 1, NULL);
            ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_EnemyListOffset + (0x60 * i) + 3, &type, 1, NULL);
            ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_EnemyListOffset + (0x60 * i) + 0x22, &room, 1, NULL);
            ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_EnemyListOffset + (0x60 * i) + 0x1C, &hp, 2, NULL);
            ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_EnemyListOffset + (0x60 * i) + 0x1E, &maxhp, 2, NULL);
            ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_EnemyListOffset + (0x60 * i) + 0x45, &status, 1, NULL);
		}
		Enemies2[i].Number = number;
		Enemies2[i].Flag = flag;
		Enemies2[i].Type = type;
		Enemies2[i].NameID = name;
        Enemies2[i].HP = hp;
		Enemies2[i].MaxHP = maxhp;
		Enemies2[i].RoomID = room;
		Enemies2[i].Status = status;
    }
}

char GetPlayerNum()
{
    unsigned char buffer;
	int bytesRead = 0;
	if (info.CurrentFile == 1)
		ReadF1(F1_PlayerNum, &buffer, 1);
	else
		ReadProcessMemory(ProcessHandle, (char *)BasePointer+F2_PlayerNum, &buffer, 1, NULL);
	return buffer;
}

char* GetStatusText(unsigned char stat)
{
	if (stat == 0x01)
		return "Poison";
	else if (stat == 0x02)
		return "Bleed";
	else if (stat == 0x03)
		return "Poison+Bleed";
	else if (stat == 0x00)
		return "OK";
//0x2000 loading
	if (info.CurrentFile == 1)
	    if (stat >= 0x80)
			return "Zombie";
	    else if (stat >= 0x18 && stat <= 0x1C)
	        return "Down";
	    else if (stat > 0x1C)
	        return "Dead";
	    else if (stat == 0x4)
	        return "Cleared";
	if (info.CurrentFile == 2)
	    if (stat >= 0x30 && stat <= 0x34)
	        return "Zombie";
	    else if (stat >= 0x08 && stat < 0x0C)
	        return "Down";
		else if (stat == 0x0C)
	        return "Down+Gas";
	    else if (stat > 0x0C)
	        return "Dead";
		else if (stat == 0x04)
			return "Gas";
		else if (stat == 0x06)
			return "Gas+Bleed";

	return "unknown";
}

static int LInit (lua_State* L) {
	ProcessID = GetProcessID("pcsx2-qt.exe");
	if (ProcessID == 0)
	{
		ProcessID = GetProcessID("pcsx2-qtx64.exe");
	}
	if (ProcessID == 0)
	{
		ProcessID = GetProcessID("pcsx2-qtx64-avx2.exe");
	}
	if (ProcessID != 0)
	{
		ProcessHandle = OpenProcess(PROCESS_VM_READ, FALSE, ProcessID);
		BindBasePointer();
		lua_pushboolean(L, 1);
	}
	else
		lua_pushboolean(L, 0);
	return 1;
}

static int LUpdateLobby (lua_State* L)
{
	info.CurrentFile = GetFile();
	if (info.CurrentFile == -1)
		return 0;

	for (int i=0; i < 20; i++)
	{
		//Slots[i].Enabled = GetLobbySlotStatus(i);
		//if (Slots[i].Enabled == 0)
		//	continue;
		Slots[i].SlotNum = GetSlotNum(i);
		Slots[i].Status = GetSlotStatus(i);
		Slots[i].Pass = GetSlotPass(i);
		Slots[i].Player = GetSlotPlayer(i);
		Slots[i].MaxPlayer = GetSlotMaxPlayer(i);
		Slots[i].ScenarioID = GetSlotScenarioID(i);
		Slots[i].Version = GetSlotVersion(i);
	}
	return 0;
}

static int LUpdateRoom (lua_State* L)
{
	info.CurrentFile = GetFile();
	if (info.CurrentFile == -1)
		return 0;
	for (int i=0; i < 4; i++)
	{
		SPlayers[i].Enabled = GetSlotCharacterEnabled(i);
		if (SPlayers[i].Enabled == 0)
			continue;
		SPlayers[i].NPCType = GetSlotNPCType(i);
		SPlayers[i].NameID = GetSlotNameID(i);
	}
	return 0;
}

static int LUpdate (lua_State* L)
{
	int previousFile = info.CurrentFile;
	int previousRelease = F1_Release;
	info.HiveCodesAvailable = 0;
	info.CurrentFile = GetFile();
	if (info.CurrentFile != previousFile || F1_Release != previousRelease || info.CurrentFile == 255)
		Rooms.Enabled = false;
	if (info.CurrentFile == -1)
		return 0;
	info.HostStatus = GetHostStatus();
	info.HostTime = GetHostTime();
	info.HostMaxPlayer = GetHostMaxPlayer();
	info.HostPlayer = GetHostPlayer();
	info.HostScenarioID = GetHostScenarioID();
	info.HostDifficulty = GetHostDifficulty();
	info.ScenarioID = GetScenarioID();
	info.FrameCounter = GetFrames();
	info.LocalSlot = GetLocalSlot();
	info.Cleared = GetCleared();
	info.PlayerNum = GetPlayerNum();
	info.WTTime = GetWTTime();
	info.EscapeTime = GetEscapeTime();
	info.FightTime = GetFightTime();
	info.FightTime2 = GetFightTime2();
	info.GarageTime = GetGarageTime();
	info.GasTime = GetGasTime();
	info.GasFlag = GetGasFlag();
	info.GasRandom = GetGasRandom();
	info.ItemRandom = GetItemRandom();
	info.ItemRandom2 = GetItemRandom2();
	info.PuzzleRandom = GetPuzzleRandom();
	UpdateSPSet();
	info.Coin = GetCoin();
	info.KilledZombie = GetKilledZombies();
	info.PassWT = GetPassWT();
	info.PassDT1 = GetPassDT1();
	info.PassDT2 = GetPassDT2();
	info.PassDT3 = GetPassDT3();
	info.Pass1 = GetPass1();
	info.Pass2 = GetPass2();
	info.Pass3 = GetPass3();
	info.PassUB1 = GetPassUB1();
	info.PassUB2 = GetPassUB2();
	info.PassUB3 = GetPassUB3();
	info.Pass4 = GetPass4();
	info.Pass5 = GetPass5();
	info.Pass6 = GetPass6();
	info.Difficulty = GetDifficulty();
	UpdateHiveCodes();
	UpdatePickups();
	UpdateEnemyList();
	UpdateRoomMasters();

	for (int i=0; i < 4; i++)
	{
		Players[i].Enabled = GetCharacterEnabled(i);
		if (Players[i].Enabled == 0)
			continue;
		Players[i].InGame = GetCharacterInGame(i);
		Players[i].HP = GetHealth(i);
		Players[i].MaxHP = GetMaxHealth(i);
		Players[i].BleedTime = GetBleedTime(i);
		Players[i].AntiVirusTime = GetAntiVirusTime(i);
		Players[i].AntiVirusGTime = GetAntiVirusGTime(i);
		Players[i].HerbTime = GetHerbTime(i);
		Players[i].CharacterType = GetCharacterType(i);
		Players[i].NameID = GetNameID(i);
		Players[i].Virus = GetPercentage(i);
		Players[i].Size = GetSize(i);
		Players[i].Speed = GetSpeed(i);
		Players[i].Power = GetPower(i);
		Players[i].PositionX = GetPositionX(i);
		Players[i].PositionY = GetPositionY(i);
        Players[i].PositionHeight = info.CurrentFile == 2 ? GetForward(i, 0, F2_PositionHeight) : 0;
		Players[i].ForwardX = GetForward(i, F1_ForwardX, F2_ForwardX);
		Players[i].ForwardY = GetForward(i, F1_ForwardY, F2_ForwardY);
		Players[i].RoomID = GetRoomID(i);
		Players[i].SpecialItem = GetSpecialItem(i);
		Players[i].EquippedItem = GetEquippedItem(i);
		Players[i].Status = GetCharacterStatus(i);
		Players[i].CritBonus = GetCritBonus(i);
		GetCindyBag(i);

		char* inv = GetInventory(i);
		char* spinv = GetSpecialInventory(i);
		char* dinv = GetDeadInventory(i);
		char* dspinv = GetDeadSpecialInventory(i);
		memcpy(Players[i].Inventory, inv, 4);
		memcpy(Players[i].SpecialInventory, spinv, 4);
		memcpy(Players[i].DeadInventory, dinv, 4);
		memcpy(Players[i].DeadInventorySpecial, dspinv, 4);
		free(inv);
		free(spinv);
		free(dinv);
		free(dspinv);
		inv = NULL;
		spinv = NULL;
		dinv = NULL;
		dspinv = NULL;
	}

	for (int i=0; i < MAX_ENEMY; i++)
	{
		Enemies[i].Enabled = GetEnemyEnabled(i);
		Enemies[i].InGame = GetEnemyInGame(i);
		if (Enemies[i].InGame == 0)
			continue;
		Enemies[i].HP = GetEnemyHealth(i);
		Enemies[i].MaxHP = GetEnemyMaxHealth(i);
		Enemies[i].EnemyType = GetEnemyType(i);
		Enemies[i].NameID = GetEnemyNameID(i);
		Enemies[i].PositionX = GetEnemyPositionX(i);
		Enemies[i].PositionY = GetEnemyPositionY(i);
		Enemies[i].RoomID = GetEnemyRoomID(i);
	}

	for (int i=0; i < MAX_ENEMY; i++)// for plant boss
	{
		Enemies[i].Enabled = GetEnemyEnabled(i);
		if (Enemies[i].Enabled == 0)
			continue;
		Enemies[i].InGame = GetEnemyInGame(i);
		Enemies[i].HP = GetEnemyHealth(i);
		Enemies[i].MaxHP = GetEnemyMaxHealth(i);
		Enemies[i].EnemyType = GetEnemyType(i);
		Enemies[i].NameID = GetEnemyNameID(i);
	}
	for (int i=0; i < MAX_ITEM; i++)
	{
		if (info.CurrentFile == 1)
			GetRoomItemF1(i);
		else
			GetRoomItemF2(i);
	}
	for (int i=0; i < MAX_DOOR; i++)
	{
		Doors[i].HP = GetDoorHP(i);
		Doors[i].Flag = GetDoorFlag(i);
	}

	return 0;
}

static int LGetLobby (lua_State* L)
{
	double slotNum = lua_tonumber(L, 1);
	int i = (int)(slotNum-1);
	double playerID = lua_tonumber(L, 1);
	lua_newtable(L);

		lua_pushstring(L, "num");
			lua_pushnumber(L, (double)Slots[i].SlotNum);
		lua_rawset(L, -3);
		lua_pushstring(L, "status");
			lua_pushnumber(L, (double)Slots[i].Status);
		lua_rawset(L, -3);
		lua_pushstring(L, "pass");
			lua_pushnumber(L, (double)Slots[i].Pass);
		lua_rawset(L, -3);
		lua_pushstring(L, "version");
			lua_pushnumber(L, (double)Slots[i].Version);
		lua_rawset(L, -3);
		lua_pushstring(L, "player");
			lua_pushnumber(L, (double)Slots[i].Player);
		lua_rawset(L, -3);
		lua_pushstring(L, "maxplayer");
			lua_pushnumber(L, (double)Slots[i].MaxPlayer);
		lua_rawset(L, -3);
		if (info.CurrentFile == 1)
		{
		lua_pushstring(L, "slotscenario");
			lua_pushstring(L, GetF1LobScenarioName(Slots[i].ScenarioID));
		lua_rawset(L, -3);
		}
		else
		{
		lua_pushstring(L, "slotscenario");
			lua_pushstring(L, GetF2LobScenarioName(Slots[i].ScenarioID));
		lua_rawset(L, -3);
		}

	return 1;
}
static int LGetSlotPlayer (lua_State* L)
{
	double playerID = lua_tonumber(L, 1);
	int i = (int)(playerID-1);
	char* charname1 = GetCharacterNameF1(SPlayers[i].NameID);
	char* charname2 = GetCharacterName(SPlayers[i].NameID);
	char* hp = GetCharacterHP(SPlayers[i].NameID);
	char* npchp = GetNPCHP(SPlayers[i].NameID);
	char* power = GetCharacterPower(SPlayers[i].NameID);
	char* npcpower = GetNPCPower(SPlayers[i].NameID);
	char* name1 = GetF1NPCName(SPlayers[i].NameID);
	char* name2 = GetNPCName(SPlayers[i].NameID);
	char* statname = GetStatusText(SPlayers[i].Status);

	lua_newtable(L);

		lua_pushstring(L, "enabled");
			lua_pushboolean(L, SPlayers[i].Enabled);
		lua_rawset(L, -3);

		lua_pushstring(L, "hp");
			if(SPlayers[i].NPCType == 0)
				lua_pushstring(L, hp);
			else
			{
				if(name1 == NULL || name2 == NULL)
					lua_pushstring(L, "Unknown");
				else
					lua_pushstring(L, npchp);
			}
		lua_rawset(L, -3);

		lua_pushstring(L, "nameID");
			lua_pushnumber(L, SPlayers[i].NameID);
		lua_rawset(L, -3);

		lua_pushstring(L, "power");
			if(SPlayers[i].NPCType == 0)
				lua_pushstring(L, power);
			else
			{
				if(name1 == NULL || name2 == NULL)
					lua_pushstring(L, "Unknown");
				else
					lua_pushstring(L, npcpower);
			}
		lua_rawset(L, -3);

		lua_pushstring(L, "name");
			if(SPlayers[i].NPCType == 0)
			{
				if(info.CurrentFile == 1)
					lua_pushstring(L, charname1);
				else
					lua_pushstring(L, charname2);
			}
			else
			{
				if(info.CurrentFile == 1)
				{
					if(name1 == NULL)
						lua_pushstring(L, "Unknown");
					else
						lua_pushstring(L, name1);
				}
				else
				{
					if(name2 == NULL)
						lua_pushstring(L, "Unknown");
					else
						lua_pushstring(L, name2);
				}
			}
		lua_rawset(L, -3);

	return 1;
}
static int LGetPlayer (lua_State* L)
{
	double playerID = lua_tonumber(L, 1);
	int i = (int)(playerID-1);
	char* charname = GetCharacterName(Players[i].CharacterType);
	char* name = GetNPCName(Players[i].NameID);
	char* statname = GetStatusText(Players[i].Status);

	lua_newtable(L);

		lua_pushstring(L, "enabled");
			lua_pushboolean(L, Players[i].Enabled);
		lua_rawset(L, -3);

		lua_pushstring(L, "inGame");
			lua_pushboolean(L, Players[i].InGame);
		lua_rawset(L, -3);

		lua_pushstring(L, "HP");
			lua_pushnumber(L, (double)Players[i].HP);
		lua_rawset(L, -3);

		lua_pushstring(L, "maxHP");
			lua_pushnumber(L, (double)Players[i].MaxHP);
		lua_rawset(L, -3);

		lua_pushstring(L, "bleedtime");
			lua_pushnumber(L, (double)Players[i].BleedTime);
		lua_rawset(L, -3);

		lua_pushstring(L, "antivirustime");
			lua_pushnumber(L, (double)Players[i].AntiVirusTime);
		lua_rawset(L, -3);

		lua_pushstring(L, "antivirusgtime");
			lua_pushnumber(L, (double)Players[i].AntiVirusGTime);
		lua_rawset(L, -3);

		lua_pushstring(L, "herbtime");
			lua_pushnumber(L, (double)Players[i].HerbTime);
		lua_rawset(L, -3);

		lua_pushstring(L, "type");
			lua_pushstring(L, charname);
		lua_rawset(L, -3);

		lua_pushstring(L, "virus");
			lua_pushnumber(L, Players[i].Virus);
		lua_rawset(L, -3);

        {
            const char* baseline = Players[i].NameID < 8 ? GetCharacterPower(Players[i].NameID) : GetNPCPower(Players[i].NameID);
            lua_pushstring(L, "basePower");
            lua_pushnumber(L, baseline ? atof(baseline) / 100.0 : 1.0);
            lua_rawset(L, -3);
        }
		lua_pushstring(L, "power");
			lua_pushnumber(L, Players[i].Power);
		lua_rawset(L, -3);

		lua_pushstring(L, "speed");
			lua_pushnumber(L, Players[i].Speed);
		lua_rawset(L, -3);

		lua_pushstring(L, "size");
			lua_pushnumber(L, Players[i].Size);
		lua_rawset(L, -3);

		lua_pushstring(L, "critBonus");
			lua_pushnumber(L, Players[i].CritBonus);
		lua_rawset(L, -3);

		lua_pushstring(L, "positionX");
			lua_pushnumber(L, Players[i].PositionX);
		lua_rawset(L, -3);

		lua_pushstring(L, "positionY");
			lua_pushnumber(L, Players[i].PositionY);
		lua_rawset(L, -3);

        if (info.CurrentFile == 2) {
            lua_pushstring(L, "heightAvailable");
            lua_pushboolean(L, true);
            lua_rawset(L, -3);
            lua_pushstring(L, "height");
            lua_pushnumber(L, Players[i].PositionHeight);
            lua_rawset(L, -3);
        }

		lua_pushstring(L, "forwardX");
			lua_pushnumber(L, Players[i].ForwardX);
		lua_rawset(L, -3);

		lua_pushstring(L, "forwardY");
			lua_pushnumber(L, Players[i].ForwardY);
		lua_rawset(L, -3);

		lua_pushstring(L, "roomID");
			lua_pushnumber(L, (double)Players[i].RoomID);
		lua_rawset(L, -3);

		lua_pushstring(L, "status");
			lua_pushstring(L, statname);
		lua_rawset(L, -3);

		lua_pushstring(L, "name");
			if (name == NULL)
				lua_pushstring(L, charname);
			else
				lua_pushstring(L, name);
		lua_rawset(L, -3);

		lua_pushstring(L, "inventory");
		lua_newtable(L);
			for (int j=0; j < 4; j++)
			{
				lua_pushnumber(L, (double)j+1);
				unsigned char id;
				if (strcmp(statname, "Dead") == 0 || strcmp(statname, "Zombie") == 0)
					id = Players[i].DeadInventory[j];
				else
					id = Players[i].Inventory[j];
				if (id == 0x00)
				{
					CreateEmptyItemTable
				}
				else
				{
					CreateItemTable(Items[id-1]);
				}
			}
		lua_rawset(L, -3);

		lua_pushstring(L, "specialItem");
		if (Players[i].SpecialItem == 0x00)
		{
			CreateEmptyItemTable
		}
		else
		{
			CreateItemTable(Items[Players[i].SpecialItem-1])
		}

		lua_pushstring(L, "specialInventory");
		lua_newtable(L);
		if (Players[i].CharacterType == 7) // if Cindy
			for (int j=0; j < 4; j++)
			{
				lua_pushnumber(L, (double)j+1);
				if (Players[i].CindyBag[j].ID == 0x00)
				{
					CreateEmptyItemTable
				}	
				else
				{
					CreateItemTable(Players[i].CindyBag[j]);
				}
			}
		else
			for (int j=0; j < 4; j++)
			{
				lua_pushnumber(L, (double)j+1);
				unsigned char id;
				if (strcmp(statname, "Dead") == 0 || strcmp(statname, "Zombie") == 0)
					id = Players[i].DeadInventorySpecial[j];
				else
					id = Players[i].SpecialInventory[j];
				if (id == 0x00)
				{
					CreateEmptyItemTable
				}
				else
				{
					CreateItemTable(Items[id-1]);
				}
			}
		lua_rawset(L, -3);

		lua_pushstring(L, "equipped");
			lua_pushnumber(L, (double)Players[i].EquippedItem);
		lua_rawset(L, -3);

	return 1;
}

static int LgetEnemyList(lua_State* L)
{
	double enemyID = lua_tonumber(L, 1);
	int i = (int)(enemyID-1);
	char* zombiename= GetZombieName(Enemies2[i].Type);
	char* dogname= GetDogName(Enemies2[i].Type);
	char* stname= GetSTName(Enemies2[i].Type);
	char* lionname= GetLionName(Enemies2[i].Type);
	char* tyrantname= GetTyrantName(Enemies2[i].Type);
	char* thanatosname= GetThanatosName(Enemies2[i].Type);
	char* name = GetEnemyName(Enemies2[i].NameID);

	lua_newtable(L);

		for (int j=0; j < 80; j++)
		{
		lua_pushstring(L, "number");
			lua_pushnumber(L, Enemies2[i].Number);
		lua_rawset(L, -3);

		lua_pushstring(L, "flag");
			lua_pushnumber(L, Enemies2[i].Flag);
		lua_rawset(L, -3);

		lua_pushstring(L, "HP");
			lua_pushnumber(L, (double)Enemies2[i].HP);
		lua_rawset(L, -3);

		lua_pushstring(L, "maxHP");
			lua_pushnumber(L, (double)Enemies2[i].MaxHP);
		lua_rawset(L, -3);

		lua_pushstring(L, "nameID");
			lua_pushnumber(L, Enemies2[i].NameID);
		lua_rawset(L, -3);

		lua_pushstring(L, "roomID");
			lua_pushnumber(L, Enemies2[i].RoomID);
		lua_rawset(L, -3);

		lua_pushstring(L, "type");
			lua_pushnumber(L, Enemies2[i].Type);
		lua_rawset(L, -3);

		lua_pushstring(L, "status");
			lua_pushnumber(L, Enemies2[i].Status);
		lua_rawset(L, -3);

		lua_pushstring(L, "name");
			if (name == NULL)
				lua_pushstring(L, zombiename);
			else if(name == "Zombie"&& zombiename != NULL)
				lua_pushstring(L, zombiename);
			else if(name == "Dog"&& dogname != NULL)
				lua_pushstring(L, dogname);
			else if(name == "Sci.Tail"&& stname != NULL)
				lua_pushstring(L, stname);
			else if(name == "Lion"&& lionname != NULL)
				lua_pushstring(L, lionname);
			else if(name == "Tyrant"&& tyrantname != NULL)
				lua_pushstring(L, tyrantname);
			else if(name == "Thanatos"&& thanatosname != NULL)
				lua_pushstring(L, thanatosname);
			else
				lua_pushstring(L, name);
		lua_rawset(L, -3);

		}
	return 1;
}
static int LGetEnemy (lua_State* L)
{
	double enemyID = lua_tonumber(L, 1);
	int i = (int)(enemyID-1);
	char* zombiename= GetZombieName(Enemies[i].EnemyType);
	char* dogname= GetDogName(Enemies[i].EnemyType);
	char* stname= GetSTName(Enemies[i].EnemyType);
	char* lionname= GetLionName(Enemies[i].EnemyType);
	char* tyrantname= GetTyrantName(Enemies[i].EnemyType);
	char* thanatosname= GetThanatosName(Enemies[i].EnemyType);
	char* name = GetEnemyName(Enemies[i].NameID);

	lua_newtable(L);

		lua_pushstring(L, "enabled");
			lua_pushboolean(L, Enemies[i].Enabled);
		lua_rawset(L, -3);

		lua_pushstring(L, "inGame");
			lua_pushboolean(L, Enemies[i].InGame);
		lua_rawset(L, -3);

		lua_pushstring(L, "HP");
			lua_pushnumber(L, (double)Enemies[i].HP);
		lua_rawset(L, -3);

		lua_pushstring(L, "maxHP");
			lua_pushnumber(L, (double)Enemies[i].MaxHP);
		lua_rawset(L, -3);

		lua_pushstring(L, "nameID");
			lua_pushnumber(L, (double)Enemies[i].NameID);
		lua_rawset(L, -3);

		lua_pushstring(L, "type");
			lua_pushnumber(L, Enemies[i].EnemyType);
			//lua_pushstring(L, zombiename);
		lua_rawset(L, -3);

		lua_pushstring(L, "positionX");
			lua_pushnumber(L, Enemies[i].PositionX);
		lua_rawset(L, -3);

		lua_pushstring(L, "positionY");
			lua_pushnumber(L, Enemies[i].PositionY);
		lua_rawset(L, -3);

		lua_pushstring(L, "roomID");
			lua_pushnumber(L, (double)Enemies[i].RoomID);
		lua_rawset(L, -3);

		lua_pushstring(L, "name");
			if (name == NULL)
				lua_pushstring(L, zombiename);
			else if(name == "Zombie"&& zombiename != NULL)
				lua_pushstring(L, zombiename);
			else if(name == "Dog"&& dogname != NULL)
				lua_pushstring(L, dogname);
			else if(name == "Sci.Tail"&& stname != NULL)
				lua_pushstring(L, stname);
			else if(name == "Lion"&& lionname != NULL)
				lua_pushstring(L, lionname);
			else if(name == "Tyrant"&& tyrantname != NULL)
				lua_pushstring(L, tyrantname);
			else if(name == "Thanatos"&& thanatosname != NULL)
				lua_pushstring(L, thanatosname);
			else
				lua_pushstring(L, name);
		lua_rawset(L, -3);

	return 1;
}

static int LGetItem(lua_State* L)
{
	double itemID = lua_tonumber(L, 1);
	int i = (int)(itemID-1);

	lua_newtable(L);

		lua_pushstring(L, "roomitem");
		lua_newtable(L);

			for (int j=0; j < MAX_ITEM; j++)
			{
				lua_pushnumber(L, (double)j+1);
				if (RItems->RItem[j].ID == 0x00||
				RItems->RItem[j].Count == 0xFFFF||
				RItems->RItem[j].EN != 0xFFFF||
				//RItems->RItem[j].Pick > 0 && RItems->RItem[j].Present ==0||
				RItems->RItem[j].Mix == 0x20)
				{
					CreateEmptyItemTable
				}
				else
				{
					CreateItemTable(RItems[i].RItem[j]);
				}
			}

		lua_rawset(L, -3);

	return 1;
}
static int LGetItem2(lua_State* L)
{
	double itemID = lua_tonumber(L, 1);
	int i = (int)(itemID-1);

	lua_newtable(L);

		for (int j=0; j < 255; j++)
		{
		lua_pushstring(L, "number");
			lua_pushnumber(L, Items[i].Number);
		lua_rawset(L, -3);

		lua_pushstring(L, "id");
			lua_pushnumber(L, (double)Items[i].ID);
		lua_rawset(L, -3);

		lua_pushstring(L, "type");
			lua_pushnumber(L, (double)Items[i].Type);
		lua_rawset(L, -3);

		lua_pushstring(L, "count");
			lua_pushnumber(L, (double)Items[i].Count);
		lua_rawset(L, -3);

		lua_pushstring(L, "pick");
			lua_pushnumber(L, (double)Items[i].Pick);
		lua_rawset(L, -3);

		lua_pushstring(L, "present");
			lua_pushnumber(L, (double)Items[i].Present);
		lua_rawset(L, -3);

		lua_pushstring(L, "mix");
			lua_pushnumber(L, Items[i].Mix);
		lua_rawset(L, -3);

		lua_pushstring(L, "roomid");
			lua_pushnumber(L, Items[i].RoomID);
		lua_rawset(L, -3);
		}
	return 1;
}

/* Reusable map export from the already-refreshed Items array; no extra PINE
   reads. Shared Lua remembers observations and selects scenario objects.
   Run tracker.getMapItems(); check reader/check-reader.sh and map checks. */
static int LGetMapItems(lua_State* L)
{
    lua_newtable(L);
    for (int i = 0; i < 255; ++i) {
        lua_pushnumber(L, i + 1);
        CreateItemTable(Items[i]);
    }
    return 1;
}

static int LGetDoor(lua_State* L)
{
	double doorID = lua_tonumber(L, 1);
	int i = (int)(doorID-1);

	lua_newtable(L);

		lua_pushstring(L, "HP");
			lua_pushnumber(L, (double)Doors[i].HP);
		lua_rawset(L, -3);

		lua_pushstring(L, "flag");
			lua_pushnumber(L, (double)Doors[i].Flag);
		lua_rawset(L, -3);

	return 1;
}

static int LGetGameInfo (lua_State* L)
{
	lua_newtable(L);
		lua_pushstring(L, "currentFile");
			lua_pushnumber(L, (double)info.CurrentFile);
		lua_rawset(L, -3);
		lua_pushstring(L, "release");
			lua_pushstring(L, GetReleaseName());
		lua_rawset(L, -3);
		lua_pushstring(L, "hoststatus");
			lua_pushnumber(L, (double)info.HostStatus);
		lua_rawset(L, -3);
		lua_pushstring(L, "hosttime");
			lua_pushnumber(L, (double)info.HostTime);
		lua_rawset(L, -3);
		lua_pushstring(L, "hostmaxplayer");
			lua_pushnumber(L, (double)info.HostMaxPlayer);
		lua_rawset(L, -3);
		lua_pushstring(L, "hostplayer");
			lua_pushnumber(L, (double)info.HostPlayer);
		lua_rawset(L, -3);
		lua_pushstring(L, "hostdifficulty");
			lua_pushstring(L, GetDifficultyName(info.HostDifficulty));
		lua_rawset(L, -3);

		if (info.CurrentFile == 1)
		{
		lua_pushstring(L, "hostscenario");
			lua_pushstring(L, GetF1LobScenarioName(info.HostScenarioID));
		lua_rawset(L, -3);
		}
		else
		{
		lua_pushstring(L, "hostscenario");
			lua_pushstring(L, GetF2LobScenarioName(info.HostScenarioID));
		lua_rawset(L, -3);
		}
		lua_pushstring(L, "scenario");
			lua_pushstring(L, GetScenarioName(info.ScenarioID));
		lua_rawset(L, -3);
		lua_pushstring(L, "frames");
			lua_pushnumber(L, (double)info.FrameCounter);
		lua_rawset(L, -3);
		lua_pushstring(L, "localSlot");
			lua_pushnumber(L, (double)info.LocalSlot);
		lua_rawset(L, -3);
		lua_pushstring(L, "cleared");
			lua_pushnumber(L, (double)info.Cleared);
		lua_rawset(L, -3);
		lua_pushstring(L, "wttime");
			lua_pushnumber(L, (double)info.WTTime);
		lua_rawset(L, -3);
		lua_pushstring(L, "escapetime");
			lua_pushnumber(L, (double)info.EscapeTime);
		lua_rawset(L, -3);
		lua_pushstring(L, "fighttime");
			lua_pushnumber(L, (double)info.FightTime);
		lua_rawset(L, -3);
		lua_pushstring(L, "fighttime2");
			lua_pushnumber(L, (double)info.FightTime2);
		lua_rawset(L, -3);
		lua_pushstring(L, "garagetime");
			lua_pushnumber(L, (double)info.GarageTime);
		lua_rawset(L, -3);
		lua_pushstring(L, "gastime");
			lua_pushnumber(L, (double)info.GasTime);
		lua_rawset(L, -3);
		lua_pushstring(L, "gasflag");
			lua_pushnumber(L, (double)info.GasFlag);
		lua_rawset(L, -3);
		lua_pushstring(L, "gasrandom");
			lua_pushnumber(L, (double)info.GasRandom);
		lua_rawset(L, -3);
		lua_pushstring(L, "itemrandom");
			lua_pushnumber(L, (double)info.ItemRandom);
		lua_rawset(L, -3);
		lua_pushstring(L, "itemrandom2");
			lua_pushnumber(L, (double)info.ItemRandom2);
		lua_rawset(L, -3);
		lua_pushstring(L, "puzzlerandom");
			lua_pushnumber(L, (double)info.PuzzleRandom);
		lua_rawset(L, -3);
		lua_pushstring(L, "spsetavailable");
			lua_pushboolean(L, info.SPSetAvailable);
		lua_rawset(L, -3);
		lua_pushstring(L, "spsetselector");
			lua_pushnumber(L, (double)info.SPSetSelector);
		lua_rawset(L, -3);
		lua_pushstring(L, "coin");
			lua_pushnumber(L, (double)info.Coin);
		lua_rawset(L, -3);
		lua_pushstring(L, "killedzombies");
			lua_pushnumber(L, (double)info.KilledZombie);
		lua_rawset(L, -3);
		lua_pushstring(L, "playernum");
			lua_pushnumber(L, (double)info.PlayerNum);
		lua_rawset(L, -3);
		lua_pushstring(L, "passwt");
			lua_pushnumber(L, (double)info.PassWT);
		lua_rawset(L, -3);
		lua_pushstring(L, "passdt1");
			lua_pushnumber(L, (double)info.PassDT1);
		lua_rawset(L, -3);
		lua_pushstring(L, "passdt2");
			lua_pushnumber(L, (double)info.PassDT2);
		lua_rawset(L, -3);
		lua_pushstring(L, "passdt3");
			lua_pushnumber(L, (double)info.PassDT3);
		lua_rawset(L, -3);
		lua_pushstring(L, "pass1");
			lua_pushnumber(L, (double)info.Pass1);
		lua_rawset(L, -3);
		lua_pushstring(L, "hivecodesavailable");
			lua_pushboolean(L, info.HiveCodesAvailable);
		lua_rawset(L, -3);
		lua_pushstring(L, "hiveb2f");
			lua_pushnumber(L, info.HiveCodesAvailable ? info.HiveB2FCode : 0);
		lua_rawset(L, -3);
		lua_pushstring(L, "hiverooftop");
			lua_pushnumber(L, info.HiveCodesAvailable ? info.HiveRoofCode : 0);
		lua_rawset(L, -3);
		lua_pushstring(L, "pass2");
			lua_pushnumber(L, (double)info.Pass2);
		lua_rawset(L, -3);
		lua_pushstring(L, "pass3");
			lua_pushnumber(L, (double)info.Pass3);
		lua_rawset(L, -3);
		lua_pushstring(L, "passub1");
			lua_pushnumber(L, (double)info.PassUB1);
		lua_rawset(L, -3);
		lua_pushstring(L, "passub2");
			lua_pushnumber(L, (double)info.PassUB2);
		lua_rawset(L, -3);
		lua_pushstring(L, "passub3");
			lua_pushnumber(L, (double)info.PassUB3);
		lua_rawset(L, -3);
		lua_pushstring(L, "pass4");
			lua_pushnumber(L, (double)info.Pass4);
		lua_rawset(L, -3);
		lua_pushstring(L, "pass5");
			lua_pushnumber(L, (double)info.Pass5);
		lua_rawset(L, -3);
		lua_pushstring(L, "pass6");
			lua_pushnumber(L, (double)info.Pass6);
		lua_rawset(L, -3);
		lua_pushstring(L, "difficulty");
			lua_pushstring(L, GetDifficultyName(info.Difficulty));
		lua_rawset(L, -3);

	return 1;
}

static int LGetRoomMaster(lua_State* L)
{
	double roomID = lua_tonumber(L, 1);
	int valid = lua_isnumber(L, 1) && roomID >= 0 && roomID < 128 && roomID == (int)roomID;
	int i = valid ? (int)roomID : 0;

	lua_newtable(L);

	lua_pushstring(L, "enabled");
	lua_pushboolean(L, valid && Rooms.Enabled);
	lua_rawset(L, -3);

	lua_pushstring(L, "roommaster");
	lua_pushnumber(L, valid && Rooms.Enabled ? Rooms.Room[i].RoomMaster : 0);
	lua_rawset(L, -3);

	return 1;
}

/* Alyssa's lock-pick progress: Japanese and U.S. File 1, Japanese File 2.
   The caller passes the hint spot it already matched and whether the lock is
   a door (counter at +0x64), a container (+0x60) or not known (nil: either).
   Several interaction records can lie near a spot (room zones, items, both
   sides of a door), so the lock's record is the one near the spot that was
   last used by this player and holds an active counter (1..200). Its address
   and counter offset are remembered and re-checked on every call, because a
   room change rebuilds the table. Until an attempt starts, the records whose
   box is near the spot are remembered from one table read and only those are
   re-read on each call, so the bar appears on the first call after a pick
   starts. Returns the signed counter (<= 0 once the lock opens), or nil when
   the release has no table or no record matches. */
typedef struct
{
	int Corner[8];
	unsigned int Actor;
	short Door;
	short Container;
} LockRecord;

static void ParseLockRecord(const unsigned char* bytes, LockRecord* record)
{
	memcpy(record->Corner, bytes, sizeof(record->Corner));
	memcpy(&record->Actor, bytes + F1_InteractActorOffset, sizeof(record->Actor));
	memcpy(&record->Door, bytes + F1_DoorLockCounterOffset, sizeof(record->Door));
	memcpy(&record->Container, bytes + F1_ContainerLockCounterOffset, sizeof(record->Container));
}

/* Distance from the spot to the bounding box of the record's four corner
   points, or -1 if they do not form an area. File 1 lists the corners as
   x0,y0 x0,y1 x1,y1 x1,y0; File 2 as x0,y0 x1,y0 x1,y1 x0,y1, and its areas
   need not be exact rectangles (a corner can be a unit off). */
static double LockBoxDistance(const LockRecord* record, double x, double y)
{
	const int* c = record->Corner;
	double minX = c[0], maxX = c[0], minY = c[1], maxY = c[1];
	for (int i = 0; i < 8; i += 2)
	{
		if (c[i] < -100000 || c[i] > 100000 || c[i + 1] < -100000 || c[i + 1] > 100000)
			return -1;
		if (c[i] < minX) minX = c[i];
		if (c[i] > maxX) maxX = c[i];
		if (c[i + 1] < minY) minY = c[i + 1];
		if (c[i + 1] > maxY) maxY = c[i + 1];
	}
	if (maxX - minX < 1 || maxY - minY < 1 || maxX - minX > 20000 || maxY - minY > 20000)
		return -1;
	double dx = x < minX ? minX - x : (x > maxX ? x - maxX : 0);
	double dy = y < minY ? minY - y : (y > maxY ? y - maxY : 0);
	return dx > dy ? dx : dy;
}

/* Table address, record size, slot count and player struct address for the loaded release. */
static int LockTableForRelease(int playerIndex, int* table, int* stride, int* slots, unsigned int* actor)
{
	if (info.CurrentFile == 1)
	{
		*table = F1_InteractTable;
		*stride = F1_InteractStride;
		*slots = F1_InteractSlots;
		*actor = (unsigned int)F1_GetCharAddress(playerIndex);
		if (F1_Release == F1_RELEASE_US)
		{
			*table = F1_US_Translate(F1_InteractTable, F1_InteractSlots * F1_InteractStride);
			*actor = (unsigned int)F1_US_Translate((int)*actor, 4);
		}
		return *table != 0 && *actor != 0;
	}
	if (info.CurrentFile == 2)
	{
		*table = F2_InteractTable;
		*stride = F2_InteractStride;
		*slots = F2_InteractSlots;
		*actor = (unsigned int)F2_GetCharAddress(playerIndex);
		return 1;
	}
	return 0;
}

/* Counter at the chosen offset (0 door, 1 container); for "either" (-1) the
   first offset whose value is an active counter, else the door offset. */
static int LockCounterOffset(const LockRecord* record, int kind)
{
	if (kind >= 0)
		return kind;
	if (record->Door >= 1 && record->Door <= 200)
		return 0;
	if (record->Container >= 1 && record->Container <= 200)
		return 1;
	return 0;
}

static int LGetLockCounter(lua_State* L)
{
	enum { MaxCandidates = 16 };
	static int cachedRecord = -1;
	static int cachedOffset = 0;
	static int candidates[MaxCandidates];
	static int candidateCount = -1; /* -1: the spot's records have not been listed yet */
	static int listedTable = 0;
	static double listedX = 0, listedY = 0;
	static unsigned int emptyCooldown = 0;
	static unsigned char table[0xC4 * 64]; /* largest stride x slots */
	const double hintRange = 250.0; /* same square the pick hints use */
	int playerIndex = (int)lua_tonumber(L, 1) - 1;
	double spotX = lua_tonumber(L, 2);
	double spotY = lua_tonumber(L, 3);
	int kind = lua_isnoneornil(L, 4) ? -1 : (lua_toboolean(L, 4) ? 1 : 0);
	int tableAddress, stride, slots;
	unsigned int actor;
	unsigned char bytes[0xC4];
	LockRecord record;
	double distance;

	if (playerIndex < 0 || playerIndex > 3 || !LockTableForRelease(playerIndex, &tableAddress, &stride, &slots, &actor) ||
		(SIZE_T)stride * slots > sizeof(table))
	{
		lua_pushnil(L);
		return 1;
	}

	/* An active attempt found earlier: one record read per call. */
	if (cachedRecord >= 0)
	{
		ReadProcessMemory(ProcessHandle, (char *)BasePointer+cachedRecord, bytes, sizeof(bytes), NULL);
		ParseLockRecord(bytes, &record);
		distance = LockBoxDistance(&record, spotX, spotY);
		if (distance >= 0 && distance <= hintRange && record.Actor == actor && (kind < 0 || kind == cachedOffset))
		{
			lua_pushnumber(L, cachedOffset ? record.Container : record.Door);
			return 1;
		}
		cachedRecord = -1;
	}

	/* List the records near this spot from one table read (again after a
	   different spot, release or room). */
	if (candidateCount < 0 || listedTable != tableAddress || listedX != spotX || listedY != spotY)
	{
		if (emptyCooldown > 0 && listedTable == tableAddress && listedX == spotX && listedY == spotY)
		{
			emptyCooldown--;
			lua_pushnil(L);
			return 1;
		}
		ReadProcessMemory(ProcessHandle, (char *)BasePointer+tableAddress, table, (SIZE_T)stride * slots, NULL);
		candidateCount = 0;
		for (int slot = 0; slot < slots && candidateCount < MaxCandidates; slot++)
		{
			ParseLockRecord(table + slot * stride, &record);
			distance = LockBoxDistance(&record, spotX, spotY);
			if (distance >= 0 && distance <= hintRange)
				candidates[candidateCount++] = tableAddress + slot * stride;
		}
		listedTable = tableAddress;
		listedX = spotX;
		listedY = spotY;
		if (candidateCount == 0)
		{
			/* Nothing near the spot yet (for example while the room loads). */
			candidateCount = -1;
			emptyCooldown = 5;
			lua_pushnil(L);
			return 1;
		}
	}

	/* Re-read only the listed records and take the nearest active one. */
	double best = hintRange;
	short counter = 0;
	for (int i = 0; i < candidateCount; i++)
	{
		ReadProcessMemory(ProcessHandle, (char *)BasePointer+candidates[i], bytes, sizeof(bytes), NULL);
		ParseLockRecord(bytes, &record);
		distance = LockBoxDistance(&record, spotX, spotY);
		if (distance < 0 || distance > hintRange)
		{
			/* The room rebuilt its table: list the records again next call. */
			candidateCount = -1;
			cachedRecord = -1;
			lua_pushnil(L);
			return 1;
		}
		int offset = LockCounterOffset(&record, kind);
		short value = offset ? record.Container : record.Door;
		if (distance > best || record.Actor != actor || value < 1 || value > 200)
			continue;
		best = distance;
		cachedRecord = candidates[i];
		cachedOffset = offset;
		counter = value;
	}
	if (cachedRecord < 0)
	{
		lua_pushnil(L);
		return 1;
	}
	lua_pushnumber(L, counter);
	return 1;
}

static const struct luaL_Reg library_functions [] = {
	{"init", LInit},
	{"updateLobby", LUpdateLobby},
	{"updateRoom", LUpdateRoom},
	{"update", LUpdate},
	{"getLobby", LGetLobby},
	{"getSlotPlayer", LGetSlotPlayer},
	{"getPlayer", LGetPlayer},
	{"getEnemy", LGetEnemy},
	{"getEnemyList", LgetEnemyList},
	{"getItem", LGetItem},
	{"getItem2", LGetItem2},
	{"getMapItems", LGetMapItems},
	{"getDoor", LGetDoor},
	{"getLockCounter", LGetLockCounter},
	{"getRoomMaster", LGetRoomMaster},
	{"getGameInfo", LGetGameInfo},
	{NULL, NULL}
};

__declspec(dllexport) int luaopen_luaoutbreaktracker  (lua_State *L){
	luaL_register(L, "tracker", library_functions);
	return 1;
}
