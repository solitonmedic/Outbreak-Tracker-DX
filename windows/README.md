# Windows build notes

The Windows native module reads PCSX2 process memory directly. It does not require PINE.

## Requirements

- Windows 10 or newer.
- Visual Studio 2022 with the Desktop development with C++ workload (v143 toolset).
- Git and PowerShell.
- LÖVE 11.5 or newer to run the packaged tracker.

## Build

From the repository root, build LuaJIT and the tracker DLL:

```powershell
git clone --depth 1 --branch v2.1 https://github.com/LuaJIT/LuaJIT.git windows/luajit
```

Open an x64 Visual Studio Developer Command Prompt, then run:

```bat
cd windows\luajit\src
msvcbuild.bat
mkdir "..\..\Outbreak Tracker\lib\x64"
copy lua51.lib "..\..\Outbreak Tracker\lib\x64\lua51.lib"
cd ..\..\..
msbuild "windows\Outbreak Tracker.sln" /m /p:Configuration=Release /p:Platform=x64
```

Package the shared UI and DLL:

```powershell
./windows/package.ps1
```

The package is `windows/build/OutbreakTracker-Windows-x64.zip`. Extract it, then run `love lua` from a terminal in the extracted directory. The ZIP contains the `lua` game folder and native DLL; it does not bundle the LÖVE runtime.

## PCSX2

Start PCSX2 with the Japanese version of Outbreak File 1 or File 2 before launching the tracker. The Windows reader locates the PCSX2 process and reads its emulated EE memory directly.
