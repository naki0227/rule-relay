#!/usr/bin/env bash
# CI/ローカル用: 固定バージョンの Godot (Linux editor) と Windows・macOS のエクスポートテンプレートを
# 公式リリースから取得し、SHA-512 を検証して配置する。
#   tools/install_godot.sh [インストール先ディレクトリ]   (既定: $HOME/godot)
# 終了後、インストール先の godot を PATH に通すか GODOT 環境変数で指定する。
set -euo pipefail

VERSION="4.6.3"
EDITOR_ZIP="Godot_v${VERSION}-stable_linux.x86_64.zip"
EDITOR_SHA512="a035258da32b77f966a5376f9fa29c30a6adde826a85ba918e1605bd1fc9823eba7d85f1dd5e748956bd2ba72827c0025ffa11bb82aec91128c407a2e723c99c"
TEMPLATES_TPZ="Godot_v${VERSION}-stable_export_templates.tpz"
TEMPLATES_SHA512="da606b61c10157844f8300172df374472665f95015495cb1a7cd132c40ede404faa96cc1016a4b9662db9909ddea69632c4948b2cd11163438dad4808881fb68"
BASE_URL="https://github.com/godotengine/godot/releases/download/${VERSION}-stable"

DEST="${1:-$HOME/godot}"
TEMPLATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${VERSION}.stable"
mkdir -p "$DEST" "$TEMPLATE_DIR"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fetch() {
  local name="$1" sha="$2"
  curl -fsSL --retry 4 --retry-delay 5 -o "$WORK/$name" "$BASE_URL/$name"
  echo "$sha  $WORK/$name" | sha512sum -c -
}

if [ ! -x "$DEST/godot" ]; then
  fetch "$EDITOR_ZIP" "$EDITOR_SHA512"
  unzip -q -o "$WORK/$EDITOR_ZIP" -d "$WORK/editor"
  mv "$WORK/editor/Godot_v${VERSION}-stable_linux.x86_64" "$DEST/godot"
  chmod +x "$DEST/godot"
fi

if [ ! -f "$TEMPLATE_DIR/windows_release_x86_64.exe" ] || [ ! -f "$TEMPLATE_DIR/macos.zip" ]; then
  fetch "$TEMPLATES_TPZ" "$TEMPLATES_SHA512"
  # 容量を抑えるため Windows x86_64 用と macOS 用（Intel と Apple シリコンの両方入り）だけを展開する
  unzip -q -o -j "$WORK/$TEMPLATES_TPZ" \
    templates/version.txt \
    templates/windows_release_x86_64.exe \
    templates/windows_debug_x86_64.exe \
    templates/windows_debug_x86_64_console.exe \
    templates/macos.zip \
    -d "$TEMPLATE_DIR"
fi

"$DEST/godot" --version
ls "$TEMPLATE_DIR"
