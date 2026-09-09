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
COMMAND = ROOT / "bin" / "breadcrumb"
COMMAND_DOC = ROOT / "docs" / "COMMAND.md"


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
        self.assertTrue(COMMAND.is_file())
        self.assertFalse(COMMAND.is_symlink())
        self.assertTrue(PANEL.is_file())
        self.assertTrue(MODEL.is_file())
        self.assertTrue(COMMAND_DOC.is_file())

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
        self.assertIn("function launchOpenArgv(", qml)
        self.assertNotIn("Quickshell.execDetached", qml)
        self.assertIn("id: openProc", qml)
        self.assertIn("openProc.command", qml)
        self.assertIn("BREADCRUMB_NO_OPEN", qml)
        self.assertIn("BREADCRUMB_OPEN_LAUNCHER", qml)
        self.assertIn("Could not open that link.", qml)
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
        self.assertIn("Unsaved draft", qml)
        self.assertIn("create-activity", qml)
        self.assertIn("archive-activity", qml)
        self.assertIn("Show archived", qml)
        self.assertGreaterEqual(qml.count("textFormat: Text.PlainText"), 8)
        self.assertIn("maximumLineCount", qml)
        self.assertIn("Stale-report", qml)
        self.assertIn("Reported author", qml)
        self.assertIn("Color.muted", qml)
        self.assertIn("focusable: (!root.busy)", qml)
        self.assertNotIn("enabled:", qml)
        self.assertIn('objectName: "compactSummary"', qml)
        self.assertIn('objectName: "expandButton"', qml)
        self.assertIn('objectName: "breadcrumbPanel"', qml)
        self.assertIn('objectName: "keyCatcher"', qml)
        self.assertIn('objectName: "panelScroller"', qml)
        self.assertIn("root.narrow", qml)
        self.assertIn("activityScroller", qml)
        self.assertIn("lastOpenArgv", qml)
        self.assertIn("catcherBlocked", qml)
        self.assertIn("popupOpen", qml)
        self.assertIn("panel.fittedContentHeight(column.implicitHeight, Style.space(520))", qml)
        self.assertIn("revealItem", qml)
        self.assertIn("Model.formatSavedAt", qml)
        expand_idx = qml.index("objectName: \"expandButton\"")
        expand_chunk = qml[expand_idx : expand_idx + 500]
        self.assertIn("focusable: (!root.busy)", expand_chunk)
        self.assertNotIn("focusable: true", expand_chunk)
        catcher_idx = qml.index("id: keyCatcher")
        catcher_chunk = qml[catcher_idx : catcher_idx + 900]
        self.assertIn("blocked: root.catcherBlocked", catcher_chunk)
        self.assertNotIn("blocked: contextArea.activeFocus", catcher_chunk)
        self.assertIn("onActivateRequested", catcher_chunk)
        self.assertIn("onMoveRequested", catcher_chunk)

    def test_store_is_ui_seam_not_public_agent_cli(self) -> None:
        store = STORE.read_text(encoding="utf-8")
        self.assertIn("Not a public agent command interface", store)
        self.assertIn("PRAGMA journal_mode = DELETE", store)
        self.assertIn("PRAGMA synchronous = FULL", store)
        self.assertIn("expected_revision", store)
        self.assertIn("expected_draft_revision", store)
        self.assertIn("save-draft", store)
        self.assertIn("discard-draft", store)
        self.assertIn("cmd_head", store)
        command = COMMAND.read_text(encoding="utf-8")
        self.assertIn("breadcrumb.command.v1", command)
        self.assertIn("MAX_STDIN_BYTES = 65536", command)
        self.assertIn("FORBIDDEN_KEYS", command)
        self.assertIn("consume_draft_revision", command)
        self.assertNotIn("cmd_save_draft", command)
        self.assertNotIn("cmd_discard_draft", command)
        doc = COMMAND_DOC.read_text(encoding="utf-8")
        self.assertIn("expected_revision", doc)
        self.assertIn("stdin JSON", doc)
        self.assertIn("ssh -o BatchMode=yes tbasss@the-cave", doc)
        self.assertIn("not delivered", doc)
        self.assertIn("installation gate", doc)

    def test_editor_dirty_tracks_user_edits_not_construction_text_changed(self) -> None:
        """Source contract only. Native recreate evidence is tests/native/."""
        qml = PANEL.read_text(encoding="utf-8")
        self.assertNotRegex(
            qml,
            r"onTextChanged:\s*\{[^}]*root\.dirty\s*=\s*true",
            "onTextChanged during TextField/TextArea construction must not mark a user draft",
        )
        self.assertGreaterEqual(qml.count("onTextEdited:"), 4)
        self.assertIn("onTextEdited: root.markUserEdit()", qml)
        self.assertNotIn("onTextEdited: root.dirty = true", qml)
        self.assertNotRegex(
            qml,
            r'pendingAction === "get"\)\s*\n\s*root\.dirty = false',
        )
        self.assertNotIn('if (root.pendingAction === "get")\n        root.dirty = false', qml)
        get_clears = 'if (root.pendingAction === "get")\\n      root.dirty = false'
        self.assertNotIn(get_clears, qml)

    def test_create_activity_persists_draft_before_create(self) -> None:
        qml = PANEL.read_text(encoding="utf-8")
        idx = qml.index("function createActivity()")
        chunk = qml[idx : idx + 400]
        self.assertIn("pendingAutosave", chunk)
        self.assertIn("saveDraft()", chunk)
        self.assertIn("actuallyCreate()", qml)
        self.assertIn('runStore("create-activity"', qml)

    def test_compact_picker_resyncs_to_authoritative_activity(self) -> None:
        qml = PANEL.read_text(encoding="utf-8")
        self.assertIn("function syncActivityPicker()", qml)
        self.assertIn("activityPicker.value =", qml)
        self.assertIn("syncActivityPicker()", qml)

    def test_draft_autosave_and_conflict_source_contracts(self) -> None:
        qml = PANEL.read_text(encoding="utf-8")
        self.assertIn('runStore("save-draft"', qml)
        self.assertIn('runStore("discard-draft"', qml)
        self.assertIn("consume_draft_revision", qml)
        self.assertIn("Unsaved draft", qml)
        self.assertIn("Saving draft…", qml)
        self.assertIn("Draft saved", qml)
        self.assertIn("hydrating", qml)
        self.assertIn("function markUserEdit()", qml)
        self.assertIn("function saveDraft()", qml)
        self.assertIn("conflictPrompt", qml)
        self.assertIn("A newer checkpoint was saved", qml)
        self.assertIn("Save draft as checkpoint", qml)
        self.assertIn("Load published", qml)
        self.assertIn("Keep editing", qml)
        self.assertIn("Discard draft", qml)
        self.assertIn("onTextEdited: root.markUserEdit()", qml)
        self.assertNotIn("onTextEdited: root.dirty = true", qml)
        save_idx = qml.index("function saveCheckpoint()")
        save_chunk = qml[save_idx : save_idx + 900]
        self.assertIn("draftBaseRevision", save_chunk)
        self.assertIn("consume_draft_revision", save_chunk)
        switch_idx = qml.index("function switchActivity(")
        switch_chunk = qml[switch_idx : switch_idx + 800]
        self.assertIn("needsDraftFlush()", switch_chunk)
        self.assertIn("saveDraft()", switch_chunk)
        # Honest ack: Draft saved is not the in-flight label.
        self.assertIn('draftStatus === "saved"', qml)
        self.assertIn('draftStatus = "saving"', qml)

    def test_ordinary_save_cas_acknowledged_draft_base_not_refreshed_revision(self) -> None:
        qml = PANEL.read_text(encoding="utf-8")
        save_idx = qml.index("function saveCheckpoint()")
        resolve_idx = qml.index("function resolveConflictSave()")
        save_chunk = qml[save_idx:resolve_idx]
        self.assertIn("draftBaseRevision", save_chunk)
        self.assertNotIn("expected_revision: root.revision", save_chunk)
        resolve_chunk = qml[resolve_idx : resolve_idx + 500]
        self.assertIn("observedRevision", resolve_chunk)

    def test_scheduler_identities_and_no_lossy_queue(self) -> None:
        qml = PANEL.read_text(encoding="utf-8")
        self.assertIn("editSequence", qml)
        self.assertIn("function enqueueOp(", qml)
        self.assertIn("function pumpQueue(", qml)
        self.assertIn("inFlight", qml)
        self.assertNotIn('if (action === "save-draft" || root.queuedAction === "")', qml)
        handler_idx = qml.index("function handleStoreResult(")
        handler = qml[handler_idx:]
        save_draft_idx = handler.index('action === "save-draft"')
        next_action = handler.find('action === "', save_draft_idx + 10)
        save_draft_handler = handler[save_draft_idx:next_action if next_action > 0 else save_draft_idx + 1800]
        self.assertNotIn("discard-draft", save_draft_handler)
        discard_idx = handler.index('action === "discard-draft"')
        discard_handler = handler[discard_idx : discard_idx + 900]
        self.assertIn("editSequence", discard_handler)

    def test_native_harness_asserts_recreate_editor_and_draft_preserve(self) -> None:
        """The native qs assertion must exist in-repo. This is not a substitute for running it."""
        harness = ROOT / "tests" / "native" / "harness" / "shell.qml"
        runner = ROOT / "tests" / "native" / "run-isolated.sh"
        self.assertTrue(harness.is_file())
        self.assertTrue(runner.is_file())
        qml = harness.read_text(encoding="utf-8")
        self.assertIn("editor readback summary mismatch", qml)
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
        self.assertIn("saveDraft()", qml)
        self.assertIn("durable draft missing after recreate", qml)
        self.assertIn("compact showed draft text instead of published checkpoint", qml)
        self.assertIn("compact missing unsaved draft indicator", qml)
        self.assertIn("conflictPrompt", qml)
        self.assertIn("recreate old-base save did not conflict", qml)
        self.assertIn("publish", qml)
        dropdown = (ROOT / "tests" / "native" / "harness" / "qs" / "Ui" / "Dropdown.qml").read_text(encoding="utf-8")
        self.assertIn("function selectCurrent(", dropdown)
        self.assertNotIn("function selectCurrent(v)", dropdown)
        self.assertIn("simulatePickerSelect(", qml)
        button = (ROOT / "tests" / "native" / "harness" / "qs" / "Ui" / "Button.qml").read_text(encoding="utf-8")
        self.assertNotIn("property bool enabled", button)
        self.assertIn("property bool focusable", button)
        runner = ROOT / "tests" / "native" / "run-isolated.sh"
        runner_text = runner.read_text(encoding="utf-8")
        self.assertIn("OMARCHY_SHELL", runner_text)
        self.assertIn("BREADCRUMB_NO_OPEN", runner_text)
        self.assertIn("packaged", runner_text.lower())
        self.assertIn("picker desync after completed switch", qml)
        self.assertIn("picker desync after later activity change", qml)
        self.assertIn("create while draft discarded A's durable draft", qml)
        self.assertIn("recreate old-base save did not conflict", qml)
        self.assertIn("keep-editing retry overwrote publication", qml)
        self.assertIn("overlap-autosave-nav", qml)
        self.assertIn("explicit save behind autosave was dropped", qml)
        self.assertIn("obsolete discard clobbered editor", qml)
        self.assertIn("open-panel in-memory draft v2", qml)
        self.assertIn("open-panel refresh missed public publish", qml)
        self.assertIn("open-panel refresh clobbered in-memory draft", qml)
        self.assertIn("closed-panel reopen missed public publish", qml)
        self.assertIn("publishPublic(", qml)
        self.assertIn("commandPath", qml)
        self.assertIn("grabToImage", qml)
        self.assertIn("keyClick", qml)
        self.assertIn("first-use default was not compact", qml)
        self.assertIn("remembered view was not expanded", qml)
        self.assertIn("compact glance grew unbounded", qml)
        self.assertIn("missing-file error was not visible", qml)
        self.assertIn("keyboard expand did not toggle view", qml)
        self.assertIn("screenshot-compact", qml)
        self.assertIn("keyCatcher did not take focus", qml)
        self.assertNotIn("expandBtn.forceActiveFocus()", qml)
        self.assertIn("catcher Return did not expand", qml)
        self.assertIn("busy Expand appeared actionable", qml)
        self.assertIn("capped panel still inflated", qml)
        self.assertIn("panel scroller missing", qml)
        self.assertIn("could not scroll main column", qml)
        self.assertIn("nonzero fake launch had no visible error", qml)
        self.assertIn("start-failure launch had no visible error", qml)
        self.assertIn("successful fake launch showed error", qml)
        self.assertIn("BREADCRUMB_FAKE_OPEN_OK", qml)
        keyboard = ROOT / "tests" / "native" / "harness" / "qs" / "Ui" / "KeyboardPanel.qml"
        kp = keyboard.read_text(encoding="utf-8")
        self.assertIn("defaultHeightCap", kp)
        dropdown = (ROOT / "tests" / "native" / "harness" / "qs" / "Ui" / "Dropdown.qml").read_text(encoding="utf-8")
        self.assertIn("popupOpen", dropdown)

    def test_panel_probes_external_changes_without_clobber(self) -> None:
        qml = PANEL.read_text(encoding="utf-8")
        self.assertIn("commandPath", qml)
        self.assertIn("changeProbe", qml)
        self.assertIn("probeProc", qml)
        self.assertIn('"head"', qml)
        self.assertIn("noteExternalPublication", qml)
        self.assertIn("draftBaseRevision", qml)
        self.assertNotIn("consume_draft_revision", qml.split("function sendOp")[0])


if __name__ == "__main__":
    unittest.main()
