#!/usr/bin/env python3
"""Check, and optionally fix, the layout and common mistakes in every file.

Purpose: the repository's one lint command, the same on macOS, Linux and
  Windows. It checks the rules in .editorconfig, keeps recordings, game files,
  secrets and personal paths out of the repository, wants a header comment in
  every script, checks JSON, Python and Lua syntax, and runs the pinned tools:
  StyLua and selene (Lua), clang-format (C and C++), Ruff (Python), ShellCheck
  (shell), Biome (the Decky JavaScript, TypeScript and CSS) and actionlint
  (GitHub workflows), plus a PowerShell syntax check where PowerShell exists.
Location/language: tests/lint.py; Python 3.9 or later, standard library only.
  Tool versions and downloads: tests/lint/tools.py. Files treated differently,
  with the reasons: tests/lint/settings.py.
Usage, from the repository root (on Windows, "py" instead of "python3"):
  python3 tests/lint.py --install-tools   download the pinned tools into .lint-tools/
  python3 tests/lint.py                   check every file Git knows about
  python3 tests/lint.py --fix             run the formatters and fix whitespace, then check
  python3 tests/lint.py --changed         only files changed against origin/dev (or dev)
  python3 tests/lint.py PATH ...          only these files or folders
  python3 tests/lint.py --strict          a missing tool counts as a problem (the GitHub checks)
Outputs: one line per problem, "path:line: rule: message", then a summary. The
  exit status is 1 when there are problems. On GitHub Actions every problem is
  also an annotation on the pull request.
Safety: reads files and runs the pinned tools on them. Only --fix writes to the
  repository (formatters and whitespace). --install-tools downloads over HTTPS
  into .lint-tools/ and checks each download's SHA-256 before using it.
Check: python3 tests/unit/check-lint.py writes one bad example for each rule
  and expects this script to report it.
"""

import argparse
import ast
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import zipfile

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / "lint"))
import settings  # noqa: E402
from tools import TOOLS  # noqa: E402

REPOSITORY = HERE.parent
TOOLS_FOLDER = REPOSITORY / ".lint-tools"
REPORTED_LINES_PER_RULE = 3  # per file; the rest are counted


class Problem:
    def __init__(self, path, line, rule, message):
        self.path, self.line, self.rule, self.message = path, line, rule, message

    def __str__(self):
        return "%s:%s: %s: %s" % (self.path, self.line or 1, self.rule, self.message)


# ------------------------------------------------------------------ files --


def run(command, cwd=None, input_bytes=None):
    """Run a command and return (exit status, stdout, stderr) as text."""
    result = subprocess.run(command, cwd=cwd, input=input_bytes, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return result.returncode, result.stdout.decode("utf-8", "replace"), result.stderr.decode("utf-8", "replace")


def list_files(root, paths, changed):
    """Files to check, relative to root and written with "/"."""
    if changed:
        return changed_files(root)
    status, out, _ = run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--"] + paths, cwd=root
    )
    if status != 0:
        raise SystemExit("lint: %s is not a Git checkout" % root)
    names = sorted(set(name for name in out.split("\0") if name))
    return [name for name in names if (root / name).is_file()]


def changed_files(root):
    base = None
    for candidate in ("origin/dev", "dev"):
        if run(["git", "rev-parse", "--verify", "--quiet", candidate], cwd=root)[0] == 0:
            base = candidate
            break
    names = set()
    commands = [
        ["git", "diff", "--name-only", "--diff-filter=ACMR", "HEAD"],
        ["git", "ls-files", "--others", "--exclude-standard"],
    ]
    if base:
        commands.append(["git", "diff", "--name-only", "--diff-filter=ACMR", base + "...HEAD"])
    for command in commands:
        names.update(line for line in run(command, cwd=root)[1].splitlines() if line)
    return sorted(name for name in names if (root / name).is_file())


def under(path, entries):
    """True if path is one of the entries, or below an entry that ends in "/"."""
    return any(path == entry or (entry.endswith("/") and path.startswith(entry)) for entry in entries)


def is_binary(path, data):
    return path.lower().endswith(settings.BINARY_ENDINGS) or b"\0" in data[:8192]


# ------------------------------------------------------------ editorconfig --


def glob_to_regex(glob):
    """Turn an EditorConfig section name into a regular expression for a path
    relative to the root. Supports *, **, ?, [...] and {a,b}, which is what
    this repository's .editorconfig uses."""
    if "/" not in glob:
        glob = "**/" + glob
    glob = glob.lstrip("/")
    out, i = "", 0
    while i < len(glob):
        if glob.startswith("**/", i):
            out, i = out + "(?:.*/)?", i + 3
        elif glob.startswith("**", i):
            out, i = out + ".*", i + 2
        elif glob[i] == "*":
            out, i = out + "[^/]*", i + 1
        elif glob[i] == "?":
            out, i = out + "[^/]", i + 1
        elif glob[i] == "{":
            end = glob.index("}", i)
            out += "(?:" + "|".join(re.escape(part) for part in glob[i + 1 : end].split(",")) + ")"
            i = end + 1
        elif glob[i] == "[":
            end = glob.index("]", i)
            out, i = out + glob[i : end + 1], end + 1
        else:
            out, i = out + re.escape(glob[i]), i + 1
    return re.compile(out + r"\Z")


def read_editorconfig(root):
    """[(regex, {property: value})] in file order."""
    sections = []
    path = root / ".editorconfig"
    if not path.exists():
        return sections
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line[0] in "#;":
            continue
        if line.startswith("[") and line.endswith("]"):
            sections.append((glob_to_regex(line[1:-1]), {}))
        elif "=" in line and sections:
            key, value = (part.strip().lower() for part in line.split("=", 1))
            sections[-1][1][key] = value
    return sections


def properties(sections, path):
    """The EditorConfig properties that apply to path ("unset" removes one)."""
    result = {}
    for pattern, values in sections:
        if pattern.match(path):
            for key, value in values.items():
                if value == "unset":
                    result.pop(key, None)
                else:
                    result[key] = value
    return result


# ---------------------------------------------------------- built-in rules --


def report_lines(problems, path, rule, message, numbers):
    for number in numbers[:REPORTED_LINES_PER_RULE]:
        problems.append(Problem(path, number, rule, message))
    if len(numbers) > REPORTED_LINES_PER_RULE:
        problems.append(
            Problem(
                path,
                numbers[REPORTED_LINES_PER_RULE],
                rule,
                "%s (%d more lines)" % (message, len(numbers) - REPORTED_LINES_PER_RULE),
            )
        )


def check_layout(path, text, props, problems):
    """The .editorconfig rules: encoding, line endings, final newline, trailing
    whitespace and tabs in indentation."""
    if props.get("charset") == "utf-8" and text.startswith("﻿"):
        problems.append(Problem(path, 1, "encoding", "starts with a byte-order mark; save as UTF-8 without one"))
    lines = text.split("\n")
    if props.get("end_of_line") == "lf":
        report_lines(
            problems,
            path,
            "line-endings",
            "CR line ending; use LF",
            [n for n, line in enumerate(lines, 1) if "\r" in line],
        )
    if props.get("insert_final_newline") == "true" and text and not text.endswith("\n"):
        problems.append(Problem(path, len(lines), "final-newline", "the last line has no newline"))
    if props.get("trim_trailing_whitespace") == "true":
        report_lines(
            problems,
            path,
            "trailing-whitespace",
            "spaces or tabs at the end of the line",
            [n for n, line in enumerate(lines, 1) if line.rstrip("\r") != line.rstrip("\r").rstrip(" \t")],
        )
    if props.get("indent_style") == "space":
        report_lines(
            problems,
            path,
            "indentation",
            "tab in the indentation; indent with spaces",
            [n for n, line in enumerate(lines, 1) if "\t" in line[: len(line) - len(line.lstrip(" \t"))]],
        )
    report_lines(
        problems,
        path,
        "conflict-marker",
        "unresolved merge conflict marker",
        [n for n, line in enumerate(lines, 1) if line.startswith(("<<<<<<< ", ">>>>>>> "))],
    )


HOME_PATH = re.compile(r"/Users/[A-Za-z0-9._-]+/|/home/[A-Za-z0-9._-]+/|[A-Za-z]:\\\\?Users\\\\?[A-Za-z0-9._-]+")


def check_private_paths(path, text, problems):
    numbers = [
        n
        for n, line in enumerate(text.split("\n"), 1)
        if any(not match.group(0).startswith(settings.HOME_PATH_ALLOWED) for match in HOME_PATH.finditer(line))
    ]
    report_lines(
        problems, path, "personal-path", "path inside a home folder; use a relative path or a placeholder", numbers
    )


def check_script_header(path, text, problems):
    """Scripts start with a comment (or a Python docstring) saying what they do."""
    lines = [line for line in text.split("\n") if not line.startswith("#!")]
    first = next((line.strip() for line in lines if line.strip()), "")
    if path.endswith(".py"):
        try:
            if ast.get_docstring(ast.parse(text)):
                return
        except SyntaxError:
            return  # reported by the syntax check
        ok = first.startswith("#") and "coding" not in first
    elif path.endswith(".ps1"):
        ok = first.startswith(("#", "<#"))
    else:
        ok = first.startswith("#")
    if not ok:
        problems.append(
            Problem(path, 1, "script-header", "start the script with a comment saying what it does and how to run it")
        )


def check_syntax(path, text, problems):
    if path.endswith((".json", ".webmanifest")):
        try:
            json.loads(text)
        except ValueError as error:
            problems.append(Problem(path, getattr(error, "lineno", 1), "json", str(error).split(":")[0]))
    elif path.endswith(".py"):
        try:
            compile(text, path, "exec", dont_inherit=True)
        except SyntaxError as error:
            problems.append(Problem(path, error.lineno, "python-syntax", error.msg))


def check_file(root, path, sections, problems):
    """All built-in rules for one file."""
    data = (root / path).read_bytes()
    for description, test in settings.FORBIDDEN:
        if test(path):
            problems.append(Problem(path, 1, "forbidden-file", "this looks like %s; never commit it" % description))
    if data.startswith(settings.FRAME_MAGIC):
        problems.append(Problem(path, 1, "forbidden-file", "a test frame; frames go only in tests/fixtures.tar.gz.gpg"))
    if not path.startswith("assets/") and len(data) > settings.MAX_BYTES_OUTSIDE_ASSETS:
        problems.append(
            Problem(
                path,
                1,
                "file-size",
                "%d bytes; files outside assets/ must stay under %d" % (len(data), settings.MAX_BYTES_OUTSIDE_ASSETS),
            )
        )
    if is_binary(path, data) or under(path, settings.THIRD_PARTY):
        return
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as error:
        problems.append(Problem(path, data[: error.start].count(b"\n") + 1, "encoding", "not valid UTF-8"))
        return
    check_layout(path, text, properties(sections, path), problems)
    check_private_paths(path, text, problems)
    if path.endswith(settings.SCRIPT_ENDINGS):
        check_script_header(path, text, problems)
    check_syntax(path, text, problems)


def check_settings(root, problems):
    """Entries in tests/lint/settings.py must still exist."""
    for entry in list(settings.GENERATED) + list(settings.THIRD_PARTY):
        if not (root / entry).exists():
            problems.append(Problem("tests/lint/settings.py", 1, "settings", "%s no longer exists; remove it" % entry))


# ------------------------------------------------------------------- tools --


def platform_key():
    system = {"Darwin": "macos", "Linux": "linux", "Windows": "windows"}.get(platform.system(), platform.system())
    machine = platform.machine().lower()
    machine = {"amd64": "x86_64", "x64": "x86_64", "aarch64": "arm64"}.get(machine, machine)
    return "%s-%s" % (system, machine)


def tool_file(name):
    """Where --install-tools puts a tool, with the version in the folder name."""
    tool = TOOLS[name]
    suffix = ".exe" if platform.system() == "Windows" else ""
    return TOOLS_FOLDER / ("%s-%s" % (name, tool["version"])) / (tool["binary"] + suffix)


def find_tool(name):
    """(path or None, note). An installed tool must be the pinned version: a
    different formatter version can lay the same code out differently."""
    installed = tool_file(name)
    if installed.exists():
        return str(installed), ""
    found = shutil.which(TOOLS[name]["binary"])
    if found:
        status, out, err = run([found, "--version"])
        if TOOLS[name]["version"] in out + err:
            return found, ""
        return None, "%s on the PATH is not version %s" % (name, TOOLS[name]["version"])
    return None, "%s is not installed" % name


def download(url):
    request = urllib.request.Request(url, headers={"User-Agent": "outbreak-tracker-lint"})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


def binary_from_download(data, url, binary):
    """The tool's executable from a .zip/.whl, .tar.gz/.tar.xz or a bare binary."""
    names = (binary, binary + ".exe")
    if url.endswith((".zip", ".whl")):
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            for member in archive.namelist():
                if member.rsplit("/", 1)[-1] in names:
                    return archive.read(member)
    elif ".tar." in url:
        with tarfile.open(fileobj=io.BytesIO(data)) as archive:
            for member in archive.getmembers():
                if member.isfile() and member.name.rsplit("/", 1)[-1] in names:
                    return archive.extractfile(member).read()
    else:
        return data
    raise SystemExit("lint: %s is not inside %s" % (binary, url))


def install_tools():
    key = platform_key()
    failures = 0
    for name, tool in TOOLS.items():
        target = tool_file(name)
        if target.exists():
            print("%s %s: already installed" % (name, tool["version"]))
            continue
        if key not in tool["downloads"]:
            print(
                "%s %s: no download for %s; install it another way (see tests/lint/tools.py)"
                % (name, tool["version"], key)
            )
            failures += 1
            continue
        url, sha256 = tool["downloads"][key]
        print("%s %s: downloading %s" % (name, tool["version"], url))
        try:
            data = download(url)
        except OSError as error:
            print("  failed: %s (on macOS with python.org Python, run its 'Install Certificates' first)" % error)
            failures += 1
            continue
        digest = hashlib.sha256(data).hexdigest()
        if digest != sha256:
            print("  refused: SHA-256 %s, expected %s" % (digest, sha256))
            failures += 1
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(binary_from_download(data, url, tool["binary"]))
        target.chmod(target.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        print("  installed %s (%d bytes downloaded)" % (target.relative_to(REPOSITORY), len(data)))
    return failures


def parse_lines(output, pattern, rule, root, problems):
    """Problems from tool output lines matching pattern (groups: path, line, message)."""
    for line in output.splitlines():
        match = re.match(pattern, line.strip())
        if match:
            path, number, message = match.group("path"), match.group("line"), match.group("message")
            problems.append(Problem(relative(root, path), int(number), rule, message.strip()))


def relative(root, path):
    """A path from a tool's output (relative to root, or absolute) as root-relative with "/"."""
    full = Path(path) if Path(path).is_absolute() else root / path
    try:
        return full.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.replace("\\", "/")


def find_luajit(root):
    """LuaJIT from the PATH, or the one the Windows build compiles."""
    built = root / "windows" / "luajit" / "src" / "luajit.exe"
    return shutil.which("luajit") or (str(built) if built.exists() else None)


def lua_syntax(root, files, problems):
    """Load (never run) every Lua file with LuaJIT, which the tracker runs on."""
    luajit = find_luajit(root)
    if not luajit or not files:
        return luajit is not None
    script = "for path in io.lines(arg[1]) do local ok, err = loadfile(path) if not ok then print(err) end end"
    with tempfile.TemporaryDirectory() as folder:
        listing, checker = Path(folder, "files.txt"), Path(folder, "check.lua")
        listing.write_text("\n".join(files) + "\n", encoding="utf-8")
        checker.write_text(script, encoding="utf-8")
        _, out, err = run([luajit, str(checker), str(listing)], cwd=root)
    parse_lines(out + err, r"(?P<path>.+?\.lua):(?P<line>\d+): (?P<message>.*)", "lua-syntax", root, problems)
    return True


# Each tool runner adds its problems and returns (exit status, output) of its
# checking command, so that a tool that fails without reporting a problem (a
# broken configuration, a crash) is reported instead of passing quietly.


def stylua(tool, root, files, fix, problems):
    if fix:
        run([tool, "--"] + files, cwd=root)
    status, out, err = run([tool, "--check", "--output-format=Summary", "--"] + files, cwd=root)
    for line in (out + err).splitlines():
        if line.strip() in files:
            problems.append(Problem(line.strip(), 1, "lua-format", "not formatted; run python3 tests/lint.py --fix"))
    return status, out + err


def selene(tool, root, files, fix, problems):
    config = root / "tests" / "lint" / "selene.toml"
    status, out, err = run(
        [tool, "--config", str(config), "--display-style=Quiet", "--no-summary", "--"] + files, cwd=root
    )
    parse_lines(out + err, r"(?P<path>.+?\.lua):(?P<line>\d+):\d+: (?P<message>.*)", "lua-check", root, problems)
    return status, out + err


def clang_format(tool, root, files, fix, problems):
    style = "--style=file:" + str(root / ".clang-format")
    if fix:
        run([tool, style, "-i"] + files, cwd=root)
    for path in files:
        status, out, err = run([tool, style, path], cwd=root)
        if status != 0:
            return status, err
        if out.encode("utf-8") != (root / path).read_bytes():
            problems.append(Problem(path, 1, "c-format", "not formatted; run python3 tests/lint.py --fix"))
    return 0, ""


def ruff(tool, root, files, fix, problems):
    config = ["--config", str(root / "ruff.toml"), "--no-cache"]
    if fix:
        run([tool, "format"] + config + files, cwd=root)
    status, out, err = run([tool, "check", "--output-format=concise"] + config + files, cwd=root)
    parse_lines(out + err, r"(?P<path>.+?\.py):(?P<line>\d+):\d+: (?P<message>.*)", "python-check", root, problems)
    format_status, format_out, format_err = run(
        [tool, "format", "--check", "--output-format=concise"] + config + files, cwd=root
    )
    for line in (format_out + format_err).splitlines():
        match = re.match(r"(?P<path>.+?\.py):\d+:\d+: unformatted", line)
        if match:
            problems.append(
                Problem(
                    relative(root, match.group("path")),
                    1,
                    "python-format",
                    "not formatted; run python3 tests/lint.py --fix",
                )
            )
    return max(status, format_status), out + err + format_out + format_err


def shellcheck(tool, root, files, fix, problems):
    status, out, err = run([tool, "--format=gcc", "--"] + files, cwd=root)
    parse_lines(out + err, r"(?P<path>.+?):(?P<line>\d+):\d+: (?P<message>.*)", "shell-check", root, problems)
    return status, out + err


def biome(tool, root, files, fix, problems):
    """Biome runs inside decky/, where its configuration (biome.jsonc) is.
    Its "info" suggestions are not shown; warnings and errors are problems."""
    decky = root / "decky"
    inside = [path[len("decky/") :] for path in files]
    options = ["--colors=off", "--diagnostic-level=warn"]
    if fix:
        run([tool, "format", "--write"] + options + inside, cwd=decky)
    status, out, err = run([tool, "ci", "--reporter=github"] + options + inside, cwd=decky)
    for line in (out + err).splitlines():
        match = re.match(r"::(?:error|warning) (?P<fields>[^:]*)::(?P<message>.*)", line)
        if match:
            fields = dict(part.split("=", 1) for part in match.group("fields").split(",") if "=" in part)
            path = fields.get("file", "")
            path = relative(root, path if Path(path).is_absolute() else str(decky / path))
            problems.append(
                Problem(
                    path,
                    int(fields.get("line", 1)),
                    "web-check",
                    "%s (%s)" % (match.group("message"), fields.get("title", "biome")),
                )
            )
    return status, out + err


def actionlint(tool, root, files, fix, problems):
    found, _ = find_tool("shellcheck")
    status, out, err = run([tool, "-no-color", "-oneline", "-shellcheck=" + (found or "")] + files, cwd=root)
    parse_lines(out + err, r"(?P<path>.+?\.ya?ml):(?P<line>\d+):\d+: (?P<message>.*)", "workflow-check", root, problems)
    return status, out + err


POWERSHELL_PARSE = r"""
param([string]$Path)
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errors) | Out-Null
foreach ($e in $errors) { "{0}: {1}" -f $e.Extent.StartLineNumber, $e.Message }
"""


def powershell_syntax(root, files, problems):
    shell = shutil.which("pwsh") or shutil.which("powershell")
    if not shell or not files:
        return shell is not None
    with tempfile.TemporaryDirectory() as folder:
        parser = Path(folder, "parse.ps1")
        parser.write_text(POWERSHELL_PARSE, encoding="utf-8")
        for path in files:
            _, out, _ = run([shell, "-NoProfile", "-NonInteractive", "-File", str(parser), str(root / path)])
            for line in out.splitlines():
                number, _, message = line.partition(": ")
                if number.strip().isdigit():
                    problems.append(Problem(path, int(number), "powershell-syntax", message))
    return True


# Which tool checks which files. Generated and third-party files are left out.
RUNNERS = [
    ("stylua", stylua, lambda path: path.endswith(".lua")),
    ("selene", selene, lambda path: path.endswith(".lua")),
    ("clang-format", clang_format, lambda path: path.endswith((".c", ".cpp", ".h"))),
    ("ruff", ruff, lambda path: path.endswith(".py")),
    ("shellcheck", shellcheck, lambda path: path.endswith(".sh")),
    ("biome", biome, lambda path: path.startswith("decky/") and path.endswith((".js", ".ts", ".tsx", ".css"))),
    ("actionlint", actionlint, lambda path: path.startswith(".github/workflows/") and path.endswith((".yml", ".yaml"))),
]


def fix_whitespace(root, path, sections):
    """--fix for the layout rules every editor can follow: line endings, final
    newline and trailing whitespace. Tabs are left for a person to change."""
    file = root / path
    data = file.read_bytes()
    if is_binary(path, data) or under(path, settings.THIRD_PARTY):
        return
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return
    props = properties(sections, path)
    if props.get("end_of_line") == "lf":
        text = text.replace("\r\n", "\n")
    if props.get("trim_trailing_whitespace") == "true":
        text = "\n".join(line.rstrip(" \t") for line in text.split("\n"))
    if props.get("insert_final_newline") == "true" and text and not text.endswith("\n"):
        text += "\n"
    if text.encode("utf-8") != data:
        file.write_bytes(text.encode("utf-8"))


# -------------------------------------------------------------------- main --


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("paths", nargs="*", help="files or folders to check (default: everything)")
    parser.add_argument("--fix", action="store_true", help="run the formatters and fix whitespace first")
    parser.add_argument("--changed", action="store_true", help="only files changed against origin/dev or dev")
    parser.add_argument("--strict", action="store_true", help="a missing tool is a problem")
    parser.add_argument("--install-tools", action="store_true", help="download the pinned tools into .lint-tools/")
    parser.add_argument("--root", type=Path, default=REPOSITORY, help=argparse.SUPPRESS)  # for tests/unit/check-lint.py
    args = parser.parse_args()
    if args.install_tools:
        sys.exit(1 if install_tools() else 0)

    root = args.root.resolve()
    paths = [relative(root, str(Path(p).resolve())) for p in args.paths]
    files = list_files(root, paths, args.changed)
    sections = read_editorconfig(root)

    if args.fix:
        for path in files:
            fix_whitespace(root, path, sections)

    problems, missing = [], []
    for path in files:
        check_file(root, path, sections, problems)
    if not paths and not args.changed:
        check_settings(root, problems)

    # Generated and third-party files get the layout and file rules above, but
    # no formatter or code checks.
    checkable = [path for path in files if path not in settings.GENERATED and not under(path, settings.THIRD_PARTY)]
    if not lua_syntax(root, [p for p in files if p.endswith(".lua")], problems):
        missing.append("luajit is not installed, so Lua syntax was not checked")
    ps1 = [p for p in checkable if p.endswith(".ps1")]
    if ps1 and not powershell_syntax(root, ps1, problems):
        missing.append("PowerShell is not installed, so .ps1 syntax was not checked")
    for name, runner, wanted in RUNNERS:
        selected = [path for path in checkable if wanted(path)]
        if not selected:
            continue
        tool, note = find_tool(name)
        if tool is None:
            missing.append(note + "; run python3 tests/lint.py --install-tools")
            continue
        before = len(problems)
        status, output = runner(tool, root, selected, args.fix, problems)
        if status != 0 and len(problems) == before:
            last = next((line for line in reversed(output.strip().splitlines()) if line.strip()), "no output")
            problems.append(
                Problem(
                    ".", 1, name, "%s failed (exit status %d) without naming a file: %s" % (name, status, last.strip())
                )
            )

    problems.sort(key=lambda p: (p.path, p.line or 0, p.rule))
    annotate = os.environ.get("GITHUB_ACTIONS") == "true"
    for problem in problems:
        print(problem)
        if annotate:
            print(
                "::error file=%s,line=%s,title=%s::%s"
                % (
                    problem.path,
                    problem.line or 1,
                    problem.rule,
                    problem.message.replace("%", "%25").replace("\n", "%0A"),
                )
            )
    for note in missing:
        print(("ERROR: " if args.strict else "skipped: ") + note)
    failed = bool(problems) or (args.strict and bool(missing))
    if problems:
        print(
            "%d problem(s) in %d file(s) of %d checked." % (len(problems), len({p.path for p in problems}), len(files))
        )
    else:
        print("No problems in %d file(s)%s." % (len(files), "" if not missing else " (some checks skipped)"))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
