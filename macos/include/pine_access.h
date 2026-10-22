#pragma once
#include <mutex>
#include <pine.h>

// PCSX2 serves one PINE client at a time, so the reader and the debug recorder
// share this connection. Hold the mutex for each complete PINE exchange.
inline PINE::PCSX2 mac_pine;
inline std::mutex mac_pine_mutex;
