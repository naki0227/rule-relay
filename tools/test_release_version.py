"""tools/release_version.py の単体テスト（tools/check.sh が走らせる）。"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

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


if __name__ == "__main__":
    unittest.main()
