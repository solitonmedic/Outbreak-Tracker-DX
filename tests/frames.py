"""Shared helpers for the gameplay-frame tests: frame files, the fake PINE
server and result comparison.

Purpose: reusable library imported by tests/run_frames.py, tests/decky_frames.py
  and the local frame-extraction tool. Not run on its own.
Location/language: tests/frames.py; Python 3 standard library.
Frame file format (.otf): the 8 bytes "OTFRAME1", then records of
  u32 address, u32 length (little endian) and that many bytes of EE RAM.
  Bytes not in a record read as 0. Addresses are EE RAM offsets below 32 MiB.
FakePine: a PINE server on <folder>/pcsx2.sock (the path pine.h uses from
  TMPDIR on macOS and XDG_RUNTIME_DIR on Linux) serving one frame. It answers
  read opcodes 0-3 only (8/16/32/64-bit), records any other opcode as an
  error, and returns zeros outside the 32 MiB EE RAM.
Safety: serves synthetic or trimmed memory only, on a socket in a temporary
  folder, so the real PCSX2 is never contacted.
Check: exercised by tests/run_frames.py --self-test.
"""
import json
import math
import socket
import struct
import threading
from pathlib import Path

MAGIC = b"OTFRAME1"
EE_RAM = 32 * 1024 * 1024


def write_frame(path, ranges):
    """ranges: iterable of (address, bytes); written sorted, merged if touching."""
    merged = []
    for address, data in sorted(ranges):
        if merged and address <= merged[-1][0] + len(merged[-1][1]):
            start, old = merged[-1]
            end = max(start + len(old), address + len(data))
            buf = bytearray(end - start)
            buf[:len(old)] = old
            buf[address - start:address - start + len(data)] = data
            merged[-1] = (start, bytes(buf))
        else:
            merged.append((address, bytes(data)))
    with open(path, "wb") as f:
        f.write(MAGIC)
        for address, data in merged:
            assert 0 <= address and address + len(data) <= EE_RAM
            f.write(struct.pack("<II", address, len(data)))
            f.write(data)


def read_frame(path):
    """Return the frame as a 32 MiB bytearray (unlisted bytes are zero)."""
    memory = bytearray(EE_RAM)
    data = Path(path).read_bytes()
    if data[:8] != MAGIC:
        raise ValueError("not a frame file: %s" % path)
    pos = 8
    while pos < len(data):
        address, length = struct.unpack_from("<II", data, pos)
        pos += 8
        if address + length > EE_RAM or pos + length > len(data):
            raise ValueError("damaged frame file: %s" % path)
        memory[address:address + length] = data[pos:pos + length]
        pos += length
    return memory


class FakePine:
    """One PINE endpoint at <folder>/pcsx2.sock serving `memory` (read-only)."""

    def __init__(self, folder, memory):
        self.memory = memory
        self.path = Path(folder) / "pcsx2.sock"
        self.socket = socket.socket(socket.AF_UNIX)
        self.socket.bind(str(self.path))
        self.socket.listen()
        self.socket.settimeout(0.2)
        self.stopped = threading.Event()
        self.errors = []
        self.messages = 0
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def read(self, address, size):
        end = address + size
        if end <= EE_RAM:
            return bytes(self.memory[address:end])
        part = bytes(self.memory[address:EE_RAM]) if address < EE_RAM else b""
        return part + bytes(size - len(part))

    def run(self):
        def exact(client, count):
            data = b""
            while len(data) < count:
                part = client.recv(count - len(data))
                if not part:
                    raise ConnectionError()
                data += part
            return data
        while not self.stopped.is_set():
            try:
                client, _ = self.socket.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            with client:
                try:
                    while not self.stopped.is_set():
                        size = struct.unpack("<I", exact(client, 4))[0]
                        body = exact(client, size - 4)
                        self.messages += 1
                        output = bytearray(b"\0")
                        for pos in range(0, len(body), 5):
                            opcode = body[pos]
                            if opcode not in (0, 1, 2, 3):
                                raise AssertionError("reader sent a non-read PINE operation %d" % opcode)
                            address = struct.unpack_from("<I", body, pos + 1)[0]
                            output += self.read(address, 1 << opcode)
                        client.sendall(struct.pack("<I", len(output) + 4) + output)
                except (ConnectionError, OSError):
                    pass
                except Exception as error:  # reported by the runner
                    self.errors.append(str(error))

    def stop(self):
        self.stopped.set()
        self.thread.join(timeout=2)
        self.socket.close()
        self.path.unlink(missing_ok=True)


def flatten(value, prefix="", out=None):
    """Nested JSON value -> {dotted.path: leaf}."""
    if out is None:
        out = {}
    if isinstance(value, dict):
        for key in sorted(value, key=str):
            flatten(value[key], "%s.%s" % (prefix, key) if prefix else str(key), out)
    elif isinstance(value, list):
        out[prefix + ".#"] = len(value)
        for index, item in enumerate(value):
            flatten(item, "%s.%d" % (prefix, index + 1), out)
    else:
        out[prefix] = value
    return out


def same(a, b):
    if isinstance(a, (int, float)) and isinstance(b, (int, float)) and not isinstance(a, bool) and not isinstance(b, bool):
        if math.isnan(a) or math.isnan(b):
            return math.isnan(a) and math.isnan(b)
        return abs(a - b) <= 1e-6 * max(1.0, abs(a), abs(b))
    return a == b


def compare(expected, actual):
    """Return a list of 'path: expected X, got Y' for every differing leaf."""
    e, a = flatten(expected), flatten(actual)
    problems = []
    for key in sorted(set(e) | set(a)):
        if key not in a:
            problems.append("%s: expected %r, missing" % (key, e[key]))
        elif key not in e:
            problems.append("%s: unexpected %r" % (key, a[key]))
        elif not same(e[key], a[key]):
            problems.append("%s: expected %r, got %r" % (key, e[key], a[key]))
    return problems


def check_facts(entry, actual):
    """entry: {"facts": {dotted.path: value}, "texts": [substring, ...]}.
    Every listed path must hold its value, and every listed text must appear in
    the drawn text of at least one view (for example a puzzle answer)."""
    a = flatten(actual)
    problems = []
    for key, value in (entry.get("facts") or {}).items():
        if key not in a:
            problems.append("fact %s: expected %r, missing" % (key, value))
        elif not same(value, a[key]):
            problems.append("fact %s: expected %r, got %r" % (key, value, a[key]))
    drawn = [t for view in actual.get("views") or [] for t in view.get("texts") or []]
    for text in entry.get("texts") or []:
        if not any(text in t for t in drawn):
            problems.append("fact: text %r is not drawn in any view" % text)
    return problems


def load_json(path):
    def constant(name):
        return {"NaN": math.nan, "Infinity": math.inf, "-Infinity": -math.inf}[name]
    return json.loads(Path(path).read_text(), parse_constant=constant)
