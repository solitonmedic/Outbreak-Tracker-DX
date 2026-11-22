# Debug reader (dev branch only): the normal macOS reader from ../CMakeLists.txt
# plus the EE-RAM run recorder in sources/PineRecorder.cpp, linked with zlib.
# Used by macos/debug/build-app.sh and for the Terminal debug reader:
#   cmake -S macos/debug -B macos/terminal-build-debug-arm64 -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_OSX_ARCHITECTURES=arm64
cmake_minimum_required(VERSION 3.20)
project(OutbreakTrackerMacDebug LANGUAGES CXX)
add_subdirectory(.. reader)
find_package(ZLIB REQUIRED)
target_sources(luaoutbreaktracker PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../../sources/PineRecorder.cpp")
target_link_libraries(luaoutbreaktracker PRIVATE ZLIB::ZLIB)
