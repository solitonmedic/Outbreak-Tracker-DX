"""Reusable LAN tracker service; Python 3 standard library and native LuaJIT reader.
Inputs: installed plugin files, read-only PINE, bounded authenticated browser keys.
Outputs: in-memory drawing frames and HTTP on LAN port 28080; no frame files.
Safety: per-start secret link protects data/control; static package assets only;
no recordings, emulator writes, shell commands, filesystem browsing or sudo.
Run: started/stopped by the Decky backend; standalone diagnostic mode at file end.
Check: open the private link in Decky, verify live status and original tracker UI.
"""
import argparse
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import mimetypes
from pathlib import Path
import queue
import secrets
import select
import shutil
import socket
import subprocess
import threading
import time
from urllib.parse import unquote, urlsplit
import os

KEYS = {"f1", "f2", "f3", "f4", "d", "h", "v", "l", "t", "i", "q", "e",
        "1", "2", "3", "4", "a", "kp0", "kp1", "kp2", "kp3", "kp4"}


class TrackerService:
    def __init__(self, plugin, port=28080):
        self.plugin = Path(plugin).resolve()
        self.port = port
        self.token = secrets.token_urlsafe(24)
        self.stopping = threading.Event()
        self.lock = threading.Lock()
        self.keys = queue.Queue(maxsize=32)
        self.process = None
        self.server = None
        self.worker = None
        self.http_thread = None
        self.frame = {"state": "waiting", "message": "Waiting for PCSX2 and a supported game", "commands": []}
        self.updated = time.monotonic()

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
            process = None
            try:
                executable = shutil.which("luajit")
                if not executable:
                    raise RuntimeError("LuaJIT is not installed on this Deck")
                env = dict(os.environ)
                env["XDG_RUNTIME_DIR"] = f"/run/user/{os.getuid()}"
                process = subprocess.Popen([executable, "reader.lua"], cwd=self.plugin, env=env,
                    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                self.process = process
                while not self.stopping.is_set():
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
            "phoneUrl": f"http://{address}:{self.port}/#{self.token}" if self.server else None,
            "connection": frame["state"], "lastError": frame.get("message"),
        }

    def start(self):
        if self.server:
            return
        self.stopping.clear()
        self.token = secrets.token_urlsafe(24)
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

            def authorized(self):
                supplied = self.headers.get("Authorization", "").encode()
                return hmac.compare_digest(supplied, ("Bearer " + service.token).encode())

            def do_GET(self):
                path = unquote(urlsplit(self.path).path)
                if path == "/api/frame":
                    if not self.authorized():
                        return self.json({"error": "Open the private connection link shown in Decky"}, 401)
                    return self.json(service.snapshot())
                if path == "/":
                    relative = Path("web/index.html")
                elif path.startswith("/assets/"):
                    relative = Path(path.lstrip("/"))
                elif path in {"/app.js", "/style.css"}:
                    relative = Path("web") / path[1:]
                else:
                    return self.json({"error": "Not found"}, 404)
                target = (service.plugin / relative).resolve()
                allowed = service.plugin / ("assets" if path.startswith("/assets/") else "web")
                if not target.is_relative_to(allowed) or not target.is_file():
                    return self.json({"error": "Not found"}, 404)
                return self.send_data(target.read_bytes(), mimetypes.guess_type(str(target))[0] or "application/octet-stream")

            def do_POST(self):
                if urlsplit(self.path).path != "/api/key":
                    return self.json({"error": "Not found"}, 404)
                if not self.authorized():
                    return self.json({"error": "Unauthorized"}, 401)
                try:
                    length = int(self.headers.get("Content-Length", "0"))
                    if not 0 < length <= 128:
                        raise ValueError()
                    key = json.loads(self.rfile.read(length))["key"]
                    if not isinstance(key, str) or key not in KEYS:
                        raise ValueError()
                    service.keys.put_nowait(key)
                except (ValueError, KeyError, TypeError, queue.Full):
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
    print("Service started; private link is available through the Decky status method.", flush=True)
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        service.stop()
