#!/usr/bin/env python3
"""Source-contract checks for the native plugin layout.

These inspect plugin files. They are not Omarchy/Quickshell runtime evidence.
"""

from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "manifest.json"
PANEL = ROOT / "Panel.qml"
MODEL = ROOT / "Model.js"
STORE = ROOT / "bin" / "breadcrumb-store"


class TestPluginContract(unittest.TestCase):
    def test_manifest_matches_supported_omarchy_plugin_layout(self) -> None:
        self.assertTrue(MANIFEST.is_file(), "manifest.json must live at the plugin root")
        data = json.loads(MANIFEST.read_text(encoding="utf-8"))
        self.assertEqual(data["schemaVersion"], 1)
        self.assertEqual(data["id"], "tbassss.breadcrumb")
        self.assertFalse(data["id"].startswith("omarchy."))
        self.assertEqual(data["kinds"], ["bar-widget"])
        self.assertEqual(data["entryPoints"]["barWidget"], "Panel.qml")
        self.assertEqual(data["barWidget"]["defaultSection"], "right")
        self.assertTrue((ROOT / data["entryPoints"]["barWidget"]).is_file())
        self.assertTrue(STORE.is_file())
        self.assertFalse(STORE.is_symlink())
        self.assertTrue(PANEL.is_file())
        self.assertTrue(MODEL.is_file())

    def test_panel_uses_supported_shell_and_safe_subprocess(self) -> None:
        qml = PANEL.read_text(encoding="utf-8")
        self.assertIn("import qs.Ui", qml)
        self.assertIn("import qs.Commons", qml)
        self.assertIn("import Quickshell.Io", qml)
        self.assertIn("Panel {", qml)
        self.assertIn("KeyboardPanel", qml)
        self.assertIn("BarIconButton", qml)
        self.assertIn('"/usr/bin/python3"', qml)
        self.assertIn("JSON.stringify", qml)
        self.assertNotIn("bash", qml)
        self.assertNotIn("shell interpolation", qml)
        self.assertIn("Quickshell.execDetached(body.open_argv)", qml)
        self.assertNotIn("io.github.tyrichards.tray", qml)
        self.assertNotIn("omarchy plugin enable", qml)

    def test_panel_has_compact_expanded_and_honest_states(self) -> None:
        qml = PANEL.read_text(encoding="utf-8")
        self.assertIn("Expand", qml)
        self.assertIn("Collapse", qml)
        self.assertIn("Loading checkpoint…", qml)
        self.assertIn("No checkpoint saved yet", qml)
        self.assertIn("lastError", qml)
        self.assertIn("Save checkpoint", qml)
        self.assertIn("Create activity", qml)
        self.assertNotIn("History", qml)
        self.assertNotIn("activityPicker", qml)
        self.assertGreaterEqual(qml.count("textFormat: Text.PlainText"), 8)

    def test_store_is_ui_seam_not_public_agent_cli(self) -> None:
        store = STORE.read_text(encoding="utf-8")
        self.assertIn("Not a public agent command interface", store)
        self.assertIn("PRAGMA journal_mode = DELETE", store)
        self.assertIn("PRAGMA synchronous = FULL", store)
        self.assertIn("expected_revision", store)


if __name__ == "__main__":
    unittest.main()
