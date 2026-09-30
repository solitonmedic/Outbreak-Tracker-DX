# Windows build notes

The Windows native module reads PCSX2 process memory directly. It does not require PINE.

## Requirements

- Windows 10 or newer.
- Visual Studio 2022 with the Desktop development with C++ workload (v143 toolset).
- Git and PowerShell.
- The official LÖVE 11.5 x64 ZIP runtime for packaging.

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

Download and extract [`love-11.5-win64.zip`](https://github.com/love2d/love/releases/tag/11.5), then package the shared UI, native reader, LÖVE runtime, and fused executable:

```powershell
./windows/package.ps1 -LoveRuntimeDirectory 'C:\path\to\love-11.5-win64'
```

The package is `windows/build/OutbreakTracker-Windows-x64.zip`. Extract it and launch `OutbreakTracker.exe`; LÖVE does not need to be separately installed. The ZIP contains the fused game executable, the native reader DLL, LÖVE's runtime DLLs, and LÖVE's license. The executable needs those adjacent runtime DLLs, so distribute the ZIP contents together.

The Windows Actions workflow is manual-only. It downloads the official LÖVE 11.5 x64 runtime, builds the distribution directory, checks the executable and required runtime files, then uploads that directory as an artifact. After downloading the artifact from GitHub, extract it once to get the Windows distribution files.

## PCSX2

Start PCSX2 with the Japanese version of Outbreak File 1 or File 2 before launching the tracker. The Windows reader locates the PCSX2 process and reads its emulated EE memory directly.
