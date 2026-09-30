cmake_minimum_required(VERSION 3.20)
project(OutbreakTrackerLinux LANGUAGES CXX)

include(FetchContent)
FetchContent_Declare(pine GIT_REPOSITORY https://github.com/GovanifY/pine.git GIT_TAG master GIT_SHALLOW TRUE)
FetchContent_MakeAvailable(pine)

FetchContent_Declare(luajit GIT_REPOSITORY https://github.com/LuaJIT/LuaJIT.git GIT_TAG v2.1 GIT_SHALLOW TRUE)
FetchContent_GetProperties(luajit)
if(NOT luajit_POPULATED)
  FetchContent_Populate(luajit)
endif()

find_path(LUA_INCLUDE_DIR lua.h
  PATHS
    "${luajit_SOURCE_DIR}/src"
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
    /usr/include/luajit-2.1
    /usr/local/include/luajit-2.1
    /usr/include/lua5.1
)
if(NOT LUA_INCLUDE_DIR)
  message(FATAL_ERROR "Lua/LuaJIT headers are required")
endif()

set(PATCHED_SOURCE "${CMAKE_CURRENT_BINARY_DIR}/main_linux.cpp")
add_custom_command(OUTPUT "${PATCHED_SOURCE}"
  COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_CURRENT_SOURCE_DIR}/../sources/main.c" "${PATCHED_SOURCE}"
  COMMAND ${CMAKE_COMMAND}
    "-DINPUT:FILEPATH=${CMAKE_CURRENT_SOURCE_DIR}/../sources/main.c"
    "-DOUTPUT:FILEPATH=${PATCHED_SOURCE}"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/patch_legacy_source.cmake"
  DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/../sources/main.c" "${CMAKE_CURRENT_SOURCE_DIR}/patch_legacy_source.cmake")

add_library(luaoutbreaktracker MODULE "${PATCHED_SOURCE}")
target_compile_features(luaoutbreaktracker PRIVATE cxx_std_17)
target_compile_options(luaoutbreaktracker PRIVATE -fpermissive -include "${CMAKE_CURRENT_SOURCE_DIR}/include/legacy_macros.h")
target_include_directories(luaoutbreaktracker PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/include" ${pine_SOURCE_DIR}/src "${luajit_SOURCE_DIR}/src" ${LUA_INCLUDE_DIR} "${CMAKE_CURRENT_SOURCE_DIR}/../sources")
target_link_options(luaoutbreaktracker PRIVATE -Wl,--unresolved-symbols=ignore-in-object-files)
set_target_properties(luaoutbreaktracker PROPERTIES PREFIX "" SUFFIX ".so" LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}")
