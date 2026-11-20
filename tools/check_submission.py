#!/usr/bin/env python3
"""提出用の ZIP を作り、中身を確かめる（docs/submission/checklist.md）。

  python3 tools/check_submission.py
      build/windows/rule-relay.exe と build/macos/rule-relay.zip（tools/check.sh --build の書き出し）から
      build/submission/rule-relay-windows.zip と rule-relay-macos.zip を作り、次を確かめる。
        - Steam が入っていない（tools/check_no_steam.py と同じ検査）
        - 秘密のファイル（.env・鍵・証明書・export_credentials.cfg など）が無い
        - user:// に書かれる物（進行・設定・合言葉・操作の案内の記録・ログ）や、
          実行ファイルの隣の _sc_ / override.cfg が入っていない
        - 書き出さないと決めたもの（art/・tests/・tools/・docs/・build/・.github/・.claude/、
          Blender の原本・Python・Markdown）が pck に無い
        - LICENSES.txt が ZIP の一番上にあり、リポジトリの LICENSES.txt と同じ
        - pck に入っているフォントなどのサードパーティ素材が、すべて LICENSES.txt に載っている
      最後に、同梱しているサードパーティのライセンスの一覧を出す。
  python3 tools/check_submission.py --godot godot
      上に加えて、Godot が自分で報告する組み込み部品の一覧から LICENSES.txt を作り直し、
      コミットしてある LICENSES.txt と同じかを確かめる（エンジンの版を上げたときの更新漏れを防ぐ）。
  python3 tools/check_submission.py --write-licenses --godot godot
      LICENSES.txt を作り直して書く（ZIP は作らない）。

何を書き出すか（理由は docs/submission/checklist.md の「同梱するもの」）:
  入れる: 実行ファイル（pck を埋め込んだ exe / Mac の .app）と LICENSES.txt だけ。
  入れない: ソース素材（art/）・テスト・道具・文書・ログ・秘密・利用者のデータ・Steam 版。

見つかったら終了コード 1。標準ライブラリと tools/check_no_steam.py だけを使う。
"""

from __future__ import annotations

import argparse
import json
import struct
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_no_steam  # noqa: E402  （同じフォルダの検査を使い回す）

ROOT = Path(__file__).resolve().parent.parent
LICENSES = ROOT / "LICENSES.txt"
LICENSES_NAME = "LICENSES.txt"
FONT_LICENSE = ROOT / "assets" / "fonts" / "OFL-zenmarugothic.txt"
WINDOWS_EXE = Path("build/windows/rule-relay.exe")
MACOS_ZIP = Path("build/macos/rule-relay.zip")
OUT_DIR = Path("build/submission")

# 提出版のプリセット（Steam 版以外）が外していなければならないフォルダ。
REQUIRED_EXCLUDES = ("tests/*", "tools/*", "docs/*", "build/*")
# pck に入っていてはいけない場所（res:// を除いた形）。art/ は .gdignore で元から入らないが、念のため見る。
FORBIDDEN_PCK_PREFIXES = (
    "art/",
    "tests/",
    "tools/",
    "docs/",
    "build/",
    ".github/",
    ".claude/",
    ".git/",
    "addons/godotsteam/",
    "src/steam/",
)
# pck の一番上に入ってよいもの（書き出すと決めたもの）。ほかの物が増えたら、中身を確かめてから足す。
ALLOWED_PCK_TOP = (
    "src",  # ゲームのコード（バイナリトークン形式）
    "scenes",
    "assets",  # 取り込み設定（.import）と、取り込みの要らない素材
    ".godot",  # 取り込み済みの素材・クラス一覧・uid_cache.bin
    "project.binary",
    "icon.svg",
    "icon.svg.import",
    "icudt_godot.dat",  # 和文の折り返しに使う ICU のデータ（ICU のライセンスは LICENSES.txt に載る）
)
# 拡張子（小文字）。原本・道具・文書・秘密・ログ。
FORBIDDEN_SUFFIXES = (
    ".blend",
    ".blend1",
    ".blend2",
    ".py",
    ".pyc",
    ".md",
    ".pem",
    ".key",
    ".p12",
    ".p8",
    ".pfx",
    ".mobileprovision",
    ".keystore",
    ".log",
)
# ファイル名（小文字、フォルダを除いた名前）。
FORBIDDEN_NAMES = (
    "export_credentials.cfg",
    "credentials.json",
    "id_rsa",
    "id_ed25519",
    "steam_appid.txt",
    # user:// を実行ファイルの隣へ移す印（自己完結モード）と、プロジェクト設定の上書き
    "_sc_",
    "._sc_",
    "override.cfg",
    "settings.cfg",
)
# user:// に書かれるもの（src/ の DEFAULT_DIR・DEFAULT_PATH・SESSION_KEY_DIR）。ZIP にも pck にもあってはいけない。
USER_DATA_PREFIXES = ("progress/", "hints/", "session/", "logs/", "userdata/", "editor_data/")

# 同梱してよいサードパーティ素材と、LICENSES.txt に載っていなければならない名前。
# 素材を足したら、ここと LICENSES.txt（_project_sections）の両方に足す。
THIRD_PARTY_ASSETS = {
    "zenmarugothic": "Zen Maru Gothic",
}
FONT_SUFFIXES = (".ttf", ".otf", ".woff", ".woff2", ".fontdata")
# LICENSES.txt に必ず載っている名前（エンジン・組み込みの物理・フォント・生成した音声）。
REQUIRED_IN_LICENSES = (
    "Godot Engine",
    "Jolt Physics",
    "Zen Maru Gothic",
    "SIL OPEN FONT LICENSE",
    "Stable Audio 3",
    "Stability AI Community License",
)


def lower_name(path: str) -> str:
    return path.rstrip("/").rsplit("/", 1)[-1].lower()


def _beside_program(path: str) -> str:
    """Mac の .app の中なら、実行ファイル・pck の置き場からの相対パスにする（user:// の名残を同じ形で見る）。"""
    for marker in ("contents/macos/", "contents/resources/"):
        if marker in path:
            return path.split(marker, 1)[1]
    return path


def forbidden_file(path: str) -> str | None:
    """ZIP・pck のどちらにも共通の禁止。理由を返す（問題なければ None）。"""
    name = lower_name(path)
    lower = path.lower()
    if name == ".env" or name.startswith(".env."):
        return "秘密のファイル（.env）"
    if name in FORBIDDEN_NAMES:
        return "入れてはいけない名前"
    if lower.endswith(FORBIDDEN_SUFFIXES):
        return "原本・道具・文書・鍵・ログ"
    if _beside_program(lower).startswith(USER_DATA_PREFIXES):
        return "user:// に書かれるデータ"
    if check_no_steam.forbidden_name(path):
        return "Steam のファイル"
    return None


def check_pck_listing(label: str, files: dict[str, bytes]) -> tuple[list[str], set[str]]:
    """pck のファイル一覧を確かめ、見つかったサードパーティ素材の名前を返す。"""
    problems = []
    found = set()
    for name in files:
        if name.startswith(FORBIDDEN_PCK_PREFIXES):
            problems.append(f"{label}: pck に {name}（書き出さないと決めたフォルダ）")
            continue
        if name.split("/", 1)[0] not in ALLOWED_PCK_TOP:
            # アドオン（addons/）もここで止まる。入れるならライセンスを LICENSES.txt に足してから許す
            problems.append(f"{label}: pck に想定外の {name}（入れると決めたら ALLOWED_PCK_TOP に足す）")
        reason = forbidden_file(name)
        if reason:
            problems.append(f"{label}: pck に {name}（{reason}）")
        lower = name.lower()
        if lower.endswith(FONT_SUFFIXES) or ".ttf-" in lower or ".otf-" in lower:
            key = next((k for k in THIRD_PARTY_ASSETS if k in lower_name(name)), None)
            if key is None:
                problems.append(f"{label}: ライセンスの一覧に無いフォント {name}")
            else:
                found.add(THIRD_PARTY_ASSETS[key])
    return problems, found


def check_pck_bytes(label: str, data: bytes) -> tuple[list[str], set[str]]:
    problems = check_no_steam.check_pck_data(label, data)
    start = check_no_steam.pck_start(data)
    if start < 0:
        return problems, set()
    try:
        files = check_no_steam.pck_files(data, start)
    except (ValueError, struct.error, UnicodeDecodeError) as error:
        return problems + [f"{label}: pck を読めない: {error}"], set()
    listing_problems, found = check_pck_listing(label, files)
    if not any(n.endswith("project.binary") for n in files):
        listing_problems.append(f"{label}: pck に project.binary が無い（書き出しが壊れている？）")
    return problems + listing_problems, found


def check_submission_zip(path: Path, licenses_text: bytes) -> tuple[list[str], set[str]]:
    problems = []
    found: set[str] = set()
    has_licenses = False
    has_program = False
    with zipfile.ZipFile(path) as archive:
        for info in archive.infolist():
            name = info.filename
            if info.is_dir():
                continue
            label = f"{path.name}:{name}"
            if name == LICENSES_NAME:
                has_licenses = True
                if archive.read(info) != licenses_text:
                    problems.append(f"{label}: リポジトリの LICENSES.txt と違う")
                continue
            # 入れてよいのは exe か .app の中身だけ
            top = name.split("/", 1)[0]
            if not (name == "rule-relay.exe" or top.endswith(".app")):
                problems.append(f"{label}: 実行ファイルと LICENSES.txt のほかに入っている")
            reason = forbidden_file(name)
            if reason:
                problems.append(f"{label}: {reason}")
            data = archive.read(info)
            if name.endswith((".exe", ".pck")):
                has_program = True
                pck_problems, pck_found = check_pck_bytes(label, data)
                problems.extend(pck_problems)
                found |= pck_found
                continue
            markers = check_no_steam.find_markers(data)
            if markers:
                problems.append(f"{label}: Steam の印 {', '.join(markers)}")
    if not has_licenses:
        problems.append(f"{path}: 一番上に {LICENSES_NAME} が無い")
    if not has_program:
        problems.append(f"{path}: 実行ファイル（exe か .app の pck）が無い")
    return problems, found


def build_windows_zip(exe: Path, out: Path) -> None:
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.write(exe, "rule-relay.exe")
        archive.write(LICENSES, LICENSES_NAME)


def build_macos_zip(source: Path, out: Path) -> None:
    """Godot が書き出した .app の ZIP に LICENSES.txt を足す（実行権限などの属性はそのまま写す）。"""
    with zipfile.ZipFile(source) as src, zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as dst:
        for info in src.infolist():
            if info.filename == LICENSES_NAME:
                continue
            dst.writestr(info, src.read(info))
        dst.write(LICENSES, LICENSES_NAME)


def check_presets() -> list[str]:
    problems = []
    for preset in check_no_steam.presets(ROOT / "export_presets.cfg"):
        if check_no_steam.is_steam_preset(preset):
            continue
        excludes = [e.strip() for e in preset.get("exclude_filter", "").split(",")]
        for required in REQUIRED_EXCLUDES:
            if required not in excludes:
                problems.append(f"{preset.get('name', '?')}: exclude_filter に {required} が無い")
        if preset.get("include_filter", "").strip():
            problems.append(f"{preset.get('name', '?')}: include_filter で資源以外を足している（中身を確かめる）")
    return problems


def dump_engine(godot: str) -> dict:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "engine.json"
        subprocess.run(
            [godot, "--headless", "--script", "res://tools/dump_engine_licenses.gd", "--", str(out)],
            cwd=ROOT,
            check=True,
            capture_output=True,
            timeout=300,
        )
        return json.loads(out.read_text(encoding="utf-8"))


def _project_sections() -> list[str]:
    font_license = FONT_LICENSE.read_text(encoding="utf-8").strip()
    return [
        "■ フォント: Zen Maru Gothic（Medium / Bold）",
        "  ライセンス: SIL Open Font License 1.1（下に全文）",
        "  取得元: Google Fonts（github.com/google/fonts の ofl/zenmarugothic/）。",
        "  容量を抑えるため、収録する文字を絞った改変版を同梱しています。",
        "",
        font_license,
        "",
        "■ 生成 AI で作った効果音（6 種）",
        "  モデル: Stable Audio 3 medium（Stability AI）。手元の PC で生成しました。",
        "  モデルのライセンス: Stability AI Community License",
        "  効果音の残りと 3D モデル・アイコンは、このゲームのために作ったスクリプトで生成したものです。",
        "",
    ]


def render_licenses(engine: dict) -> str:
    lines = [
        "rule-relay（仮題）で使っているサードパーティのライセンス",
        "=" * 60,
        "",
        "このファイルは tools/check_submission.py --write-licenses で作りました。",
        f"エンジン: Godot Engine {engine.get('version', '')}（下の一覧は、このエンジンが自分で報告したもの）",
        "",
    ]
    lines += _project_sections()
    lines += ["■ Godot Engine", "", engine["godot_license"].strip(), ""]
    lines += ["■ Godot Engine に組み込まれた部品（著作権表示）", ""]
    for component in engine["copyright"]:
        lines.append(f"- {component['name']}")
        for part in component.get("parts", []):
            for holder in part.get("copyright", []):
                lines.append(f"    Copyright {holder}")
            lines.append(f"    License: {part.get('license', '')}")
    lines += ["", "■ ライセンス本文", ""]
    for name in sorted(engine["licenses"]):
        lines += [f"----- {name} -----", engine["licenses"][name].strip(), ""]
    return "\n".join(lines).rstrip() + "\n"


def check_licenses_text(text: str) -> list[str]:
    return [
        f"LICENSES.txt に {required} が無い" for required in REQUIRED_IN_LICENSES if required not in text
    ]


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--godot", help="Godot の実行ファイル（LICENSES.txt を作る・照らし合わせる）")
    parser.add_argument("--write-licenses", action="store_true", help="LICENSES.txt を作り直して終わる")
    args = parser.parse_args(argv)

    if args.write_licenses:
        if not args.godot:
            parser.error("--write-licenses には --godot が要る")
        LICENSES.write_text(render_licenses(dump_engine(args.godot)), encoding="utf-8")
        print(f"wrote {LICENSES.relative_to(ROOT)}")
        return 0

    problems = check_presets()
    if not LICENSES.is_file():
        print(f"[submission] {LICENSES_NAME} が無い（--write-licenses --godot で作る）", file=sys.stderr)
        return 1
    text = LICENSES.read_text(encoding="utf-8")
    problems.extend(check_licenses_text(text))
    if args.godot and render_licenses(dump_engine(args.godot)) != text:
        problems.append("LICENSES.txt が古い（tools/check_submission.py --write-licenses --godot で作り直す）")

    out_dir = ROOT / OUT_DIR
    out_dir.mkdir(parents=True, exist_ok=True)
    found: set[str] = set()
    targets = []
    for source, out, build in (
        (ROOT / WINDOWS_EXE, out_dir / "rule-relay-windows.zip", build_windows_zip),
        (ROOT / MACOS_ZIP, out_dir / "rule-relay-macos.zip", build_macos_zip),
    ):
        if not source.is_file():
            problems.append(f"{source.relative_to(ROOT)} が無い（先に tools/check.sh --build）")
            continue
        build(source, out)
        # 書き出しのフォルダに Steam のファイルが紛れていないか（check_no_steam と同じ）
        for sibling in source.parent.rglob("*"):
            if sibling.is_file() and check_no_steam.forbidden_name(sibling.name):
                problems.append(f"{sibling}: Steam のファイルが書き出しのフォルダにある")
        zip_problems, zip_found = check_submission_zip(out, text.encode("utf-8"))
        problems.extend(zip_problems)
        found |= zip_found
        targets.append(out)

    for problem in problems:
        print(f"[submission] {problem}", file=sys.stderr)
    if problems:
        return 1
    missing = [name for name in found if name not in text]
    if missing:
        print(f"[submission] LICENSES.txt に無い素材: {', '.join(missing)}", file=sys.stderr)
        return 1
    print("同梱しているサードパーティのライセンス（LICENSES.txt）:")
    print("  - Godot Engine（MIT）と、エンジンに組み込まれた部品（Jolt Physics ほか。LICENSES.txt に全文）")
    for name in sorted(found):
        print(f"  - {name}（SIL Open Font License 1.1）")
    print("  - 効果音 6 種: Stable Audio 3 medium の生成物（Stability AI Community License）")
    for out in targets:
        print(f"submission: OK {out.relative_to(ROOT)} ({out.stat().st_size:,} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
