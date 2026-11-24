#!/usr/bin/env bash
# 重い場面の性能を測る（tools/perf_bench.gd。結果と読み方は docs/reports/2026-11-24-performance.md）。
#   tools/perf_bench.sh                       全部の場面を 10 秒ずつ（1280x720）
#   tools/perf_bench.sh hub coop4             選んだ場面だけ
#   tools/perf_bench.sh --seconds=20 ...      1 場面の長さ（秒。--fixed-fps 60 なので 60×秒 コマ）
#   tools/perf_bench.sh --quality=low ...     画質の段階（low / medium / high。省略か none ならゲームが選んだまま）
#   tools/perf_bench.sh --out=build/perf/x    結果の置き場所（既定 build/perf/<画質>）
#   tools/perf_bench.sh --headless ...        描かずに CPU だけを測る（描画の数は 0 になる。スクリプト・物理・
#                                             アニメーションの重さを、lavapipe の描画待ちを含めずに見る）
#   tools/perf_bench.sh --size=640x360 ...    画面の大きさ（既定 1280x720。描画の呼び出し回数と三角形の数は
#                                             大きさによらないので、CPU で描く lavapipe では小さくすると速く終わる）
# 出力: <out>/<scene>.json と、表（<out>/summary.md）。build/ は .gitignore 済み。
# 必要なもの: Godot 4.6.3（環境変数 GODOT。既定 godot）・xvfb-run・Mesa の lavapipe（Vulkan のソフトウェア描画）。
# lavapipe は CPU で描くので、フレーム時間の絶対値は実機の GPU と比べられない。描画の呼び出し回数・三角形の数・
# ノードの数・CPU（process）と物理の時間を比べる。
set -euo pipefail

cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
SECONDS_PER_SCENE=10
QUALITY=none
SIZE=1280x720
HEADLESS=0
OUT=""
SCENES=()
ALL_SCENES=(hub long_expedition w7_summit_6 w6_peak_bells w4_herd_path o2_5 coop4 range_lend)
for arg in "$@"; do
  case "$arg" in
    --seconds=*) SECONDS_PER_SCENE="${arg#--seconds=}" ;;
    --quality=*) QUALITY="${arg#--quality=}" ;;
    --out=*) OUT="${arg#--out=}" ;;
    --size=*) SIZE="${arg#--size=}" ;;
    --headless) HEADLESS=1 ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) SCENES+=("$arg") ;;
  esac
done
if [ "${#SCENES[@]}" -eq 0 ]; then
  SCENES=("${ALL_SCENES[@]}")
fi
OUT="${OUT:-build/perf/$QUALITY}"
mkdir -p "$OUT"
ICD="${VK_ICD_FILENAMES:-/usr/share/vulkan/icd.d/lvp_icd.json}"

for scene in "${SCENES[@]}"; do
  echo "== $scene ($QUALITY, ${SECONDS_PER_SCENE}s, $SIZE) =="
  # 協力の場面は参加者の進行（user://）を作って消すので、ほかの Godot と分ける
  data="$PWD/$OUT/data-$scene"
  mkdir -p "$data"
  set +e
  if [ "$HEADLESS" -eq 1 ]; then
    XDG_DATA_HOME="$data" timeout 900 "$GODOT" --headless --fixed-fps 60 \
      --script res://tools/perf_bench.gd -- "$scene" "$SECONDS_PER_SCENE" "$PWD/$OUT/$scene.json" "$QUALITY" \
      >"$OUT/$scene.log" 2>&1
  else
    XDG_DATA_HOME="$data" VK_ICD_FILENAMES="$ICD" timeout 900 xvfb-run -a -s "-screen 0 ${SIZE}x24" \
      "$GODOT" --rendering-driver vulkan --resolution "$SIZE" --fixed-fps 60 \
      --script res://tools/perf_bench.gd -- "$scene" "$SECONDS_PER_SCENE" "$PWD/$OUT/$scene.json" "$QUALITY" \
      >"$OUT/$scene.log" 2>&1
  fi
  code=$?
  set -e
  grep -E '^perf_bench:|SCRIPT ERROR|^ERROR' "$OUT/$scene.log" | head -n 20 || true
  if [ "$code" -ne 0 ] || [ ! -s "$OUT/$scene.json" ]; then
    echo "[$scene] failed (exit $code). log: $OUT/$scene.log" >&2
    exit 1
  fi
done
python3 - "$OUT" "${SCENES[@]}" <<'PY' | tee "$OUT/summary.md"
import json, sys
out, scenes = sys.argv[1], sys.argv[2:]
cols = ["scene", "frame avg/p95/p99 ms", "process avg/p99 ms", "physics avg/p99 ms",
        "draw calls avg/max", "objects avg", "primitives avg", "nodes", "VRAM MB", "static MB"]
print("| " + " | ".join(cols) + " |")
print("|" + "---|" * len(cols))
for s in scenes:
    r = json.load(open(f"{out}/{s}.json"))
    f, p, ph = r["frame_ms"], r["process_ms"], r["physics_ms"]
    row = [s, f"{f['avg']:.1f} / {f['p95']:.1f} / {f['p99']:.1f}",
           f"{p['avg']:.2f} / {p['p99']:.2f}", f"{ph['avg']:.2f} / {ph['p99']:.2f}",
           f"{r['draw_calls']['avg']:.0f} / {r['draw_calls']['max']:.0f}",
           f"{r['objects']['avg']:.0f}", f"{r['primitives']['avg']:.0f}", str(r["nodes"]),
           f"{r['video_mem_mb']:.0f}", f"{r['static_mem_mb']:.0f}"]
    print("| " + " | ".join(row) + " |")
for s in scenes:
    r = json.load(open(f"{out}/{s}.json"))
    extra = {k: r[k] for k in ("load_ms", "range_commit_ms", "range_cells", "net_frame_bytes",
                               "net_host_upload_kbps") if k in r}
    print(f"\n- {s}: {json.dumps(extra, ensure_ascii=False)} counts={json.dumps(r['scene_counts'])}")
PY
