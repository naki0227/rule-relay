#!/usr/bin/env bash
# ローカルとCIで同じ品質ゲートを実行する。
#   tools/check.sh            format / lint / import / static / test / smoke
#   tools/check.sh --build    上記に加えて Windows 実行ファイルをエクスポート
#   tools/check.sh --fix      gdformat で整形してから検査
# 環境変数 GODOT で Godot 実行ファイルを指定できる（既定: godot）。
set -euo pipefail

cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
BUILD=0
FIX=0
for arg in "$@"; do
  case "$arg" in
    --build) BUILD=1 ;;
    --fix) FIX=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

LOG_DIR="build/logs"
mkdir -p "$LOG_DIR"
mapfile -t GD_FILES < <(git ls-files --cached --others --exclude-standard '*.gd')

step() { printf '\n== %s ==\n' "$1"; }

# Godot はスクリプトエラーでも終了コード0を返すことがあるので、ログも検査する。
run_godot() {
  local name="$1"; shift
  local log="$LOG_DIR/$name.log"
  set +e
  timeout "${GODOT_TIMEOUT:-600}" "$GODOT" "$@" >"$log" 2>&1
  local code=$?
  set -e
  cat "$log"
  if [ "$code" -ne 0 ]; then
    echo "[$name] godot exited with $code" >&2
    exit 1
  fi
  if grep -E '^(SCRIPT ERROR|ERROR|USER ERROR):|Parse Error|Failed to load script' "$log" >/dev/null; then
    echo "[$name] errors found in godot output" >&2
    exit 1
  fi
}

step "format"
if [ "$FIX" -eq 1 ]; then
  gdformat "${GD_FILES[@]}"
fi
gdformat --check "${GD_FILES[@]}"

step "lint"
gdlint "${GD_FILES[@]}"

step "sound budget (tools/sfx)"
python3 -m unittest discover -s tools/sfx -p 'test_*.py'

step "import"
run_godot import --headless --import

step "static"
run_godot static --headless --script res://tools/check_scripts.gd

step "test"
run_godot test --headless --fixed-fps 60 --script res://tests/run_tests.gd

step "smoke (main scene, 180 frames)"
run_godot smoke --headless --fixed-fps 60 --quit-after 180

if [ "$BUILD" -eq 1 ]; then
  step "build (Windows Desktop)"
  mkdir -p build/windows
  run_godot export --headless --export-release "Windows Desktop" build/windows/rule-relay.exe
  test -s build/windows/rule-relay.exe
  ls -la build/windows
fi

printf '\nall checks passed\n'
