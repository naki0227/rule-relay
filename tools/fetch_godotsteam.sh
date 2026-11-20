#!/usr/bin/env bash
# Steam 版だけで使う（応募後に使う。docs/steam-build.md・docs/adr/0012）。
# GodotSteam の GDExtension（Steam の再頒布ファイルを含む）を Codeberg の公式リリースから取り、
# SHA-256 を検証して addons/godotsteam/ に置く。addons/godotsteam/ は .gitignore 済みでコミットしない。
#   tools/fetch_godotsteam.sh            取得する（Windows・Linux・macOS の 64 ビット分だけ展開）
#   tools/fetch_godotsteam.sh --remove   取り除く（提出版を書き出す前に。書き出しの検査は tools/check_no_steam.py）
# 提出版（コンテスト版）の書き出しと CI では実行しない。
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="4.24"
ZIP="godotsteam-${VERSION}-gdextension-plugin-4.4.zip"
# 2026-11-20 に取得して計算した値。リリースを差し替えられたら検証で止まる。
ZIP_SHA256="d4358888959a03f4df0c71aafbcdca8f34b8cb9d4522aa5c8454f0e9e3debbf7"
URL="https://codeberg.org/godotsteam/godotsteam/releases/download/v${VERSION}-gde/${ZIP}"
DEST="addons/godotsteam"

if [ "${1:-}" = "--remove" ]; then
  rm -rf "$DEST"
  rmdir addons 2>/dev/null || true
  # エディタが覚えている GDExtension の一覧から外す（残ると提出版の書き出しに名前が入る）
  if [ -f .godot/extension_list.cfg ]; then
    grep -v 'godotsteam' .godot/extension_list.cfg > .godot/extension_list.cfg.tmp || true
    mv .godot/extension_list.cfg.tmp .godot/extension_list.cfg
  fi
  rm -f steam_appid.txt
  echo "removed $DEST"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
curl -fsSL --retry 4 --retry-delay 5 -o "$WORK/$ZIP" "$URL"
echo "$ZIP_SHA256  $WORK/$ZIP" | sha256sum -c -

# エディタ用の更新プラグイン（editor/・godotsteam_plugin.gd）は外す。Asset Library へ通信するうえ、使わない。
rm -rf "$DEST"
mkdir -p "$DEST"
unzip -q -o "$WORK/$ZIP" \
  'addons/godotsteam/godotsteam.gdextension' \
  'addons/godotsteam/license.md' \
  'addons/godotsteam/readme.md' \
  'addons/godotsteam/win64/*' \
  'addons/godotsteam/linux64/*' \
  'addons/godotsteam/osx/*' \
  -d "$WORK/x"
cp -R "$WORK/x/addons/godotsteam/." "$DEST/"
ls -R "$DEST"
echo "GodotSteam GDExtension ${VERSION} を $DEST に置きました（MIT。Steam の再頒布ファイルは Valve の Steamworks SDK の条件）"
