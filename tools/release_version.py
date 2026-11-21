#!/usr/bin/env python3
"""配布版のアプリの版（バージョン）を、タグと書き出しのプリセットでそろえる（docs/how-to-test.md「配布版の作り方」）。

  python3 tools/release_version.py set v0.2.1
      export_presets.cfg の版をタグから書き換える（CI がタグの書き出しの前に呼ぶ）。
        - macOS: application/short_version と application/version に 0.2.1
        - Windows（提出版・Steam 版）: application/file_version と application/product_version に 0.2.1.0
          （Windows の版は 4 つの数字が要るので、最後に 0 を足す）
  python3 tools/release_version.py check
      プリセットの中の版が、Mac と Windows でそろっているかを確かめる（tools/check.sh が毎回呼ぶ）。
  python3 tools/release_version.py check --tag v0.2.1
      上に加えて、プリセットの版がタグと同じかを確かめる（CI のタグの書き出しで呼ぶ）。
  python3 tools/release_version.py check --exported [--tag v0.2.1]
      上に加えて、書き出した実行ファイル（build/windows/rule-relay.exe の版情報、build/macos/rule-relay.zip の
      Info.plist）に入った版が、プリセット（とタグ）と同じかを確かめる（tools/check.sh --build が呼ぶ）。

タグの形は v<数>.<数>.<数>（例: v0.2.1）だけを受け付ける。違えば終了コード 1。標準ライブラリだけを使う。
"""

from __future__ import annotations

import argparse
import plistlib
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PRESETS = ROOT / "export_presets.cfg"
WINDOWS_EXE = ROOT / "build" / "windows" / "rule-relay.exe"
MACOS_ZIP = ROOT / "build" / "macos" / "rule-relay.zip"

TAG_PATTERN = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
MACOS_KEYS = ("application/short_version", "application/version")
WINDOWS_KEYS = ("application/file_version", "application/product_version")
# 書き出した Mac の .app の Info.plist で見る項目（Godot が上の 2 つから書く）
PLIST_KEYS = ("CFBundleShortVersionString", "CFBundleVersion")
# 書き出した exe の版情報（VS_VERSION_INFO の StringFileInfo）で見る項目
EXE_KEYS = ("FileVersion", "ProductVersion")


def version_from_tag(tag: str) -> str:
    """v0.2.1 → 0.2.1。形が違えば ValueError。"""
    match = TAG_PATTERN.match(tag.strip())
    if match is None:
        raise ValueError(f"タグの形が違う（v<数>.<数>.<数>、例 v0.2.1）: {tag!r}")
    return ".".join(str(int(part)) for part in match.groups())


def windows_version(version: str) -> str:
    """Windows の版は 4 つの数字（0.2.1 → 0.2.1.0）。"""
    return version + ".0"


def _platform_of(section: list[str]) -> str:
    for line in section:
        if line.startswith("platform="):
            return line.split("=", 1)[1].strip().strip('"')
    return ""


def _sections(text: str) -> list[tuple[str, list[str]]]:
    """[preset.N] と [preset.N.options] の組ごとに、(platform, 行の番号) を並べる。"""
    lines = text.splitlines()
    result: list[tuple[str, list[str]]] = []
    current: list[str] = []
    for line in lines:
        if line.startswith("[preset.") and not line.endswith(".options]"):
            current = []
            result.append(("", current))
        current.append(line)
    return [(_platform_of(section), section) for _, section in result]


def preset_versions(text: str) -> list[tuple[str, str, str]]:
    """プリセットごとの (platform, 項目, 値)。Mac と Windows の版の項目だけ。"""
    found = []
    for platform, section in _sections(text):
        keys = MACOS_KEYS if platform == "macOS" else WINDOWS_KEYS if platform == "Windows Desktop" else ()
        for line in section:
            key, _, value = line.partition("=")
            if key in keys:
                found.append((platform, key, value.strip().strip('"')))
    return found


def set_versions(text: str, version: str) -> str:
    """プリセットの版を書き換えた export_presets.cfg の中身を返す。"""
    out = []
    platform = ""
    for line in text.splitlines():
        if line.startswith("[preset.") and not line.endswith(".options]"):
            platform = ""
        if line.startswith("platform="):
            platform = line.split("=", 1)[1].strip().strip('"')
        key = line.partition("=")[0]
        if platform == "macOS" and key in MACOS_KEYS:
            line = f'{key}="{version}"'
        elif platform == "Windows Desktop" and key in WINDOWS_KEYS:
            line = f'{key}="{windows_version(version)}"'
        out.append(line)
    return "\n".join(out) + ("\n" if text.endswith("\n") else "")


def check_presets(text: str, tag: str | None) -> tuple[list[str], str]:
    """プリセットの版を確かめ、(問題, Mac の版) を返す。"""
    problems = []
    found = preset_versions(text)
    macos = {value for platform, _, value in found if platform == "macOS"}
    windows = {value for platform, _, value in found if platform == "Windows Desktop"}
    if len([f for f in found if f[0] == "macOS"]) < len(MACOS_KEYS):
        problems.append("export_presets.cfg: macOS の版の項目が足りない")
    if not windows:
        problems.append("export_presets.cfg: Windows の版の項目が無い")
    if len(macos) != 1:
        problems.append(f"export_presets.cfg: macOS の版がそろっていない: {sorted(macos)}")
        return problems, ""
    version = next(iter(macos))
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        problems.append(f"export_presets.cfg: macOS の版が <数>.<数>.<数> でない: {version!r}")
    if windows != {windows_version(version)}:
        problems.append(
            f"export_presets.cfg: Windows の版 {sorted(windows)} が Mac の版 {version} と合わない"
            f"（{windows_version(version)} にする）"
        )
    if tag is not None:
        expected = version_from_tag(tag)
        if version != expected:
            problems.append(
                f"export_presets.cfg の版 {version} がタグ {tag} と違う"
                f"（tools/release_version.py set {tag} を書き出しの前に）"
            )
    return problems, version


def exe_versions(data: bytes) -> dict[str, str]:
    """exe の版情報（StringFileInfo）から FileVersion・ProductVersion の文字列を読む。"""
    result = {}
    for key in EXE_KEYS:
        marker = (key + "\0").encode("utf-16-le")
        start = data.find(marker)
        if start < 0:
            continue
        pos = start + len(marker)
        # 値は 4 バイト境界にそろえて置かれる（間は 0 で埋まる）
        while pos + 1 < len(data) and data[pos : pos + 2] == b"\0\0":
            pos += 2
        end = data.find(b"\0\0", pos)
        while end > 0 and (end - pos) % 2:
            end = data.find(b"\0\0", end + 1)
        if end > pos:
            result[key] = data[pos:end].decode("utf-16-le", "replace")
    return result


def plist_versions(zip_path: Path) -> dict[str, str]:
    """Mac の ZIP に入った .app の Info.plist から版を読む。"""
    with zipfile.ZipFile(zip_path) as archive:
        for name in archive.namelist():
            parts = name.split("/")
            if len(parts) == 3 and parts[0].endswith(".app") and parts[1:] == ["Contents", "Info.plist"]:
                plist = plistlib.loads(archive.read(name))
                return {key: str(plist.get(key, "")) for key in PLIST_KEYS}
    return {}


def check_exported(version: str, exe: Path, macos_zip: Path) -> list[str]:
    """書き出した exe と Mac の ZIP に入った版が version（Mac の形）と同じか。"""
    problems = []
    if not exe.is_file():
        problems.append(f"{exe} が無い")
    else:
        found = exe_versions(exe.read_bytes())
        for key in EXE_KEYS:
            if found.get(key) != windows_version(version):
                problems.append(
                    f"{exe.name}: {key} が {found.get(key)!r}（{windows_version(version)} のはず。"
                    "Windows のプリセットの application/modify_resources が true か確かめる）"
                )
    if not macos_zip.is_file():
        problems.append(f"{macos_zip} が無い")
    else:
        found = plist_versions(macos_zip)
        if not found:
            problems.append(f"{macos_zip.name}: .app の Info.plist が無い")
        for key in PLIST_KEYS:
            if found and found.get(key) != version:
                problems.append(f"{macos_zip.name}: Info.plist の {key} が {found.get(key)!r}（{version} のはず）")
    return problems


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    set_parser = sub.add_parser("set", help="プリセットの版をタグから書き換える")
    set_parser.add_argument("tag")
    check_parser = sub.add_parser("check", help="プリセット（と書き出し）の版を確かめる")
    check_parser.add_argument("--tag", help="この版と同じかも確かめる（例 v0.2.1）")
    check_parser.add_argument("--exported", action="store_true", help="書き出した exe と Mac の ZIP も見る")
    check_parser.add_argument("--exe", type=Path, default=WINDOWS_EXE)
    check_parser.add_argument("--macos-zip", type=Path, default=MACOS_ZIP)
    args = parser.parse_args(argv)

    try:
        text = PRESETS.read_text(encoding="utf-8")
        if args.command == "set":
            version = version_from_tag(args.tag)
            PRESETS.write_text(set_versions(text, version), encoding="utf-8")
            print(f"export_presets.cfg: macOS {version} / Windows {windows_version(version)}")
            return 0
        problems, version = check_presets(text, args.tag)
    except ValueError as error:
        print(f"[version] {error}", file=sys.stderr)
        return 1
    if args.exported and version:
        problems.extend(check_exported(version, args.exe, args.macos_zip))
    for problem in problems:
        print(f"[version] {problem}", file=sys.stderr)
    if problems:
        return 1
    where = "プリセットと書き出し" if args.exported else "プリセット"
    print(f"version: OK {version}（{where}" + (f"・タグ {args.tag}）" if args.tag else "）"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
