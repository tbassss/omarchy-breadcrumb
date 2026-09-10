"""Packaging guard for known auto-discovered agent instructions, not a security audit."""
from pathlib import Path, PurePosixPath
import unittest

ROOT = Path(__file__).resolve().parents[1]


def is_agent_instruction(path):
    parts = tuple(part.casefold() for part in PurePosixPath(path).parts)
    return (
        parts[-1] in {
            "agents.md", "agents.override.md", "claude.md", "claude.local.md",
            "gemini.md", ".cursorrules", ".windsurfrules", "copilot-instructions.md",
        }
        or any(part in {".claude", ".cursor", ".windsurf"} for part in parts)
        or (len(parts) > 1 and parts[:2] == (".github", "instructions"))
    )


class TestDistribution(unittest.TestCase):
    def test_known_instruction_paths_are_detected_including_nested(self):
        for path in ["AGENTS.md", "docs/AGENTS.md", "Agents.md", "AGENTS.override.md",
                     "CLAUDE.md", "docs/CLAUDE.local.md", "GEMINI.md", ".cursorrules",
                     ".windsurfrules", ".cursor/rules/project.mdc", ".claude/settings.json",
                     ".windsurf/rules/project.md", ".github/copilot-instructions.md",
                     ".github/instructions/python.instructions.md"]:
            with self.subTest(path=path):
                self.assertTrue(is_agent_instruction(path))

    def test_ordinary_contributor_and_command_docs_are_allowed(self):
        for path in ["CONTRIBUTING.md", "docs/COMMAND.md", "README.md",
                     ".github/pull_request_template.md", "tests/test_distribution.py"]:
            with self.subTest(path=path):
                self.assertFalse(is_agent_instruction(path))

    def test_shipped_tree_has_no_known_agent_instruction_files(self):
        offenders = []
        for item in ROOT.rglob("*"):
            relative = item.relative_to(ROOT)
            if ".git" in relative.parts or "__pycache__" in relative.parts:
                continue
            if (item.is_file() or item.is_symlink()) and is_agent_instruction(relative.as_posix()):
                offenders.append(relative.as_posix())
        self.assertEqual(sorted(offenders), [], "Agent instructions must stay outside the plugin payload")


if __name__ == "__main__":
    unittest.main()
