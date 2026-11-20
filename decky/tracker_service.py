"""Reusable LAN tracker service; Python 3 standard library and native LuaJIT reader.
Inputs: installed plugin files, read-only PINE, bounded browser keys/map actions and
an explicitly selected Japanese disc path from the local network. cache_dir or
OUTBREAK_MAP_CACHE selects the persistent art cache (default user data directory).
The M key toggles shared SP radar sound; it defaults on for each reader session.
Check the sound control offline from repo-merged/ with:
python3 tools-n-shit/tracker-tests/sp/check-sp-sound-frames.py
Outputs: in-memory drawing frames and HTTP on LAN port 28080; no frame files.
Safety: no login; serves only clients on private/link-local/loopback/Tailscale addresses, only
for IP-literal, single-label or .local host names (blocks DNS rebinding), and accepts keys only
as same-origin JSON POSTs (blocks other websites); package assets and private cached
map PNGs only; disc import runs MapImport.lua via argv and writes the cache. No recordings,
emulator writes, shell commands, filesystem browsing or sudo.
The reader runs only while a device is watching: it starts on the first frame request and
stops after IDLE_SECONDS without one, so PCSX2 gets no PINE traffic while nobody looks.
Run: started/stopped by the Decky backend; standalone diagnostic mode at file end.
Check: open the link shown in Decky, verify live status and original tracker UI.
"""
import argparse
import ipaddress
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import math
import mimetypes
from pathlib import Path
import queue
import select
import shutil
import socket
import subprocess
import threading
import time
from urllib.parse import unquote, urlsplit
import os

TAILSCALE = ipaddress.ip_network("100.64.0.0/10")
IDLE_SECONDS = 15
KEYS = {"f1", "f2", "f3", "f4", "d", "h", "v", "l", "t", "i", "q", "e", "m", "b", "n", "f",
        "1", "2", "3", "4", "a", "kp0", "kp1", "kp2", "kp3", "kp4"}


def local_client(address):
    """True for private, link-local, loopback and Tailscale client addresses."""
    try:
        ip = ipaddress.ip_address(address.split("%")[0])
    except ValueError:
        return False
    if isinstance(ip, ipaddress.IPv6Address) and ip.ipv4_mapped:
        ip = ip.ipv4_mapped
    return ip.is_private or ip.is_loopback or ip.is_link_local or (ip.version == 4 and ip in TAILSCALE)


def local_host(header):
    """True when the Host header names an IP literal, a single-label name or a .local name."""
    host = (header or "").strip().lower()
    if host.startswith("["):
        host = host[1:host.find("]")] if "]" in host else ""
    elif host.count(":") == 1:
        host = host.split(":")[0]
    if not host:
        return False
    try:
        ipaddress.ip_address(host)
        return True
    except ValueError:
        return "." not in host or host.endswith(".local")


class TrackerService:
    def __init__(self, plugin, port=28080, cache_dir=None):
        self.plugin = Path(plugin).resolve()
        self.port = port
        self.stopping = threading.Event()
        self.lock = threading.Lock()
        self.keys = queue.Queue(maxsize=32)
        self.process = None
        self.server = None
        self.worker = None
        self.http_thread = None
        self.frame = {"state": "idle", "message": "Reader paused until a device opens the tracker", "commands": []}
        self.updated = time.monotonic()
        self.runtime_dir = f"/run/user/{os.getuid()}"
        self.last_request = None
        self.wake = threading.Event()
        self.map_cache = Path(cache_dir or os.environ.get("OUTBREAK_MAP_CACHE", Path.home() / ".local/share/outbreak-tracker")).resolve()
        self.import_lock = threading.Lock()

    def import_maps(self, path):
        """Read an explicitly selected disc; publish only private cached map art.

        LuaJIT runs the same bounded parser as desktop, with argv (no shell).
        No PINE reader, recordings, file uploads or source-disc writes are involved.
        """
        if not isinstance(path, str) or not 0 < len(path) <= 4096 or "\0" in path:
            raise ValueError("Enter the disc folder or ISO path on the Deck")
        if not self.import_lock.acquire(blocking=False):
            raise ValueError("A map import is already running")
        try:
            executable = shutil.which("luajit")
            if not executable:
                raise ValueError("LuaJIT is unavailable")
            for game in (1, 2):
                (self.map_cache / f"maps/jp{game}").mkdir(parents=True, exist_ok=True)
            result = subprocess.run([executable, str(self.plugin / "shared/MapImport.lua"), path, str(self.map_cache)],
                                    capture_output=True, text=True, timeout=90)
            if result.returncode:
                raise ValueError("Cannot import this disc. Select an extracted Japanese disc folder, NETBIO00.DAT, or an ISO.")
            return result.stdout.strip()
        finally:
            self.import_lock.release()

    def watched(self):
        return self.last_request is not None and time.monotonic() - self.last_request < IDLE_SECONDS

    def touch(self):
        """Record a device request; wakes an idle reader."""
        self.last_request = time.monotonic()
        with self.lock:
            if self.frame.get("state") == "idle":
                self.frame = {"state": "waiting", "message": "Starting the reader", "commands": []}
                self.updated = time.monotonic()
        self.wake.set()

    def publish(self, frame):
        with self.lock:
            self.frame, self.updated = frame, time.monotonic()

    def snapshot(self):
        with self.lock:
            frame = dict(self.frame)
            age = time.monotonic() - self.updated
        frame["ageSeconds"] = round(age, 2)
        if age > 3 and frame.get("state") == "connected":
            frame["state"] = "stale"
            frame["message"] = "Reader delayed; these values are not current"
        return frame

    def reader_loop(self):
        while not self.stopping.is_set():
            if not self.watched():
                self.publish({"state": "idle", "message": "Reader paused until a device opens the tracker", "commands": []})
                while not self.stopping.is_set() and not self.watched():
                    self.wake.wait(1)
                    self.wake.clear()
                continue
            process = None
            failed = False
            try:
                executable = shutil.which("luajit")
                if not executable:
                    raise RuntimeError("LuaJIT is not installed on this Deck")
                env = dict(os.environ)
                env["XDG_RUNTIME_DIR"] = self.runtime_dir
                env["OUTBREAK_MAP_CACHE"] = str(self.map_cache)
                process = subprocess.Popen([executable, "reader.lua"], cwd=self.plugin, env=env,
                    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                self.process = process
                while not self.stopping.is_set() and self.watched():
                    keys = []
                    while not self.keys.empty():
                        try:
                            keys.append(self.keys.get_nowait())
                        except queue.Empty:
                            break
                    process.stdin.write((",".join(keys) + "\n").encode())
                    process.stdin.flush()
                    ready, _, _ = select.select([process.stdout], [], [], 8)
                    if not ready:
                        raise RuntimeError("PINE reader timed out; close other PINE clients and check PCSX2")
                    data = process.stdout.readline(2_000_000)
                    if not data or len(data) >= 2_000_000:
                        raise RuntimeError("PINE reader stopped or returned an invalid frame")
                    frame = json.loads(data)
                    if not isinstance(frame, dict):
                        raise RuntimeError("Reader returned an invalid frame")
                    self.publish(frame)
                    self.stopping.wait(0.2)
            except (OSError, ValueError, RuntimeError) as error:
                failed = True
                self.publish({"state": "error", "message": str(error), "commands": []})
            finally:
                if process:
                    if process.poll() is None:
                        process.terminate()
                        try:
                            process.wait(timeout=2)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait()
                    process.stdin.close()
                    process.stdout.close()
                self.process = None
            if failed:
                self.stopping.wait(2)

    def status(self):
        address = "127.0.0.1"
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            try:
                probe.connect(("192.0.2.1", 9))
                address = probe.getsockname()[0]
            except OSError:
                pass
        frame = self.snapshot()
        return {
            "running": self.server is not None,
            "phoneUrl": f"http://{address}:{self.port}/" if self.server else None,
            "connection": frame["state"], "lastError": frame.get("message"),
        }

    def start(self):
        if self.server:
            return
        self.stopping.clear()
        self.last_request = None
        service = self

        class Handler(BaseHTTPRequestHandler):
            def setup(self):
                super().setup()
                self.connection.settimeout(5)

            def log_message(self, *args):
                pass

            def send_data(self, data, mime, code=200):
                self.send_response(code)
                self.send_header("Content-Type", mime)
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Cache-Control", "no-store")
                self.send_header("X-Content-Type-Options", "nosniff")
                self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; font-src 'self'; img-src 'self'; connect-src 'self'; frame-ancestors 'none'")
                self.end_headers()
                self.wfile.write(data)

            def json(self, value, code=200):
                self.send_data(json.dumps(value, allow_nan=False).encode(), "application/json", code)

            def allowed(self):
                return local_client(self.client_address[0]) and local_host(self.headers.get("Host"))

            def do_GET(self):
                if not self.allowed():
                    return self.json({"error": "Only devices on the local network may connect"}, 403)
                path = unquote(urlsplit(self.path).path)
                if path == "/api/frame":
                    service.touch()
                    return self.json(service.snapshot())
                if path.startswith("/maps/"):
                    target = (service.map_cache / path.lstrip("/")).resolve()
                    if target.is_relative_to(service.map_cache / "maps") and target.suffix == ".png" and target.is_file():
                        return self.send_data(target.read_bytes(), "image/png")
                    return self.json({"error": "Not found"}, 404)
                if path == "/":
                    relative = Path("web/index.html")
                elif path.startswith("/assets/"):
                    relative = Path(path.lstrip("/"))
                elif path.startswith("/icons/"):
                    relative = Path("web") / path.lstrip("/")
                elif path in {"/app.js", "/style.css", "/manifest.webmanifest"}:
                    relative = Path("web") / path[1:]
                else:
                    return self.json({"error": "Not found"}, 404)
                target = (service.plugin / relative).resolve()
                allowed = service.plugin / ("assets" if path.startswith("/assets/") else "web/icons" if path.startswith("/icons/") else "web")
                if not target.is_relative_to(allowed) or not target.is_file():
                    return self.json({"error": "Not found"}, 404)
                return self.send_data(target.read_bytes(), mimetypes.guess_type(str(target))[0] or "application/octet-stream")

            def do_POST(self):
                route = urlsplit(self.path).path
                if route not in {"/api/key", "/api/map", "/api/map-import"}:
                    return self.json({"error": "Not found"}, 404)
                if not self.allowed():
                    return self.json({"error": "Only devices on the local network may connect"}, 403)
                origin = self.headers.get("Origin")
                if self.headers.get("Content-Type", "").split(";")[0].strip().lower() != "application/json" or (
                        origin and origin != "http://" + self.headers.get("Host", "")):
                    return self.json({"error": "Controls must come from the tracker page"}, 403)
                try:
                    length = int(self.headers.get("Content-Length", "0"))
                    if not 0 < length <= (8192 if route == "/api/map-import" else 256):
                        raise ValueError()
                    data = json.loads(self.rfile.read(length))
                    if route == "/api/map-import":
                        try:
                            return self.json({"message": service.import_maps(data["path"])})
                        except (OSError, ValueError, subprocess.TimeoutExpired) as error:
                            return self.json({"error": str(error)}, 400)
                    if route == "/api/map":
                        action, x, y = data["action"], data["x"], data["y"]
                        if action not in {"down", "move", "up", "in", "out", "fit"} or any(
                                type(v) not in (int, float) or not math.isfinite(v) or abs(v) > 10000 for v in (x, y)):
                            raise ValueError()
                        key = f"map/{action}/{x:.2f}/{y:.2f}"
                    else:
                        key = data["key"]
                        if not isinstance(key, str) or key not in KEYS:
                            raise ValueError()
                    service.keys.put_nowait(key)
                    service.touch()
                except (ValueError, KeyError, TypeError, AttributeError, queue.Full):
                    return self.json({"error": "Invalid control or control queue full"}, 400)
                return self.json({"ok": True})

        self.server = ThreadingHTTPServer(("0.0.0.0", self.port), Handler)
        self.server.daemon_threads = True
        self.worker = threading.Thread(target=self.reader_loop, name="outbreak-reader", daemon=True)
        self.http_thread = threading.Thread(target=self.server.serve_forever, name="outbreak-http", daemon=True)
        self.worker.start()
        self.http_thread.start()

    def stop(self):
        self.stopping.set()
        self.wake.set()
        if self.process and self.process.poll() is None:
            self.process.terminate()
        if self.server:
            self.server.shutdown()
            self.server.server_close()
            self.server = None
        if self.worker:
            self.worker.join(timeout=10)
        if self.http_thread:
            self.http_thread.join(timeout=2)
        self.publish({"state": "stopped", "commands": [], "message": "Phone view stopped"})


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=28080)
    args = parser.parse_args()
    service = TrackerService(Path(__file__).resolve().parent, args.port)
    service.start()
    print("Service started; the phone link is available through the Decky status method.", flush=True)
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        service.stop()
