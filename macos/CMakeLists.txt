cmake_minimum_required(VERSION 3.20)
project(OutbreakTrackerMac LANGUAGES CXX)
include(FetchContent)
FetchContent_Declare(pine GIT_REPOSITORY https://github.com/GovanifY/pine.git GIT_TAG master GIT_SHALLOW TRUE)
FetchContent_MakeAvailable(pine)
find_path(LUA_INCLUDE_DIR lua.h PATHS /opt/homebrew/opt/luajit/include/luajit-2.1 /usr/local/opt/luajit/include/luajit-2.1)
if(NOT LUA_INCLUDE_DIR)
  message(FATAL_ERROR "LuaJIT headers are required")
endif()
# The shared reader sources/main.c is C, but the PINE shim in include/windows.h
# is C++, so main.c is compiled as C++ here. The two switches select the
# behaviour of the builds that read over PINE; main.c explains each where it is
# used. The Windows build compiles main.c as C and sets neither.
set(READER_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/../sources/main.c")
set_source_files_properties("${READER_SOURCE}" PROPERTIES LANGUAGE CXX)
add_library(luaoutbreaktracker MODULE "${READER_SOURCE}")
target_compile_definitions(luaoutbreaktracker PRIVATE OUTBREAK_THROTTLE_READS OUTBREAK_ROOM_ITEM_ID_BOUND)
target_compile_features(luaoutbreaktracker PRIVATE cxx_std_17)
target_compile_options(luaoutbreaktracker PRIVATE -fdeclspec -fpermissive -include "${CMAKE_CURRENT_SOURCE_DIR}/include/legacy_macros.h")
target_include_directories(luaoutbreaktracker PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/include" ${pine_SOURCE_DIR}/src ${LUA_INCLUDE_DIR} ../sources)
target_link_options(luaoutbreaktracker PRIVATE -Wl,-undefined,dynamic_lookup)
set_target_properties(luaoutbreaktracker PROPERTIES PREFIX "" SUFFIX ".so" LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}")
