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
        self.assertIn("History", qml)
        self.assertIn("activityPicker", qml)
        self.assertIn("Save or discard this edit before switching activities.", qml)
        self.assertIn("create-activity", qml)
        self.assertIn("archive-activity", qml)
        self.assertIn("Show archived", qml)
        self.assertGreaterEqual(qml.count("textFormat: Text.PlainText"), 8)

    def test_store_is_ui_seam_not_public_agent_cli(self) -> None:
        store = STORE.read_text(encoding="utf-8")
        self.assertIn("Not a public agent command interface", store)
        self.assertIn("PRAGMA journal_mode = DELETE", store)
        self.assertIn("PRAGMA synchronous = FULL", store)
        self.assertIn("expected_revision", store)

    def test_editor_dirty_tracks_user_edits_not_construction_text_changed(self) -> None:
        """Source contract only. Native recreate evidence is tests/native/."""
        qml = PANEL.read_text(encoding="utf-8")
        self.assertNotRegex(
            qml,
            r"onTextChanged:\s*\{[^}]*root\.dirty\s*=\s*true",
            "onTextChanged during TextField/TextArea construction must not mark a user draft",
        )
        self.assertGreaterEqual(qml.count("onTextEdited:"), 4)
        self.assertIn("onTextEdited: root.dirty = true", qml)
        self.assertNotRegex(
            qml,
            r'pendingAction === "get"\)\s*\n\s*root\.dirty = false',
        )
        self.assertNotIn('if (root.pendingAction === "get")\n        root.dirty = false', qml)
        get_clears = 'if (root.pendingAction === "get")\n      root.dirty = false'
        self.assertNotIn(get_clears, qml)

    def test_native_harness_asserts_recreate_editor_and_draft_preserve(self) -> None:
        """The native qs assertion must exist in-repo. This is not a substitute for running it."""
        harness = ROOT / "tests" / "native" / "harness" / "shell.qml"
        runner = ROOT / "tests" / "native" / "run-isolated.sh"
        self.assertTrue(harness.is_file())
        self.assertTrue(runner.is_file())
        qml = harness.read_text(encoding="utf-8")
        self.assertIn("editor readback summary mismatch", qml)
        self.assertIn("editSummary !== expectedSummary", qml)
        self.assertIn("fresh Panel marked dirty before any user edit", qml)
        self.assertIn("refresh clobbered genuine in-progress summary draft", qml)
        self.assertIn("panelLoader.active = false", qml)
        self.assertIn("Unsaved lantern draft", qml)
        self.assertIn("createActivity()", qml)
        self.assertIn("switchActivity(", qml)
        self.assertIn("archiveActivity(", qml)
        self.assertIn("restoreCheckpoint(", qml)
        self.assertIn("App Project", qml)
        self.assertIn("historyEntries", qml)
        self.assertIn("activity id B mismatch after recreate", qml)
        self.assertIn("archived activity was not readable", qml)
        self.assertIn("restore did not append a new revision", qml)


if __name__ == "__main__":
    unittest.main()
