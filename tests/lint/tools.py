"""Pinned versions of the tools tests/lint.py runs, with their downloads.

Purpose: the one place that says which tool versions the lint uses, so every
  system (and the GitHub checks) formats and checks code the same way. Each
  version was released at least two weeks before it was pinned.
Location/language: tests/lint/tools.py; Python 3 data, imported by tests/lint.py.
Contents: per tool its version, the binary's name inside the download, and per
  platform the download URL with its SHA-256 (the digest the project publishes
  with the release, or PyPI's for the clang-format wheel).
Platforms: macos-arm64, macos-x86_64, linux-x86_64, linux-arm64, windows-x86_64.
  selene publishes one macOS build, for Apple silicon, and no Linux arm64
  build; on an Intel Mac or Linux arm64, "cargo install selene --version
  <version> --locked" works instead.
Updating a tool: change its version, URLs and digests together, run
  "python3 tests/lint.py --install-tools" and "python3 tests/lint.py --fix", and
  commit the formatting changes on their own.
"""

TOOLS = {
    "stylua": {
        # Lua formatter; https://github.com/JohnnyMorganz/StyLua; released 2026-10-10.
        "version": "2.6.0",
        "binary": "stylua",
        "downloads": {
            "macos-arm64": (
                "https://github.com/JohnnyMorganz/StyLua/releases/download/v2.6.0/stylua-macos-aarch64.zip",
                "dab9b66d340ca5ffc8225211f1dcf89b84783e09b8cbec8c518497eba81f3c42",
            ),
            "macos-x86_64": (
                "https://github.com/JohnnyMorganz/StyLua/releases/download/v2.6.0/stylua-macos-x86_64.zip",
                "90779aa873837b2dff8eb3361bd27950303914c24265a59cae0a0d0629d71585",
            ),
            "linux-x86_64": (
                "https://github.com/JohnnyMorganz/StyLua/releases/download/v2.6.0/stylua-linux-x86_64.zip",
                "a485f72bbfa22e4642e77a84b5edc2611a5cab7477b34e2e709dd8f78e919895",
            ),
            "linux-arm64": (
                "https://github.com/JohnnyMorganz/StyLua/releases/download/v2.6.0/stylua-linux-aarch64.zip",
                "8e67539e5fdf7a81cd03cf592b0df18d3bb96ee17a5ea5d9bf67b86387b903b0",
            ),
            "windows-x86_64": (
                "https://github.com/JohnnyMorganz/StyLua/releases/download/v2.6.0/stylua-windows-x86_64.zip",
                "fd13b4014e3b779c244bbc03f2c282e357f15bc526de6a6fa5ecbc447538313c",
            ),
        },
    },
    "selene": {
        # Lua checks; https://github.com/Kampfkarren/selene; released 2026-10-01.
        "version": "0.32.0",
        "binary": "selene",
        "downloads": {
            "macos-arm64": (
                "https://github.com/Kampfkarren/selene/releases/download/0.32.0/selene-0.32.0-macos.zip",
                "d8aa4701530a81334836f9c5e3bf38b91f633d9ad88f4d15cf29f63fe8589dc0",
            ),
            "linux-x86_64": (
                "https://github.com/Kampfkarren/selene/releases/download/0.32.0/selene-0.32.0-linux.zip",
                "d3773393578580074386e69337d35b7acddfbaa9fc38964c07fa3e28436ade9b",
            ),
            "windows-x86_64": (
                "https://github.com/Kampfkarren/selene/releases/download/0.32.0/selene-0.32.0-windows.zip",
                "c8b693de81d0ddc11490d8e1170dd98d775c2b21431144bd8286f738ef416109",
            ),
        },
    },
    "clang-format": {
        # C and C++ formatter (from the PyPI wheel); https://pypi.org/project/clang-format/; released 2026-10-06.
        "version": "23.1.3",
        "binary": "clang-format",
        "downloads": {
            "macos-arm64": (
                "https://files.pythonhosted.org/packages/47/a5/2007b7a7a53dfe417e66d0a6b38b2f87f16391bfe6fe522d436d1e50be1c/clang_format-23.1.3-py2.py3-none-macosx_11_0_arm64.whl",
                "79f53ac55434af6dda88eb90eeb65d903ff920c910f78041de41e3ca666dfba5",
            ),
            "macos-x86_64": (
                "https://files.pythonhosted.org/packages/05/0f/a1813ede1e149e700ee810baf22dd9c863ca0bd719d73f86e8c10b67a6bb/clang_format-23.1.3-py2.py3-none-macosx_10_9_x86_64.whl",
                "0b8e86cc5a870ca42989bd1ccfe5220fbab96e386922d0a8f0ca350db30593df",
            ),
            "linux-x86_64": (
                "https://files.pythonhosted.org/packages/11/d1/658d3da4dcbca98620956868c7cf6f4ba19fccecbdfc30cc055e19c9d4a7/clang_format-23.1.3-py2.py3-none-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl",
                "58bf1804216501669832a39f2415e14284337438a062ff564729792adec664ac",
            ),
            "linux-arm64": (
                "https://files.pythonhosted.org/packages/1d/00/a0f99e24dc4892fb120e82fa9cf6e8fcb92714181ffd1165ab7eaf5ba1fd/clang_format-23.1.3-py2.py3-none-manylinux_2_26_aarch64.manylinux_2_28_aarch64.whl",
                "072113527b49a9c0ab9058006d9fe20e583823e6482608a34e1883dd2c49ae7d",
            ),
            "windows-x86_64": (
                "https://files.pythonhosted.org/packages/23/a6/90148f91544e3c056e78c514f0e764c1b44d50a33344c83fd03011ea97c8/clang_format-23.1.3-py2.py3-none-win_amd64.whl",
                "6c2b74c3a3e942ec172d768e7b945f8e136db05a7b735d49ecfc69bda97643ad",
            ),
        },
    },
    "ruff": {
        # Python checks and formatter; https://github.com/astral-sh/ruff; released 2026-10-27.
        "version": "0.17.3",
        "binary": "ruff",
        "downloads": {
            "macos-arm64": (
                "https://github.com/astral-sh/ruff/releases/download/0.17.3/ruff-aarch64-apple-darwin.tar.gz",
                "118f7121aa838785672bf612487f755a89108bb5f44e0f3df96c5967a72614f9",
            ),
            "macos-x86_64": (
                "https://github.com/astral-sh/ruff/releases/download/0.17.3/ruff-x86_64-apple-darwin.tar.gz",
                "17f95b1bee24d70de62ffe5beec7f71bb541c7e3d147a1c3d84f7cd6525f6fdf",
            ),
            "linux-x86_64": (
                "https://github.com/astral-sh/ruff/releases/download/0.17.3/ruff-x86_64-unknown-linux-gnu.tar.gz",
                "2b0890f5a55900af741f133918c2656919bbf18c2ab7741b4ca8403a90e647a9",
            ),
            "linux-arm64": (
                "https://github.com/astral-sh/ruff/releases/download/0.17.3/ruff-aarch64-unknown-linux-gnu.tar.gz",
                "3f4639152c0e42bb5938e6c23d53d527a38f3133e000102934518f90529fa299",
            ),
            "windows-x86_64": (
                "https://github.com/astral-sh/ruff/releases/download/0.17.3/ruff-x86_64-pc-windows-msvc.zip",
                "a84d9ac74af8ef5bac84a1888a1634df18e6e985e2f930d35c052beacd00e813",
            ),
        },
    },
    "shellcheck": {
        # shell script checks; https://github.com/koalaman/shellcheck; released 2025-08-04.
        "version": "0.11.0",
        "binary": "shellcheck",
        "downloads": {
            "macos-arm64": (
                "https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.darwin.aarch64.tar.xz",
                "56affdd8de5527894dca6dc3d7e0a99a873b0f004d7aabc30ae407d3f48b0a79",
            ),
            "macos-x86_64": (
                "https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.darwin.x86_64.tar.xz",
                "3c89db4edcab7cf1c27bff178882e0f6f27f7afdf54e859fa041fca10febe4c6",
            ),
            "linux-x86_64": (
                "https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.linux.x86_64.tar.xz",
                "8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198",
            ),
            "linux-arm64": (
                "https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.linux.aarch64.tar.xz",
                "12b331c1d2db6b9eb13cfca64306b1b157a86eb69db83023e261eaa7e7c14588",
            ),
            "windows-x86_64": (
                "https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.zip",
                "8a4e35ab0b331c85d73567b12f2a444df187f483e5079ceffa6bda1faa2e740e",
            ),
        },
    },
    "biome": {
        # JavaScript, TypeScript and CSS checks and formatter; https://github.com/biomejs/biome; released 2026-10-28.
        "version": "2.6.4",
        "binary": "biome",
        "downloads": {
            "macos-arm64": (
                "https://github.com/biomejs/biome/releases/download/%40biomejs/biome%402.6.4/biome-darwin-arm64",
                "1d1edbda5ee33475144c56ba452dbda28e1b061088fb875102a2df6cda84c9b4",
            ),
            "macos-x86_64": (
                "https://github.com/biomejs/biome/releases/download/%40biomejs/biome%402.6.4/biome-darwin-x64",
                "eea768e85adf17a1680b0333c4305dd42df3f3bf73e1e1578eb04d4a365cb899",
            ),
            "linux-x86_64": (
                "https://github.com/biomejs/biome/releases/download/%40biomejs/biome%402.6.4/biome-linux-x64",
                "eb9afd5af3c04bd242be6db39fb812a025b42469af8c6a621535036dbd9b0c63",
            ),
            "linux-arm64": (
                "https://github.com/biomejs/biome/releases/download/%40biomejs/biome%402.6.4/biome-linux-arm64",
                "11a2e6770b3d7c8ce8cbec4652a516584b179dc30febecce0ca852d87074bee8",
            ),
            "windows-x86_64": (
                "https://github.com/biomejs/biome/releases/download/%40biomejs/biome%402.6.4/biome-win32-x64.exe",
                "ed7aa62b0f22ac4258d3d8668e0af8d53085168d421a8d4ec708040c5e275c0c",
            ),
        },
    },
    "actionlint": {
        # GitHub workflow checks; https://github.com/rhysd/actionlint; released 2026-03-30.
        "version": "1.7.12",
        "binary": "actionlint",
        "downloads": {
            "macos-arm64": (
                "https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_darwin_arm64.tar.gz",
                "aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f",
            ),
            "macos-x86_64": (
                "https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_darwin_amd64.tar.gz",
                "5b44c3bc2255115c9b69e30efc0fecdf498fdb63c5d58e17084fd5f16324c644",
            ),
            "linux-x86_64": (
                "https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_amd64.tar.gz",
                "8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8",
            ),
            "linux-arm64": (
                "https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_arm64.tar.gz",
                "325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6",
            ),
            "windows-x86_64": (
                "https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_windows_amd64.zip",
                "6e7241b51e6817ea6a047693d8e6fed13b31819c9a0dd6c5a726e1592d22f6e9",
            ),
        },
    },
}
