"""tools/release_version.py の単体テスト（tools/check.sh が走らせる）。"""

from __future__ import annotations

import contextlib
import io
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import release_version as rv  # noqa: E402

PRESETS = """[preset.0]

name="Windows Desktop"
platform="Windows Desktop"

[preset.0.options]

application/file_version=""
application/product_version=""

[preset.1]

name="macOS"
platform="macOS"

[preset.1.options]

application/short_version="0.1"
application/version="0.1"

[preset.2]

name="Linux"
platform="Linux"

[preset.2.options]

application/version="keep"
"""


class ReleaseVersionTest(unittest.TestCase):
    def test_tag_becomes_a_three_part_version(self) -> None:
        self.assertEqual(rv.version_from_tag("v0.2.1"), "0.2.1")
        self.assertEqual(rv.version_from_tag("v1.10.0"), "1.10.0")
        self.assertEqual(rv.windows_version("0.2.1"), "0.2.1.0")

    def test_other_tag_shapes_are_refused(self) -> None:
        for tag in ("0.2.1", "v0.2", "v0.2.1-rc1", "v0.2.1.0", "vX"):
            with self.assertRaises(ValueError, msg=tag):
                rv.version_from_tag(tag)

    def test_set_writes_macos_and_four_part_windows_versions_only(self) -> None:
        text = rv.set_versions(PRESETS, "0.2.1")
        self.assertIn('application/short_version="0.2.1"', text)
        self.assertIn('application/file_version="0.2.1.0"', text)
        self.assertIn('application/product_version="0.2.1.0"', text)
        self.assertIn('application/version="keep"', text, "the Linux preset is left alone")
        problems, version = rv.check_presets(text, "v0.2.1")
        self.assertEqual(problems, [])
        self.assertEqual(version, "0.2.1")

    def test_check_finds_a_stale_or_mismatched_version(self) -> None:
        problems, _ = rv.check_presets(PRESETS, None)
        self.assertTrue(problems, "0.1 and empty Windows versions do not match")
        text = rv.set_versions(PRESETS, "0.2.0")
        problems, _ = rv.check_presets(text, "v0.2.1")
        self.assertEqual(len(problems), 1)
        self.assertIn("v0.2.1", problems[0])

    def test_exe_version_strings_are_read_from_the_string_table(self) -> None:
        def entry(key: str, value: str) -> bytes:
            raw = (key + "\0").encode("utf-16-le")
            pad = b"\0\0" if len(raw) % 4 else b""
            return raw + pad + (value + "\0").encode("utf-16-le")

        data = b"MZ..." + entry("FileVersion", "0.2.1.0") + entry("ProductVersion", "0.2.1.0")
        self.assertEqual(rv.exe_versions(data), {"FileVersion": "0.2.1.0", "ProductVersion": "0.2.1.0"})

    def test_committed_presets_are_consistent(self) -> None:
        problems, version = rv.check_presets(rv.PRESETS.read_text(encoding="utf-8"), None)
        self.assertEqual(problems, [])
        self.assertEqual(version, "0.3.1")


NOTES = "## rule-relay v0.3.1\n\n- 新しいこと\n\n### 生成 AI の利用\n- 記録は docs/ai-usage.md\n"


class TagOrderTest(unittest.TestCase):
    """v0.3.1: 版を上げる PR のマージ前に Release を作り、タグが 0.3.0 のコミットを指した。"""

    def test_matching_tag_passes(self) -> None:
        self.assertIsNone(rv.tag_mismatch(rv.set_versions(PRESETS, "0.3.1"), "v0.3.1"))

    def test_stale_presets_explain_what_differs_and_how_to_fix(self) -> None:
        found = rv.tag_mismatch(rv.set_versions(PRESETS, "0.3.0"), "v0.3.1", "0123456789abcdef")
        assert found is not None
        title, lines = found
        text = "\n".join(lines)
        self.assertIn("v0.3.1", title)
        self.assertIn("0.3.0", title)
        self.assertIn("版 0.3.1", text, "what the tag says")
        self.assertIn("版 0.3.0", text, "what the presets say")
        self.assertIn("0123456", text, "the tagged commit")
        self.assertIn("Release を消し", text)
        self.assertIn("タグ v0.3.1 も消す", text)
        self.assertIn("マージしてから、main", text)
        self.assertIn("空のまま", text)
        self.assertIn("docs/release-notes/v0.3.1.md", text)

    def test_bad_tag_shape_is_refused(self) -> None:
        with self.assertRaises(ValueError):
            rv.tag_mismatch(PRESETS, "v0.3")

    def test_verify_tag_writes_an_error_annotation_and_the_step_summary(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            presets = Path(tmp) / "export_presets.cfg"
            presets.write_text(rv.set_versions(PRESETS, "0.3.0"), encoding="utf-8")
            summary = Path(tmp) / "summary.md"
            out = io.StringIO()
            env = {"GITHUB_STEP_SUMMARY": str(summary), "GITHUB_SHA": "abcdef0123"}
            with mock.patch.object(rv, "PRESETS", presets), mock.patch.dict(os.environ, env):
                with contextlib.redirect_stdout(out):
                    code = rv.main(["verify-tag", "v0.3.1", "--github"])
            self.assertEqual(code, 1)
            self.assertTrue(out.getvalue().startswith("::error title="), out.getvalue())
            self.assertNotIn("\n", out.getvalue().strip(), "one annotation line (newlines escaped)")
            written = summary.read_text(encoding="utf-8")
            self.assertIn("### エラー:", written)
            self.assertIn("abcdef0", written)

    def test_annotation_escapes_newlines_and_title_separators(self) -> None:
        line = rv.annotation("warning", "a: b, c", ["100%", "次の行"])
        self.assertEqual(line, "::warning title=a%3A b%2C c::100%25%0A次の行")


class ReleaseBodyTest(unittest.TestCase):
    def test_empty_body_is_filled_from_the_notes_file(self) -> None:
        for body in ("", "\n", "  \r\n"):
            action, messages = rv.release_body_action("v0.3.1", body, NOTES)
            self.assertEqual(action, "fill", repr(body))
            self.assertEqual([m[0] for m in messages], ["notice"])

    def test_body_that_is_already_the_notes_is_left_alone(self) -> None:
        crlf = NOTES.replace("\n", "\r\n") + "   \n"
        generated = NOTES + "\n## What's Changed\n* PR by someone\n"
        for body in (NOTES, crlf, generated):
            self.assertEqual(rv.release_body_action("v0.3.1", body, NOTES), ("keep", []))

    def test_hand_edited_body_is_kept_with_a_warning_on_how_to_paste(self) -> None:
        # v0.3.0: 本人が生成 AI の節を意図して消した。CI はこれを上書きしない。
        edited = NOTES.split("### 生成 AI")[0]
        action, messages = rv.release_body_action("v0.3.1", edited, NOTES)
        self.assertEqual(action, "keep")
        self.assertEqual(len(messages), 1)
        level, _, lines = messages[0]
        text = "\n".join(lines)
        self.assertEqual(level, "warning")
        self.assertIn("書き換えていません", text)
        self.assertIn("gh release edit v0.3.1 --notes-file docs/release-notes/v0.3.1.md", text)
        self.assertIn("Raw", text)
        self.assertNotIn("残っています", text, "no paste signs in a plain edit")

    def test_obsidian_or_html_leftovers_are_pointed_out_but_still_kept(self) -> None:
        for body in ("見て [[v0.3.1]]", "<!-- draft -->\n本文", "行<br>行", "%%メモ%%\n本文"):
            action, messages = rv.release_body_action("v0.3.1", body, NOTES)
            self.assertEqual(action, "keep", body)
            self.assertIn("残っています", messages[0][2][-1], body)

    def test_missing_notes_file(self) -> None:
        self.assertEqual(rv.release_body_action("v9.9.9", "手書き", None), ("keep", []))
        action, messages = rv.release_body_action("v9.9.9", "", None)
        self.assertEqual(action, "keep")
        self.assertEqual(messages[0][0], "warning")

    def test_release_body_command_writes_the_action(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            body = Path(tmp) / "body.md"
            action = Path(tmp) / "action"
            body.write_text("", encoding="utf-8")
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                code = rv.main(["release-body", "v0.3.1", "--body-file", str(body), "--action-file", str(action)])
            self.assertEqual(code, 0)
            self.assertEqual(action.read_text(encoding="utf-8").strip(), "fill", "v0.3.1.md is committed")


if __name__ == "__main__":
    unittest.main()
