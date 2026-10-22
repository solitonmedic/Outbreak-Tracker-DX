"""Purpose: reusable Decky backend owning the live reader and LAN phone service.
Location/runtime: decky/main.py, Python provided by Decky Loader (no pip packages).
Inputs: packaged build-info.json, package.json, DECKY_USER_HOME, PCSX2 INI settings.
Outputs: get_status() including a private phone link; lifecycle logs, LAN port 8384.
Safety: live PINE reads only; no recording, game/settings writes or saved recordings.
Run: install the ZIP made by `python3 decky/scripts/deck.py build` from repo-merged/.
Check: open Outbreak Tracker in Decky; Refresh shows version, commit and PINE setting.
"""

import asyncio
import configparser
import json
from pathlib import Path
import sys

import decky

sys.path.insert(0, str(Path(__file__).resolve().parent))
from tracker_service import TrackerService


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

        service = getattr(self, "service", None)
        web = service.status() if service else {"running": False, "phoneUrl": None, "connection": "stopped", "lastError": None}
        return {
            "version": package["version"],
            "sourceCommit": metadata.get("sourceCommit", "unbuilt"),
            "trackerState": web["connection"],
            "pcsx2Installed": (user_home / "Applications/pcsx2-Qt.AppImage").is_file(),
            "pineEnabled": pine_enabled,
            "pineSlot": pine_slot,
            "message": getattr(self, "startup_error", None) or web.get("lastError") or "Scan the code or open the private link on a device on your network.",
            **web,
        }

    async def set_running(self, running: bool):
        if not isinstance(running, bool):
            raise ValueError("running must be a boolean")
        if running:
            await asyncio.to_thread(self.service.start)
        else:
            await asyncio.to_thread(self.service.stop)
        self.startup_error = None
        return await self.get_status()

    async def _main(self):
        self.service = TrackerService(Path(__file__).resolve().parent)
        self.startup_error = None
        try:
            await asyncio.to_thread(self.service.start)
            decky.logger.info("Outbreak Tracker LAN service started on port 8384")
        except OSError:
            self.startup_error = "Unable to start phone view. Port 8384 may already be in use."
            decky.logger.error(self.startup_error)

    async def _unload(self):
        if getattr(self, "service", None):
            await asyncio.to_thread(self.service.stop)
        decky.logger.info("Outbreak Tracker reader and LAN service stopped")
