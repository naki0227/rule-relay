#!/usr/bin/env bash
# ゲームプレイ動画の素材を撮る（docs/submission/video-capture.md）。
#   tools/capture_video.sh                  全部のクリップを 1280x720・30 fps で撮る
#   tools/capture_video.sh range_lend ...   選んだクリップだけ
#   tools/capture_video.sh --1080p ...      1920x1080 で撮る（ソフトウェア描画なので約 2 倍の時間）
#   tools/capture_video.sh --stills ...     撮ったあと、各クリップの代表の 1 枚を docs/images/video/ へ写す
# 出力（build/ は .gitignore 済み。コミットしない）:
#   build/video/<clip>.mp4                  H.264 ＋ AAC（ffmpeg があるとき）
#   build/video/<clip>/frames/%05d.png      使う範囲の PNG の連番（30 fps）
#   build/video/<clip>/<clip>.wav           同じ範囲の音（ゲームの BGM と効果音）
#   build/video/<clip>/still.png            代表の 1 枚（真ん中より少し後ろのフレーム）
# 必要なもの: Godot 4.6.3（環境変数 GODOT。既定 godot）・xvfb-run・Mesa の lavapipe（Vulkan のソフトウェア描画）、
# 動画にするなら ffmpeg（無ければ PNG と WAV だけ作る。入れ方は docs/submission/video-capture.md）。
set -euo pipefail

cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
WIDTH=1280
HEIGHT=720
STILLS=0
CLIPS=()
ALL_CLIPS=(hub_walk jump_lend creature_medal range_lend throw_arc coop_jumps clear_return)
for arg in "$@"; do
  case "$arg" in
    --1080p) WIDTH=1920; HEIGHT=1080 ;;
    --stills) STILLS=1 ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) CLIPS+=("$arg") ;;
  esac
done
if [ "${#CLIPS[@]}" -eq 0 ]; then
  CLIPS=("${ALL_CLIPS[@]}")
fi

ICD="${VK_ICD_FILENAMES:-/usr/share/vulkan/icd.d/lvp_icd.json}"
# Movie Maker の大きさは --resolution ではなく、プロジェクトの window_*_override（1600x900）で決まる。
# 撮る間だけ override.cfg で上書きし、終わったら必ず消す（提出の ZIP・コミットに入れない。
# 撮っている間は、同じ作業ツリーで tools/check.sh を走らせない）。
if [ -e override.cfg ]; then
  echo "override.cfg が既にあります。消してから撮ってください" >&2
  exit 1
fi
trap 'rm -f override.cfg' EXIT
cat >override.cfg <<CFG
[display]

window/size/window_width_override=$WIDTH
window/size/window_height_override=$HEIGHT
CFG
OUT="build/video"
mkdir -p "$OUT"
# 何千枚もの PNG を Godot に読み込ませない（読み込ませると --import が落ちる）
touch "$OUT/.gdignore"
HAVE_FFMPEG=0
if command -v ffmpeg >/dev/null 2>&1; then
  HAVE_FFMPEG=1
else
  echo "ffmpeg が見つかりません。PNG と WAV だけ作ります（mp4 にするには ffmpeg を入れる）" >&2
fi

for clip in "${CLIPS[@]}"; do
  dir="$OUT/$clip"
  rm -rf "$dir"
  mkdir -p "$dir/raw" "$dir/frames"
  echo "== $clip (${WIDTH}x${HEIGHT}) =="
  # Movie Maker は描いたフレームを全部 raw/ に書く。marks.txt に使う範囲（始まりと終わりの番号）が入る
  VK_ICD_FILENAMES="$ICD" xvfb-run -a -s "-screen 0 ${WIDTH}x${HEIGHT}x24" \
    "$GODOT" --rendering-driver vulkan --resolution "${WIDTH}x${HEIGHT}" --fixed-fps 30 \
    --write-movie "$dir/raw/frame.png" \
    --script res://tools/capture_video.gd -- "$clip" "$dir/marks.txt" >"$dir/godot.log" 2>&1 || true
  grep -E 'capture_video|WARNING: capture|SCRIPT ERROR' "$dir/godot.log" || true
  if [ ! -s "$dir/marks.txt" ]; then
    echo "[$clip] marks.txt がありません（$dir/godot.log を見る）" >&2
    exit 1
  fi
  read -r start end <"$dir/marks.txt"
  # 使う範囲だけを 00000.png から並べ直す（Movie Maker の名前は frame00000000.png）
  n=0
  for ((i = start; i < end; i++)); do
    src=$(printf '%s/raw/frame%08d.png' "$dir" "$i")
    [ -f "$src" ] || continue
    mv "$src" "$(printf '%s/frames/%05d.png' "$dir" "$n")"
    n=$((n + 1))
  done
  echo "[$clip] $n frames ($(awk "BEGIN{printf \"%.1f\", $n/30}") s)"
  pick=$(printf '%s/frames/%05d.png' "$dir" $((n * 3 / 5)))
  [ -f "$pick" ] && cp "$pick" "$dir/still.png"
  if [ "$HAVE_FFMPEG" -eq 1 ]; then
    ss=$(awk "BEGIN{printf \"%.4f\", $start/30}")
    len=$(awk "BEGIN{printf \"%.4f\", $n/30}")
    if [ -f "$dir/raw/frame.wav" ]; then
      ffmpeg -hide_banner -loglevel error -y -ss "$ss" -t "$len" -i "$dir/raw/frame.wav" \
        -c:a pcm_s16le "$dir/$clip.wav"
    fi
    audio=()
    [ -f "$dir/$clip.wav" ] && audio=(-i "$dir/$clip.wav" -c:a aac -b:a 192k)
    ffmpeg -hide_banner -loglevel error -y -framerate 30 -i "$dir/frames/%05d.png" "${audio[@]}" \
      -c:v libx264 -pix_fmt yuv420p -crf 18 -preset slow -movflags +faststart -shortest \
      "$OUT/$clip.mp4"
    echo "[$clip] -> $OUT/$clip.mp4"
  elif [ -f "$dir/raw/frame.wav" ]; then
    cp "$dir/raw/frame.wav" "$dir/$clip.full.wav"
    echo "[$clip] 音は $dir/$clip.full.wav（先頭 $start フレーム分の準備を含む。編集で切る）"
  fi
  rm -rf "$dir/raw"
  if [ "$STILLS" -eq 1 ] && [ -f "$dir/still.png" ]; then
    mkdir -p docs/images/video
    cp "$dir/still.png" "docs/images/video/$clip.png"
  fi
done
echo "done: $OUT"
