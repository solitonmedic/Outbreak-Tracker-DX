"""Purpose: reusable Decky backend providing setup status for the foundation plugin.
Location/runtime: decky/main.py, Python provided by Decky Loader (no pip packages).
Inputs: packaged build-info.json, package.json, DECKY_USER_HOME, PCSX2 INI settings.
Outputs: get_status() JSON-compatible values; lifecycle messages in Decky's plugin log.
Safety: reads only setup metadata and PINE configuration; never connects to PINE,
records memory, changes emulator settings, or reads recordings/workbooks.
Run: install the ZIP made by `python3 decky/scripts/deck.py build` from repo-merged/.
Check: open Outbreak Tracker in Decky; Refresh shows version, commit and PINE setting.
"""

import configparser
import json
from pathlib import Path

import decky


class Plugin:
    async def get_status(self) -> dict:
        plugin_dir = Path(__file__).resolve().parent
        package = json.loads((plugin_dir / "package.json").read_text())
        metadata_path = plugin_dir / "build-info.json"
        metadata = json.loads(metadata_path.read_text()) if metadata_path.exists() else {}
        user_home = Path(decky.DECKY_USER_HOME)
        pine_enabled = None
        pine_slot = None
        settings = configparser.ConfigParser(strict=False, interpolation=None)
        try:
            settings.read(user_home / ".config/PCSX2/inis/PCSX2.ini")
            for section in settings.sections():
                if settings.has_option(section, "EnablePINE"):
                    pine_enabled = settings.getboolean(section, "EnablePINE")
                    pine_slot = settings.getint(section, "PINESlot", fallback=28011)
                    break
        except (OSError, ValueError, configparser.Error):
            pine_enabled = None
            pine_slot = None

        return {
            "version": package["version"],
            "sourceCommit": metadata.get("sourceCommit", "unbuilt"),
            "trackerState": "pending",
            "pcsx2Installed": (user_home / "Applications/pcsx2-Qt.AppImage").is_file(),
            "pineEnabled": pine_enabled,
            "pineSlot": pine_slot,
            "message": "Setup foundation is ready. Live tracker data and the phone view are pending.",
        }

    async def _main(self):
        decky.logger.info("Outbreak Tracker foundation loaded")

    async def _unload(self):
        decky.logger.info("Outbreak Tracker foundation unloaded")
