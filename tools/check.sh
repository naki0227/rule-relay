#!/usr/bin/env bash
# ローカルとCIで同じ品質ゲートを実行する。
#   tools/check.sh            format / lint / import / static / test / smoke
#   tools/check.sh --build    上記に加えて Windows・macOS・Linux（Steam Deck）向けにエクスポート
#                             （提出版の書き出しに Steam が入っていないことも確かめる。docs/adr/0012）
#                             （提出用の ZIP を build/submission/ に作り、tools/check_submission.py で確かめる）
#                             （書き出した exe と Mac の .app の版が export_presets.cfg と同じかも確かめる）
#   tools/check.sh --fix      gdformat で整形してから検査
#   tools/check.sh --serial   テストを 1 つの Godot で順に流す（並列にする前と同じ流し方）
#   tools/check.sh --jobs=N   テストを N 個の Godot で並列に流す（既定: CPU の数。上限 6）
# テストは既定で並列に流す。組ごとのログは build/logs/test_shard_<i>.log（docs/how-to-test.md の 4）。
# 環境変数 GODOT で Godot 実行ファイルを指定できる（既定: godot）。
# 環境変数 GODOT_TIMEOUT で Godot 1 回の時間切れ（秒）を変えられる（既定: 600。直列のテストは 1500）。
# 環境変数 TEST_SHARD_TIMEOUT で並列のテストの 1 組の時間切れ（秒）を変えられる（既定: 600）。
# 環境変数 RELEASE_TAG（例 v0.2.1）があれば、export_presets.cfg と書き出しの版がそのタグと同じかも確かめる。
set -euo pipefail

cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
BUILD=0
FIX=0
JOBS=""
for arg in "$@"; do
  case "$arg" in
    --build) BUILD=1 ;;
    --fix) FIX=1 ;;
    --serial) JOBS=1 ;;
    --jobs=*) JOBS="${arg#--jobs=}" ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

if [ -z "$JOBS" ]; then
  JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
  if [ "$JOBS" -gt 6 ]; then
    JOBS=6
  fi
fi
# 上限は tests/framework/test_case.gd の MAX_SHARDS（組ごとにテスト用のポートの範囲を分ける）
if ! [[ "$JOBS" =~ ^[1-8]$ ]]; then
  echo "--jobs must be 1..8: $JOBS" >&2
  exit 2
fi

LOG_DIR="build/logs"
mkdir -p "$LOG_DIR"
mapfile -t GD_FILES < <(git ls-files --cached --others --exclude-standard '*.gd')

step() { printf '\n== %s ==\n' "$1"; }

# Godot はスクリプトエラーでも終了コード0を返すことがあるので、ログも検査する。
run_godot() {
  local name="$1"; shift
  local log="$LOG_DIR/$name.log"
  set +e
  timeout "${RUN_TIMEOUT:-${GODOT_TIMEOUT:-600}}" "$GODOT" "$@" >"$log" 2>&1
  local code=$?
  set -e
  cat "$log"
  if [ "$code" -ne 0 ]; then
    echo "[$name] godot exited with $code" >&2
    exit 1
  fi
  if grep -E "$GODOT_ERRORS" "$log" >/dev/null; then
    echo "[$name] errors found in godot output" >&2
    exit 1
  fi
}

GODOT_ERRORS='^(SCRIPT ERROR|ERROR|USER ERROR):|Parse Error|Failed to load script'

# テストを JOBS 個の Godot で並列に流す（tests/run_tests.gd --shard=i/JOBS）。組の分け方は
# tests/test_timings.json の実測。組ごとに user://（XDG_DATA_HOME）とテスト用のポートの範囲を分けるので、
# 同じプロファイル名の保存や部屋のポートが別の組とぶつからない。結果は tools/test_shards.py でまとめ、
# 直列と同じ「X passed, Y failed」を出す。1 組でも失敗・時間切れ・ログのエラーがあれば止める。
# 実時間を測るテスト（run_tests.gd の RUN_ALONE_FILES）は、組が全部終わってから 1 つで流す（alone）。
run_tests_parallel() {
  local jobs="$1"
  local dir="build/test-shards"
  rm -rf "$dir"
  local pids=()
  local i
  for i in $(seq 1 "$jobs"); do
    local data="$PWD/$dir/$i/data"
    mkdir -p "$data"
    rm -f "$LOG_DIR/test_shard_$i.log"
    XDG_DATA_HOME="$data" RULE_RELAY_TEST_DATA_HOME="$data" \
      timeout "${TEST_SHARD_TIMEOUT:-600}" "$GODOT" --headless --fixed-fps 60 \
      --script res://tests/run_tests.gd -- --shard="$i/$jobs" --timing-out="$PWD/$dir/$i/result.json" \
      >"$LOG_DIR/test_shard_$i.log" 2>&1 &
    pids+=("$!")
  done
  local failed=0
  local results=()
  for i in $(seq 1 "$jobs"); do
    wait "${pids[$((i - 1))]}" || echo "$?" >"$dir/$i/exit_code"
  done
  local alone="$PWD/$dir/alone"
  mkdir -p "$alone/data"
  rm -f "$LOG_DIR/test_shard_alone.log"
  XDG_DATA_HOME="$alone/data" RULE_RELAY_TEST_DATA_HOME="$alone/data" \
    timeout "${TEST_SHARD_TIMEOUT:-600}" "$GODOT" --headless --fixed-fps 60 \
    --script res://tests/run_tests.gd -- --alone --timing-out="$alone/result.json" \
    >"$LOG_DIR/test_shard_alone.log" 2>&1 || echo "$?" >"$alone/exit_code"
  for i in $(seq 1 "$jobs") alone; do
    local log="$LOG_DIR/test_shard_$i.log"
    local code
    code="$(cat "$dir/$i/exit_code" 2>/dev/null || echo 0)"
    results+=("$dir/$i/result.json")
    if [ "$code" -ne 0 ]; then
      failed=1
      if [ "$code" -eq 124 ]; then
        echo "[test shard $i/$jobs] timed out after ${TEST_SHARD_TIMEOUT:-600} s" >&2
      else
        echo "[test shard $i/$jobs] godot exited with $code" >&2
      fi
      if [ ! -s "$dir/$i/result.json" ]; then
        echo "--- last lines of $log ---" >&2
        tail -n 40 "$log" >&2
      fi
    fi
    # 失敗したテストと、その理由（字下げした「- 」の行）
    awk '/^FAIL /{show=1; print; next} show && /^     - /{print; next} {show=0}' "$log" >&2
    if grep -E "$GODOT_ERRORS" "$log" >&2; then
      echo "[test shard $i/$jobs] errors found in godot output ($log)" >&2
      failed=1
    fi
  done
  python3 tools/test_shards.py summary "${results[@]}" || failed=1
  if [ "$failed" -ne 0 ]; then
    echo "[test] failed. logs: $LOG_DIR/test_shard_*.log" >&2
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

step "no steam in the contest build (source)"
python3 tools/check_no_steam.py --source

step "sound budget (tools/sfx)"
python3 -m unittest discover -s tools/sfx -p 'test_*.py'

step "app version (export_presets.cfg)"
# Mac と Windows の版がそろっているか（タグの書き出しでは CI がタグと同じかも確かめる。tools/release_version.py）
python3 -m unittest discover -s tools -p 'test_release_*.py'
python3 tools/release_version.py check ${RELEASE_TAG:+--tag "$RELEASE_TAG"}

step "import"
run_godot import --headless --import

step "static"
run_godot static --headless --script res://tools/check_scripts.gd

if [ "$JOBS" -eq 1 ]; then
  step "test (serial)"
  RUN_TIMEOUT="${GODOT_TIMEOUT:-1500}" run_godot test --headless --fixed-fps 60 --script res://tests/run_tests.gd
else
  step "test ($JOBS parallel shards)"
  run_tests_parallel "$JOBS"
fi

step "smoke (main scene, 180 frames)"
run_godot smoke --headless --fixed-fps 60 --quit-after 180

step "smoke (solo / host, 300 frames)"
run_godot smoke_solo --headless --fixed-fps 60 --quit-after 300 -- --solo --profile=zz_smoke
run_godot smoke_host --headless --fixed-fps 60 --quit-after 300 -- --host=24991 --profile=zz_smoke

if [ "$BUILD" -eq 1 ]; then
  step "build (Windows Desktop)"
  mkdir -p build/windows
  run_godot export --headless --export-release "Windows Desktop" build/windows/rule-relay.exe
  test -s build/windows/rule-relay.exe
  ls -la build/windows
  step "build (macOS, Intel + Apple Silicon)"
  mkdir -p build/macos
  run_godot export_macos --headless --export-release "macOS" build/macos/rule-relay.zip
  test -s build/macos/rule-relay.zip
  ls -la build/macos
  step "build (Linux x86_64 / Steam Deck)"
  mkdir -p build/linux
  run_godot export_linux --headless --export-release "Linux" build/linux/rule-relay.x86_64
  test -s build/linux/rule-relay.x86_64
  ls -la build/linux
  step "no steam in the contest build (exported files)"
  python3 tools/check_no_steam.py build/windows/rule-relay.exe build/macos/rule-relay.zip \
    build/linux/rule-relay.x86_64
  step "app version (exported exe / Mac Info.plist)"
  python3 tools/release_version.py check --exported ${RELEASE_TAG:+--tag "$RELEASE_TAG"}
  step "submission ZIP (LICENSES / secrets / sources / no steam)"
  # 提出用の ZIP（Windows・Mac・Linux）を build/submission/ に作って中身を確かめる（docs/submission/checklist.md）。
  # GitHub Release の ZIP も同じ作り方と検査で作る（.github/workflows/ci.yml の release ジョブ）
  python3 tools/check_submission.py --godot "$GODOT"
  step "smoke (exported Linux build, solo, 300 frames)"
  GODOT="build/linux/rule-relay.x86_64" run_godot smoke_linux_build --headless --quit-after 300 \
    -- --solo --profile=zz_smoke
fi

printf '\nall checks passed\n'
