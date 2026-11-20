#!/usr/bin/env python3
"""提出版（コンテスト版）に Steam が入っていないことを確かめる（docs/adr/0012）。

  python3 tools/check_no_steam.py --source
      リポジトリ: GodotSteam・Steam の DLL・steam_appid.txt が Git に入っていない、
      project.godot に GodotSteam の設定が無い、提出版のプリセットが Steam のフォルダを外している。
  python3 tools/check_no_steam.py build/windows/rule-relay.exe build/macos/rule-relay.zip ...
      書き出した実行ファイル: 同じフォルダに Steam のファイルが無い。埋め込まれた pck のファイル一覧に
      GodotSteam・Steam 版のフォルダ（src/steam/）が無く、各ファイルとエンジン部分に Steam の印が無い。

例外は1つ: pck の .godot/uid_cache.bin は、Godot がプロジェクトの全ファイルの「UID → パス」の表を
そのまま入れる（書き出さない tests/ も載る）。ここに載る src/steam/ のパス文字列だけは許す（コードではない）。
GodotSteam のパスが載っていたら、GodotSteam を置いたままの木で書き出したということなので止める
（tools/fetch_godotsteam.sh --remove してから書き出す）。

見つかったら終了コード 1。標準ライブラリだけを使う（CI の Python でそのまま動く）。
"""

from __future__ import annotations

import configparser
import struct
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FEATURE = "steam"
# 提出版のプリセットが外すべきフォルダ（Steam 版の通信と GodotSteam）。
REQUIRED_EXCLUDES = ("addons/godotsteam/*", "src/steam/*")
# 提出版の書き出しに現れてはいけない印。src/net/steam_gate.gd にはこれらを書かない。
MARKERS = (
    b"godotsteam",
    b"GodotSteam",
    b"steam_api",
    b"steam_appid",
    b"libsteam",
    b"src/steam/",
    b"SteamMultiplayerPeer",
    b"steam_transport",
)
# 書き出しのフォルダ・ZIP の中にあってはいけないファイル名（小文字で比べる）。
FORBIDDEN_NAMES = ("steam_appid.txt", "steam_api.dll", "steam_api64.dll", "libsteam_api.so",
                   "libsteam_api.dylib")
FORBIDDEN_PARTS = ("godotsteam", "steam_api", "steam_appid")
# pck のファイル一覧にあってはいけないパス（res:// を除いた形）。
FORBIDDEN_PREFIXES = ("addons/godotsteam/", "src/steam/")
UID_CACHE = ".godot/uid_cache.bin"
# uid_cache.bin に載っていてよい印（Steam 版のフォルダのパス文字列）。
UID_CACHE_ALLOWED = (b"src/steam/", b"steam_transport")
PCK_MAGIC = b"GDPC"


def find_markers(data: bytes) -> list[str]:
    return [m.decode() for m in MARKERS if m in data]


def forbidden_name(name: str) -> bool:
    lower = name.lower().rsplit("/", 1)[-1]
    return lower in FORBIDDEN_NAMES or any(part in lower for part in FORBIDDEN_PARTS)


def presets(path: Path) -> list[dict[str, str]]:
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.read(path, encoding="utf-8")
    result = []
    for section in parser.sections():
        if section.startswith("preset.") and section.count(".") == 1:
            values = {k: v.strip().strip('"') for k, v in parser[section].items()}
            result.append(values)
    return result


def is_steam_preset(preset: dict[str, str]) -> bool:
    features = [f.strip() for f in preset.get("custom_features", "").split(",")]
    return FEATURE in features


def check_presets(path: Path) -> list[str]:
    problems = []
    found_steam = False
    for preset in presets(path):
        name = preset.get("name", "?")
        excludes = [e.strip() for e in preset.get("exclude_filter", "").split(",")]
        if is_steam_preset(preset):
            found_steam = True
            if not preset.get("export_path", "").startswith("build/steam/"):
                problems.append(f"{name}: Steam 版は build/steam/ に書き出す（提出版と混ざらないように）")
            continue
        for required in REQUIRED_EXCLUDES:
            if required not in excludes:
                problems.append(f"{name}: exclude_filter に {required} が無い")
    if not found_steam:
        problems.append("Steam 版のプリセット（custom_features に steam）が無い")
    return problems


def check_source() -> list[str]:
    problems = []
    tracked = subprocess.run(
        ["git", "ls-files"], cwd=ROOT, check=True, capture_output=True, text=True
    ).stdout.splitlines()
    for path in tracked:
        if path.startswith("addons/godotsteam/") or forbidden_name(path):
            problems.append(f"Git に入っている: {path}（GodotSteam は tools/fetch_godotsteam.sh で取る）")
    project = (ROOT / "project.godot").read_text(encoding="utf-8")
    if "godotsteam" in project.lower() or "\n[steam]" in project:
        problems.append("project.godot に GodotSteam の設定がある（Steam 版の設定はコミットしない）")
    ignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
    for entry in ("/addons/godotsteam/", "steam_appid.txt"):
        if entry not in ignore:
            problems.append(f".gitignore に {entry} が無い")
    problems.extend(check_presets(ROOT / "export_presets.cfg"))
    return problems


def pck_start(data: bytes) -> int:
    """pck の始まり（単体の .pck なら 0、実行ファイルに埋め込まれていれば末尾の大きさから）。無ければ -1。"""
    if data[:4] == PCK_MAGIC:
        return 0
    if data[-4:] == PCK_MAGIC and len(data) >= 12:
        size = struct.unpack("<Q", data[-12:-4])[0]
        start = len(data) - 12 - size
        if start >= 0 and data[start : start + 4] == PCK_MAGIC:
            return start
    return -1


def pck_files(data: bytes, start: int) -> dict[str, bytes]:
    """Godot 4 の pck（形式 2・3）のファイル一覧と中身。暗号化された pck は読めないので ValueError。"""
    version, _major, _minor, _patch, flags = struct.unpack("<5I", data[start + 4 : start + 24])
    if version not in (2, 3) or flags & 1:
        raise ValueError(f"pck の形式 {version}（flags {flags}）は読めない")
    base = struct.unpack("<Q", data[start + 24 : start + 32])[0]
    if flags & 2:  # PACK_REL_FILEBASE
        base += start
    if version == 3:
        at = start + struct.unpack("<Q", data[start + 32 : start + 40])[0]
    else:
        at = start + 32 + 16 * 4
    count = struct.unpack("<I", data[at : at + 4])[0]
    at += 4
    files = {}
    for _ in range(count):
        length = struct.unpack("<I", data[at : at + 4])[0]
        name = data[at + 4 : at + 4 + length].rstrip(b"\0").decode("utf-8")
        at += 4 + length
        offset, size = struct.unpack("<QQ", data[at : at + 16])
        at += 16 + 16 + 4  # md5 と flags
        files[name.removeprefix("res://")] = data[base + offset : base + offset + size]
    return files


def check_pck_data(label: str, data: bytes) -> list[str]:
    start = pck_start(data)
    if start < 0:
        markers = find_markers(data)
        return [f"{label}: pck が見つからない" + (f"（{', '.join(markers)}）" if markers else "")]
    problems = []
    engine_markers = find_markers(data[:start])
    if engine_markers:
        problems.append(f"{label}: エンジン部分に {', '.join(engine_markers)}（公式のテンプレートではない？）")
    try:
        files = pck_files(data, start)
    except (ValueError, struct.error, UnicodeDecodeError) as error:
        markers = find_markers(data[start:])
        detail = f"（{', '.join(markers)}）" if markers else ""
        return problems + [f"{label}: pck を読めない: {error}{detail}"]
    for name, content in files.items():
        if name.startswith(FORBIDDEN_PREFIXES) or forbidden_name(name):
            problems.append(f"{label}: pck に {name} が入っている")
        markers = find_markers(content)
        if name == UID_CACHE:
            markers = [m for m in markers if m.encode() not in UID_CACHE_ALLOWED]
        if markers:
            problems.append(f"{label}: pck の {name} に {', '.join(markers)}")
    return problems


def check_zip(path: Path) -> list[str]:
    problems = []
    with zipfile.ZipFile(path) as archive:
        for info in archive.infolist():
            if forbidden_name(info.filename):
                problems.append(f"{path}: {info.filename} が入っている")
            if info.is_dir():
                continue
            data = archive.read(info)
            if info.filename.endswith(".pck"):
                problems.extend(check_pck_data(f"{path}:{info.filename}", data))
                continue
            markers = find_markers(data)
            if markers:
                problems.append(f"{path}:{info.filename} に {', '.join(markers)}")
    return problems


def check_artifact(path: Path) -> list[str]:
    if not path.is_file():
        return [f"{path}: 書き出しが無い"]
    problems = []
    for sibling in path.parent.rglob("*"):
        if sibling.is_file() and forbidden_name(sibling.name):
            problems.append(f"{sibling}: Steam のファイルが書き出しのフォルダにある")
    if path.suffix == ".zip":
        return problems + check_zip(path)
    return problems + check_pck_data(str(path), path.read_bytes())


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__)
        return 2
    problems = []
    for arg in argv:
        problems.extend(check_source() if arg == "--source" else check_artifact(Path(arg)))
    for problem in problems:
        print(f"[no-steam] {problem}", file=sys.stderr)
    if problems:
        return 1
    print(f"no-steam: OK ({', '.join(argv)})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
