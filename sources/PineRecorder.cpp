// Debug-build run recorder for the PINE platforms.
//
// While the tracker runs, this saves timestamped, gzip-compressed full 32 MiB
// EE-RAM checkpoints through the tracker's read-only PINE connection. The run
// folder matches tools-n-shit/record-pine-ee-run.py: manifest.json, one JSON
// sidecar per checkpoint, periodic and room-change checkpoints, room_loaded
// events and typed markers. It only reads memory; it never writes to the game.
//
// The Hive password pin of the Python recorder is not included.

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

#include <pine_access.h>
#include <zlib.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cctype>
#include <cmath>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace fs = std::filesystem;

namespace {

constexpr std::uint32_t kEERamSize = 32 * 1024 * 1024;
// pine.h allows fewer than 50,000 commands and 450,000 reply bytes per batch.
constexpr std::uint32_t kReadsPerBatch = 40000;
constexpr std::uint32_t kPlayerStride = 0x10E0;
constexpr std::uint32_t kRoomOffset = 0x1E2;
const int kFile1Scenarios[] = {1, 2, 28, 35, 41};

// ---------------------------------------------------------------------------
// Minimal ordered JSON value, enough for the manifest and sidecars.

class Json {
public:
    enum class Type { Null, Bool, Int, Real, String, Array, Object };

    Json() = default;
    Json(std::nullptr_t) {}
    Json(bool value) : type_(Type::Bool), bool_(value) {}
    Json(int value) : type_(Type::Int), int_(value) {}
    Json(long long value) : type_(Type::Int), int_(value) {}
    Json(std::uint32_t value) : type_(Type::Int), int_(value) {}
    Json(double value) : type_(Type::Real), real_(value) {}
    Json(const char* value) : type_(Type::String), string_(value) {}
    Json(std::string value) : type_(Type::String), string_(std::move(value)) {}

    static Json array() { Json json; json.type_ = Type::Array; return json; }
    static Json object() { Json json; json.type_ = Type::Object; return json; }

    Json& operator[](const std::string& key) {
        if (type_ != Type::Object) *this = object();
        for (auto& entry : members_)
            if (entry.first == key) return entry.second;
        members_.emplace_back(key, Json());
        return members_.back().second;
    }

    void push(Json value) {
        if (type_ != Type::Array) *this = array();
        items_.push_back(std::move(value));
    }

    std::size_t size() const { return type_ == Type::Array ? items_.size() : members_.size(); }

    std::string dump() const {
        std::string out;
        write(out, 0);
        out += "\n";
        return out;
    }

private:
    static void indent(std::string& out, int depth) { out.append(static_cast<std::size_t>(depth) * 2, ' '); }

    static void writeString(std::string& out, const std::string& text) {
        out += '"';
        for (unsigned char c : text) {
            switch (c) {
                case '"': out += "\\\""; break;
                case '\\': out += "\\\\"; break;
                case '\n': out += "\\n"; break;
                case '\r': out += "\\r"; break;
                case '\t': out += "\\t"; break;
                default:
                    if (c < 0x20) {
                        char escaped[8];
                        std::snprintf(escaped, sizeof(escaped), "\\u%04x", c);
                        out += escaped;
                    } else {
                        out += static_cast<char>(c);
                    }
            }
        }
        out += '"';
    }

    void write(std::string& out, int depth) const {
        char number[64];
        switch (type_) {
            case Type::Null: out += "null"; break;
            case Type::Bool: out += bool_ ? "true" : "false"; break;
            case Type::Int: out += std::to_string(int_); break;
            case Type::Real: {
                std::snprintf(number, sizeof(number), "%.3f", real_);
                std::string text = number;
                while (text.size() > 1 && text.back() == '0' && text[text.size() - 2] != '.') text.pop_back();
                out += text;
                break;
            }
            case Type::String: writeString(out, string_); break;
            case Type::Array:
                if (items_.empty()) { out += "[]"; break; }
                out += "[\n";
                for (std::size_t i = 0; i < items_.size(); ++i) {
                    indent(out, depth + 1);
                    items_[i].write(out, depth + 1);
                    out += i + 1 < items_.size() ? ",\n" : "\n";
                }
                indent(out, depth);
                out += "]";
                break;
            case Type::Object:
                if (members_.empty()) { out += "{}"; break; }
                out += "{\n";
                for (std::size_t i = 0; i < members_.size(); ++i) {
                    indent(out, depth + 1);
                    writeString(out, members_[i].first);
                    out += ": ";
                    members_[i].second.write(out, depth + 1);
                    out += i + 1 < members_.size() ? ",\n" : "\n";
                }
                indent(out, depth);
                out += "}";
                break;
        }
    }

    Type type_ = Type::Null;
    bool bool_ = false;
    long long int_ = 0;
    double real_ = 0.0;
    std::string string_;
    std::vector<Json> items_;
    std::vector<std::pair<std::string, Json>> members_;
};

// ---------------------------------------------------------------------------
// Helpers

std::string utcNow() {
    const auto now = std::chrono::system_clock::now();
    const std::time_t seconds = std::chrono::system_clock::to_time_t(now);
    const auto millis = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count() % 1000;
    std::tm utc{};
    gmtime_r(&seconds, &utc);
    char text[40];
    std::strftime(text, sizeof(text), "%Y-%m-%dT%H:%M:%S", &utc);
    char result[64];
    std::snprintf(result, sizeof(result), "%s.%03lld+00:00", text, static_cast<long long>(millis));
    return result;
}

double rounded(double seconds) { return std::round(seconds * 1000.0) / 1000.0; }

// Same rule as capture-pine-ee.py's safe_label().
std::string safeLabel(const std::string& label) {
    std::string cleaned;
    bool lastWasDash = false;
    for (unsigned char c : label) {
        if (std::isalnum(c) || c == '.' || c == '_' || c == '-') {
            cleaned += static_cast<char>(c);
            lastWasDash = false;
        } else if (!lastWasDash) {
            cleaned += '-';
            lastWasDash = true;
        }
    }
    const auto first = cleaned.find_first_not_of("-._");
    const auto last = cleaned.find_last_not_of("-._");
    if (first == std::string::npos) return "";
    return cleaned.substr(first, last - first + 1);
}

std::string lower(std::string text) {
    std::transform(text.begin(), text.end(), text.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return text;
}

void writeFileAtomically(const fs::path& path, const std::string& text) {
    const fs::path temporary = path.string() + ".tmp";
    {
        std::ofstream out(temporary, std::ios::binary | std::ios::trunc);
        if (!out) throw std::runtime_error("Could not write " + temporary.string());
        out << text;
        if (!out) throw std::runtime_error("Could not write " + temporary.string());
    }
    fs::rename(temporary, path);
}

struct Release {
    std::string title, gameId, gameVersion, gameCrc;
    bool operator==(const Release& other) const {
        return title == other.title && gameId == other.gameId && gameVersion == other.gameVersion && gameCrc == other.gameCrc;
    }
    bool operator!=(const Release& other) const { return !(*this == other); }
    Json toJson() const {
        Json json = Json::object();
        json["title"] = title;
        json["game_id"] = gameId;
        json["game_version"] = gameVersion;
        json["game_crc"] = gameCrc;
        return json;
    }
};

// Exact-build File 1 maps, as in tools-n-shit/file1_run_monitor.py.
struct File1Profile {
    const char* gameId;
    const char* gameVersion;
    const char* gameCrc;
    std::uint32_t frames, scenario, player, pass1;
    bool usPuzzlePolicy;
};

const File1Profile kProfiles[] = {
    {"SLUS-20765", "2.00", "0245ef6d", 0x004BADE8, 0x003243DA, 0x004A5C30, 0x004B9A83, true},
    {"SLUS-20765", "2.00", "0244e76c", 0x004BADE8, 0x003243DA, 0x004A5C30, 0x004B9A83, true},
    {"SLPM-65428", "1.04", "32088394", 0x0048BF78, 0x003065AA, 0x00476DD0, 0x0048AC13, false},
};

const File1Profile* profileFor(const Release& release) {
    for (const auto& profile : kProfiles)
        if (release.gameId == profile.gameId && release.gameVersion == profile.gameVersion && lower(release.gameCrc) == profile.gameCrc)
            return &profile;
    return nullptr;
}

Json usPuzzlePolicy() {
    Json policy = Json::object();
    policy["basis"] = "user confirms community update changes some Hive puzzles";
    policy["update_context"] = "Ver2.162 research context; disc metadata alone does not identify the update";
    policy["multiple_combinations_possible"] = true;
    policy["observation_scope"] = "current_recording";
    policy["reuse_observed_codes_as_defaults"] = false;
    policy["solution_algorithm"] = "unresolved";
    return policy;
}

// ---------------------------------------------------------------------------
// PINE access. Every exchange holds mac_pine_mutex so the reader and the
// recorder never interleave on the shared connection.

std::string takePineString(char* text) {
    std::string result = text ? text : "";
    delete[] text;
    return result;
}

Release readRelease() {
    std::lock_guard<std::mutex> lock(mac_pine_mutex);
    Release release;
    release.title = takePineString(mac_pine.GetGameTitle());
    release.gameId = takePineString(mac_pine.GetGameID());
    release.gameCrc = lower(takePineString(mac_pine.GetGameUUID()));
    release.gameVersion = takePineString(mac_pine.GetGameVersion());
    return release;
}

struct Observation {
    std::uint32_t frames = 0;
    std::uint16_t scenario = 0, scenarioAfter = 0, room = 0;
    std::uint8_t enabled = 0, pass1 = 0;
};

Observation readObservation(const File1Profile& profile) {
    const std::uint32_t player = profile.player;  // player slot 1
    std::lock_guard<std::mutex> lock(mac_pine_mutex);
    mac_pine.InitializeBatch();
    mac_pine.Read<std::uint32_t, true>(profile.frames);
    mac_pine.Read<std::uint16_t, true>(profile.scenario);
    mac_pine.Read<std::uint8_t, true>(player);
    mac_pine.Read<std::uint16_t, true>(player + kRoomOffset);
    mac_pine.Read<std::uint8_t, true>(profile.pass1);
    mac_pine.Read<std::uint16_t, true>(profile.scenario);
    auto batch = mac_pine.FinalizeBatch();
    mac_pine.SendCommand(batch);
    Observation observation;
    observation.frames = mac_pine.GetReply<PINE::PCSX2::MsgRead32>(batch, 0);
    observation.scenario = mac_pine.GetReply<PINE::PCSX2::MsgRead16>(batch, 1);
    observation.enabled = mac_pine.GetReply<PINE::PCSX2::MsgRead8>(batch, 2);
    observation.room = mac_pine.GetReply<PINE::PCSX2::MsgRead16>(batch, 3);
    observation.pass1 = mac_pine.GetReply<PINE::PCSX2::MsgRead8>(batch, 4);
    observation.scenarioAfter = mac_pine.GetReply<PINE::PCSX2::MsgRead16>(batch, 5);
    return observation;
}

// Reads the whole EE RAM in batches. Returns false if stopping was requested.
bool readEERam(std::vector<std::uint8_t>& memory, const std::atomic<bool>& stopRequested) {
    memory.resize(kEERamSize);
    for (std::uint32_t start = 0; start < kEERamSize; start += kReadsPerBatch * 8) {
        if (stopRequested) return false;
        const std::uint32_t count = std::min(kReadsPerBatch, (kEERamSize - start) / 8);
        {
            std::lock_guard<std::mutex> lock(mac_pine_mutex);
            mac_pine.InitializeBatch();
            for (std::uint32_t i = 0; i < count; ++i)
                mac_pine.Read<std::uint64_t, true>(start + i * 8);
            auto batch = mac_pine.FinalizeBatch();
            mac_pine.SendCommand(batch);
            for (std::uint32_t i = 0; i < count; ++i) {
                const std::uint64_t value = mac_pine.GetReply<PINE::PCSX2::MsgRead64>(batch, static_cast<int>(i));
                std::memcpy(&memory[start + i * 8], &value, sizeof(value));
            }
        }
        // Let the tracker's own reads run between batches.
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    return true;
}

template <typename T>
T valueAt(const std::vector<std::uint8_t>& memory, std::uint32_t address) {
    T value{};
    if (address + sizeof(T) <= memory.size()) std::memcpy(&value, &memory[address], sizeof(T));
    return value;
}

// ---------------------------------------------------------------------------
// Room readiness, ported from RoomMonitor in tools-n-shit/file1_run_monitor.py:
// a room counts as loaded after two matching polls with an advancing clock.

class RoomMonitor {
public:
    std::vector<Json> update(const Observation& current) {
        std::vector<Json> events;
        const bool hadPrevious = hasPrevious_;
        const Observation previous = previous_;
        previous_ = current;
        hasPrevious_ = true;
        const bool knownScenario = std::find(std::begin(kFile1Scenarios), std::end(kFile1Scenarios), current.scenario) != std::end(kFile1Scenarios);
        if (current.scenario != current.scenarioAfter || !knownScenario || current.frames == 0) {
            hasPrevious_ = false;
            hasLastRoom_ = false;
            return events;
        }
        if (hadPrevious && (current.scenario != previous.scenario || current.frames < previous.frames)) {
            hasLastRoom_ = false;
            return events;
        }
        if (current.enabled != 1 || current.room == 0 || current.room >= 128) {
            hasPrevious_ = false;
            return events;
        }
        const bool ready = hadPrevious && previous.enabled == 1 && current.room == previous.room && current.frames > previous.frames;
        if (!ready) return events;
        if (!hasLastRoom_ || lastScenario_ != current.scenario || lastRoom_ != current.room) {
            Json event = Json::object();
            event["kind"] = "room_loaded";
            event["scenario_id"] = static_cast<int>(current.scenario);
            event["previous_room_id"] = hasLastRoom_ ? Json(static_cast<int>(lastRoom_)) : Json();
            event["room_id"] = static_cast<int>(current.room);
            event["frames"] = current.frames;
            event["basis"] = "two stable room polls and advancing scenario clock";
            events.push_back(event);
            hasLastRoom_ = true;
            lastScenario_ = current.scenario;
            lastRoom_ = current.room;
        }
        return events;
    }

private:
    Observation previous_;
    bool hasPrevious_ = false;
    bool hasLastRoom_ = false;
    std::uint16_t lastScenario_ = 0, lastRoom_ = 0;
};

// ---------------------------------------------------------------------------
// Recorder

struct Marker {
    std::string capturedAt;
    std::chrono::steady_clock::time_point typedAt;
    std::string note;
};

class Recorder {
public:
    ~Recorder() { stop(); }

    // Returns an empty string on success, otherwise the reason it could not start.
    std::string start(const std::string& requestedLabel, const std::string& outputDir, double interval, double pollInterval) {
        stop();
        const std::string label = safeLabel(requestedLabel);
        if (label.empty()) return "Label must contain at least one letter or number";
        if (!(interval > 0) || !(pollInterval > 0) || !std::isfinite(interval) || !std::isfinite(pollInterval))
            return "Capture and poll intervals must be finite and greater than zero";
        const fs::path runDir = fs::path(outputDir) / label;
        std::error_code error;
        if (fs::exists(runDir, error)) return "Run folder already exists: " + runDir.string();

        label_ = label;
        runDir_ = runDir;
        interval_ = interval;
        pollInterval_ = pollInterval;
        stopRequested_ = false;
        {
            std::lock_guard<std::mutex> lock(statusMutex_);
            state_ = "waiting";
            message_ = "waiting for PCSX2 and a loaded game";
            checkpointCount_ = 0;
        }
        {
            std::lock_guard<std::mutex> lock(markerMutex_);
            pendingMarkers_.clear();
        }
        startedClock_ = std::chrono::steady_clock::now();
        worker_ = std::thread([this] { run(); });
        return "";
    }

    void stop() {
        stopRequested_ = true;
        wake_.notify_all();
        if (worker_.joinable()) worker_.join();
    }

    void mark(const std::string& note) {
        std::lock_guard<std::mutex> lock(markerMutex_);
        if (!worker_.joinable()) return;
        pendingMarkers_.push_back({utcNow(), std::chrono::steady_clock::now(), note});
        wake_.notify_all();
    }

    void pushStatus(lua_State* L) {
        std::lock_guard<std::mutex> lock(statusMutex_);
        lua_newtable(L);
        lua_pushstring(L, state_.c_str()); lua_setfield(L, -2, "state");
        lua_pushstring(L, label_.c_str()); lua_setfield(L, -2, "label");
        lua_pushstring(L, runDir_.string().c_str()); lua_setfield(L, -2, "folder");
        lua_pushinteger(L, checkpointCount_); lua_setfield(L, -2, "checkpoints");
        lua_pushstring(L, message_.c_str()); lua_setfield(L, -2, "message");
    }

private:
    double elapsedSeconds() const {
        return std::chrono::duration<double>(std::chrono::steady_clock::now() - startedClock_).count();
    }

    void setStatus(const std::string& state, const std::string& message) {
        std::lock_guard<std::mutex> lock(statusMutex_);
        state_ = state;
        message_ = message;
        checkpointCount_ = static_cast<int>(manifest_["checkpoints"].size());
    }

    void writeManifest() { writeFileAtomically(runDir_ / "manifest.json", manifest_.dump()); }

    // Waits until the deadline or until stop/marker activity wakes the thread.
    void waitUntil(std::chrono::steady_clock::time_point deadline) {
        std::unique_lock<std::mutex> lock(markerMutex_);
        wake_.wait_until(lock, deadline, [this] { return stopRequested_.load() || !pendingMarkers_.empty(); });
    }

    void createRun() {
        fs::create_directories(runDir_.parent_path());
        if (!fs::create_directory(runDir_)) throw std::runtime_error("Run folder already exists: " + runDir_.string());
        manifest_ = Json::object();
        manifest_["label"] = label_;
        manifest_["started_at_utc"] = startedAt_;
        manifest_["stopped_at_utc"] = Json();
        manifest_["status"] = "recording";
        manifest_["interval_seconds"] = interval_;
        manifest_["capture_source"] = "PCSX2 PINE read-only full EE memory checkpoints";
        manifest_["recorder"] = "Outbreak Tracker debug build";
        manifest_["ee_ram_size"] = kEERamSize;
        manifest_["release"] = Json();
        manifest_["checkpoints"] = Json::array();
        manifest_["markers"] = Json::array();
        manifest_["events"] = Json::array();
        Json monitor = Json::object();
        monitor["poll_interval_seconds"] = pollInterval_;
        monitor["player_slot"] = 1;
        monitor["room_load_rule"] = "two stable room polls with an advancing scenario clock";
        monitor["hive_passwords"] = false;
        monitor["checkpoint_on_marker"] = true;
        manifest_["monitor"] = monitor;
        writeManifest();
        std::cout << "Recorder: run folder " << runDir_.string() << std::endl;
    }

    // Moves typed markers into the manifest; returns their sequence numbers.
    std::vector<int> saveMarkers() {
        std::vector<Marker> markers;
        {
            std::lock_guard<std::mutex> lock(markerMutex_);
            markers.swap(pendingMarkers_);
        }
        std::vector<int> sequences;
        for (const auto& marker : markers) {
            const int sequence = static_cast<int>(manifest_["markers"].size()) + 1;
            const double elapsed = rounded(std::chrono::duration<double>(marker.typedAt - startedClock_).count());
            Json entry = Json::object();
            entry["sequence"] = sequence;
            entry["captured_at_utc"] = marker.capturedAt;
            entry["elapsed_seconds"] = elapsed;
            entry["note"] = marker.note;
            manifest_["markers"].push(entry);
            sequences.push_back(sequence);
            std::cout << "Recorder: marked +" << elapsed << "s: " << (marker.note.empty() ? "(no note)" : marker.note) << std::endl;
        }
        if (!sequences.empty()) writeManifest();
        return sequences;
    }

    // Saves one checkpoint. Returns false if stopping interrupted the read.
    bool saveCheckpoint(int sequence, const std::vector<std::string>& reasons,
                        const std::vector<int>& eventSequences, const std::vector<int>& markerSequences) {
        const auto checkpointStarted = std::chrono::steady_clock::now();
        const double elapsed = std::chrono::duration<double>(checkpointStarted - startedClock_).count();
        const std::string capturedAt = utcNow();
        const Release observed = readRelease();
        if (observed != release_)
            throw std::runtime_error("PCSX2 release metadata changed during the run; recording stopped to avoid mixing builds");
        if (!readEERam(memory_, stopRequested_)) return false;
        const auto checkpointFinished = std::chrono::steady_clock::now();

        char number[8];
        std::snprintf(number, sizeof(number), "%05d", sequence);
        const std::string checkpointLabel = label_ + "-" + number;
        const std::string stem = checkpointLabel + "-" + safeLabel(release_.gameId) + "-" + safeLabel(release_.gameCrc);
        const fs::path memoryPath = runDir_ / (stem + ".bin.gz");
        const fs::path metadataPath = runDir_ / (stem + ".json");
        const fs::path partialPath = runDir_ / (stem + ".bin.gz.partial");
        if (fs::exists(memoryPath) || fs::exists(metadataPath) || fs::exists(partialPath))
            throw std::runtime_error("Capture already exists: " + memoryPath.string());

        gzFile gz = gzopen(partialPath.c_str(), "wb1");
        if (!gz) throw std::runtime_error("Could not create " + partialPath.string());
        std::size_t written = 0;
        while (written < memory_.size()) {
            const unsigned chunk = static_cast<unsigned>(std::min<std::size_t>(1024 * 1024, memory_.size() - written));
            if (gzwrite(gz, memory_.data() + written, chunk) != static_cast<int>(chunk)) {
                gzclose(gz);
                fs::remove(partialPath);
                throw std::runtime_error("Could not compress " + memoryPath.string());
            }
            written += chunk;
        }
        if (gzclose(gz) != Z_OK) {
            fs::remove(partialPath);
            throw std::runtime_error("Could not finish " + memoryPath.string());
        }
        fs::rename(partialPath, memoryPath);

        Json metadata = Json::object();
        metadata["label"] = checkpointLabel;
        metadata["title"] = release_.title;
        metadata["game_id"] = release_.gameId;
        metadata["game_crc"] = release_.gameCrc;
        metadata["game_version"] = release_.gameVersion;
        metadata["ee_ram_size"] = kEERamSize;
        metadata["memory_file"] = memoryPath.filename().string();
        metadata["byte_order"] = "little";
        metadata["capture_source"] = "PCSX2 PINE read-only EE memory reads";
        metadata["compression"] = "gzip";
        metadata["captured_at_utc"] = capturedAt;
        metadata["elapsed_seconds"] = rounded(elapsed);
        writeFileAtomically(metadataPath, metadata.dump());

        // A few typed values from the saved image, not a second live sample.
        Json file1State;
        if (const File1Profile* profile = profileFor(release_)) {
            file1State = Json::object();
            file1State["frames"] = valueAt<std::uint32_t>(memory_, profile->frames);
            file1State["scenario_id"] = static_cast<int>(valueAt<std::uint16_t>(memory_, profile->scenario));
            file1State["room_id"] = static_cast<int>(valueAt<std::uint16_t>(memory_, profile->player + kRoomOffset));
            file1State["player_enabled"] = static_cast<int>(valueAt<std::uint8_t>(memory_, profile->player));
            file1State["pass1_raw"] = static_cast<int>(valueAt<std::uint8_t>(memory_, profile->pass1));
        }

        Json entry = Json::object();
        entry["sequence"] = sequence;
        entry["captured_at_utc"] = capturedAt;
        entry["elapsed_seconds"] = rounded(elapsed);
        entry["capture_duration_seconds"] = rounded(std::chrono::duration<double>(checkpointFinished - checkpointStarted).count());
        entry["memory_file"] = memoryPath.filename().string();
        entry["metadata_file"] = metadataPath.filename().string();
        Json reasonList = Json::array();
        for (const auto& reason : reasons) reasonList.push(reason);
        entry["reasons"] = reasonList;
        Json events = Json::array();
        for (int value : eventSequences) events.push(value);
        entry["event_sequences"] = events;
        Json markers = Json::array();
        for (int value : markerSequences) markers.push(value);
        entry["marker_sequences"] = markers;
        entry["file1_state"] = file1State;
        entry["hive_password_lookup"] = Json();
        manifest_["checkpoints"].push(entry);
        writeManifest();

        std::string reasonText;
        for (const auto& reason : reasons) reasonText += (reasonText.empty() ? "" : ", ") + reason;
        std::printf("Recorder: saved checkpoint %d at +%.1fs (%.1fs read, %s): %s\n", sequence, elapsed,
                    std::chrono::duration<double>(checkpointFinished - checkpointStarted).count(),
                    reasonText.c_str(), memoryPath.filename().c_str());
        std::fflush(stdout);
        return true;
    }

    // Waits for a game to be loaded, then fixes the release for the whole run.
    bool waitForRelease() {
        while (!stopRequested_) {
            try {
                Release release = readRelease();
                if (!release.gameId.empty()) {
                    release_ = release;
                    return true;
                }
            } catch (...) {
                // PCSX2 is not running, PINE is off, or no game is loaded yet.
            }
            waitUntil(std::chrono::steady_clock::now() + std::chrono::seconds(2));
            std::lock_guard<std::mutex> lock(markerMutex_);
            pendingMarkers_.clear();  // there is no run folder to hold them yet
        }
        return false;
    }

    void run() {
        if (!waitForRelease()) {
            setStatus("stopped", "stopped before a game was loaded");
            return;
        }
        int sequence = 0;
        try {
            startedClock_ = std::chrono::steady_clock::now();
            startedAt_ = utcNow();
            createRun();
            manifest_["release"] = release_.toJson();
            const File1Profile* profile = profileFor(release_);
            if (profile && profile->usPuzzlePolicy) manifest_["monitor"]["puzzle_policy"] = usPuzzlePolicy();
            if (!profile) std::cout << "Recorder: no exact-build room profile; periodic and marker checkpoints remain active." << std::endl;
            writeManifest();
            setStatus("recording", "");

            RoomMonitor monitor;
            const auto interval = std::chrono::duration_cast<std::chrono::steady_clock::duration>(std::chrono::duration<double>(interval_));
            const auto pollInterval = std::chrono::duration_cast<std::chrono::steady_clock::duration>(std::chrono::duration<double>(pollInterval_));
            auto nextPeriodic = startedClock_;
            auto nextPoll = startedClock_;
            std::vector<std::string> reasons;
            std::vector<int> eventSequences, markerSequences;

            while (!stopRequested_) {
                const auto saved = saveMarkers();
                if (!saved.empty()) {
                    reasons.push_back("marker");
                    markerSequences.insert(markerSequences.end(), saved.begin(), saved.end());
                }
                auto now = std::chrono::steady_clock::now();
                if (profile && now >= nextPoll) {
                    if (readRelease() != release_)
                        throw std::runtime_error("PCSX2 release metadata changed; recording stopped to avoid mixing builds");
                    const Observation observation = readObservation(*profile);
                    nextPoll = std::chrono::steady_clock::now() + pollInterval;
                    for (Json event : monitor.update(observation)) {
                        const int eventSequence = static_cast<int>(manifest_["events"].size()) + 1;
                        Json entry = Json::object();
                        entry["sequence"] = eventSequence;
                        entry["captured_at_utc"] = utcNow();
                        entry["elapsed_seconds"] = rounded(elapsedSeconds());
                        entry["kind"] = "room_loaded";
                        entry["scenario_id"] = event["scenario_id"];
                        entry["previous_room_id"] = event["previous_room_id"];
                        entry["room_id"] = event["room_id"];
                        entry["frames"] = event["frames"];
                        entry["basis"] = event["basis"];
                        manifest_["events"].push(entry);
                        eventSequences.push_back(eventSequence);
                        reasons.push_back("room_loaded");
                        std::cout << "Recorder: room loaded (sampled): scenario " << observation.scenario
                                  << ", room " << observation.room << std::endl;
                        writeManifest();
                    }
                }
                now = std::chrono::steady_clock::now();
                if (now >= nextPeriodic) {
                    reasons.push_back("interval");
                    // Keep the periodic cadence independent of event-triggered captures.
                    const auto missed = (now - nextPeriodic) / interval;
                    nextPeriodic += (missed + 1) * interval;
                }
                if (reasons.empty()) {
                    auto deadline = nextPeriodic;
                    if (profile) deadline = std::min(deadline, nextPoll);
                    waitUntil(deadline);
                    continue;
                }
                std::vector<std::string> uniqueReasons;
                for (const auto& reason : reasons)
                    if (std::find(uniqueReasons.begin(), uniqueReasons.end(), reason) == uniqueReasons.end())
                        uniqueReasons.push_back(reason);
                if (!saveCheckpoint(sequence + 1, uniqueReasons, eventSequences, markerSequences)) break;
                ++sequence;
                setStatus("recording", "");
                reasons.clear();
                eventSequences.clear();
                markerSequences.clear();
            }
            saveMarkers();
            manifest_["status"] = "stopped_by_user";
            manifest_["stopped_at_utc"] = utcNow();
            writeManifest();
            setStatus("stopped", "");
            std::cout << "Recorder: stopped. Manifest: " << (runDir_ / "manifest.json").string() << std::endl;
        } catch (const std::exception& error) {
            finishWithError(error.what());
        } catch (...) {
            finishWithError("PINE request failed (PCSX2 closed or the game was unloaded)");
        }
    }

    void finishWithError(const std::string& message) {
        std::cerr << "Recorder: " << message << std::endl;
        try {
            if (fs::exists(runDir_ / "manifest.json")) {
                saveMarkers();
                manifest_["status"] = "error";
                manifest_["error"] = message;
                manifest_["stopped_at_utc"] = utcNow();
                writeManifest();
            }
            for (const auto& entry : fs::directory_iterator(runDir_))
                if (entry.path().extension() == ".partial") fs::remove(entry.path());
        } catch (...) {
        }
        setStatus("error", message);
    }

    std::string label_;
    fs::path runDir_;
    double interval_ = 10.0;
    double pollInterval_ = 0.5;
    std::string startedAt_;
    std::chrono::steady_clock::time_point startedClock_;
    Release release_;
    Json manifest_;
    std::vector<std::uint8_t> memory_;

    std::thread worker_;
    std::atomic<bool> stopRequested_{false};
    std::condition_variable wake_;
    std::mutex markerMutex_;
    std::vector<Marker> pendingMarkers_;

    std::mutex statusMutex_;
    std::string state_ = "idle";
    std::string message_;
    int checkpointCount_ = 0;
};

Recorder& recorder() {
    static Recorder instance;
    return instance;
}

// Lines typed into the terminal that launched the tracker become markers,
// like the notes typed into record-pine-ee-run.py.
void startTerminalMarkers() {
    static bool started = false;
    if (started || !isatty(STDIN_FILENO)) return;
    started = true;
    std::thread([] {
        std::string line;
        while (std::getline(std::cin, line)) {
            const auto first = line.find_first_not_of(" \t\r");
            const auto last = line.find_last_not_of(" \t\r");
            recorder().mark(first == std::string::npos ? "" : line.substr(first, last - first + 1));
        }
    }).detach();
}

// recorder.start(label, outputDir [, intervalSeconds [, pollSeconds]]) -> true | nil, message
int LStart(lua_State* L) {
    const std::string label = luaL_checkstring(L, 1);
    const std::string outputDir = luaL_checkstring(L, 2);
    const double interval = luaL_optnumber(L, 3, 10.0);
    const double pollInterval = luaL_optnumber(L, 4, 0.5);
    const std::string error = recorder().start(label, outputDir, interval, pollInterval);
    if (!error.empty()) {
        lua_pushnil(L);
        lua_pushstring(L, error.c_str());
        return 2;
    }
    startTerminalMarkers();
    lua_pushboolean(L, 1);
    return 1;
}

int LStop(lua_State*) {
    recorder().stop();
    return 0;
}

int LMark(lua_State* L) {
    recorder().mark(luaL_optstring(L, 1, ""));
    return 0;
}

int LStatus(lua_State* L) {
    recorder().pushStatus(L);
    return 1;
}

const luaL_Reg kRecorderFunctions[] = {
    {"start", LStart},
    {"stop", LStop},
    {"mark", LMark},
    {"status", LStatus},
    {nullptr, nullptr},
};

}  // namespace

extern "C" __attribute__((visibility("default"))) int luaopen_luaoutbreakrecorder(lua_State* L) {
    lua_newtable(L);
    luaL_register(L, nullptr, kRecorderFunctions);
    return 1;
}
