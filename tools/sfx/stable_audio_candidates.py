"""Stable Audio 3 で生成した効果音の候補を、ゲームの効果音と同じ形にそろえて測る（聴き比べ用。assets/ には触らない）。

    uv run --with numpy --with scipy --with soundfile python tools/sfx/stable_audio_candidates.py ~/AudioStudio
    uv run --with numpy --with scipy --with soundfile python tools/sfx/stable_audio_candidates.py ~/AudioStudio --round 2   # 3 も同じ

入力: <dir>/sfx_<イベント>_v<n>.wav（2回目は sfx2_、3回目は sfx3_<イベント>_v<n>.wav。44.1kHz 24bit ステレオ、.json に prompt・seed）
出力: art/audio/stable-audio/sfx/<イベント>_<n>.wav（2回目は sfx2/、3回目は sfx3/）。16bit モノラル 44.1kHz と measurements.json
加工: モノラルにする → build_sfx.finish と同じフィルター（150Hz 未満を切る。衝撃音と鐘は 45Hz 未満だけ。9kHz より上を弱める）
      （2回目・3回目は、イベントごとに ROUND2_LOWPASS・ROUND3_LOWPASS の周波数でさらにローパス）
      → 頭の無音を切る（ピークから −40dB を最初に超える 3ms 前から）→ 長さの上限で切って 15ms で消す
      → ピークをそろえる（ホバー −12dBFS、UI −9dBFS、ほか −4dBFS。UI はゲームの音より小さく）
基準は tools/sfx/test_sfx.py と同じ。外れても消さず、印を付けるだけ。
"""

import json
import sys
import wave
from pathlib import Path

import numpy as np
import soundfile as sf

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analyze
import build_sfx

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "art" / "audio" / "stable-audio" / "sfx"
EVENTS = [
    "ui_hover", "ui_select", "ui_confirm", "ui_cancel", "ui_open", "ui_close", "ui_pick", "ui_drop", "ui_error",
    "radial_open", "lend", "lend_range", "recall", "prohibit",
    "receive_wood", "receive_stone", "receive_grass", "receive_creature",
    "block_jump", "block_land", "block_step", "bell", "player_jump", "player_land", "footstep", "save", "goal",
]
# 2回目（2026-11-20）: 1回目で基準を外れたイベントだけを、seed を変えて 3 つずつ作り直す
ROUND2_EVENTS = [
    # こもっていた → アタックをはっきり
    "ui_select", "ui_confirm", "ui_close", "ui_drop", "ui_error", "prohibit", "receive_wood", "receive_creature",
    "block_land",
    # シャーっと鳴っていた → 高域を抑える
    "ui_cancel", "ui_open", "ui_pick", "radial_open", "lend", "lend_range", "recall", "receive_grass",
    "player_land", "footstep",
    # 主な周波数が高すぎた → 低い鐘
    "bell", "goal",
]
# 2回目で、シャーっと鳴ったイベントに追加で掛けるローパス（Hz、4次）。生成で高域が抑えきれなかった分の加工
ROUND2_LOWPASS = {"ui_select": 3500, "ui_drop": 6000, "prohibit": 6000, "radial_open": 6000, "receive_grass": 3500, "player_land": 3500, "footstep": 3500}
# 3回目（2026-11-20）: 2回目でも合格が無かった4つと、新しい音2つ（dash、ui_notice）。seed を変えて 4 つずつ
ROUND3_EVENTS = ["ui_confirm", "ui_error", "ui_open", "bell", "dash", "ui_notice"]
ROUND3_LOWPASS = {"ui_error": 6000, "dash": 4500}
ROUNDS = {
    1: {"prefix": "sfx_", "out": OUT, "events": EVENTS, "count": 2, "lowpass": {}},
    2: {"prefix": "sfx2_", "out": OUT.parent / "sfx2", "events": ROUND2_EVENTS, "count": 3, "lowpass": ROUND2_LOWPASS},
    3: {"prefix": "sfx3_", "out": OUT.parent / "sfx3", "events": ROUND3_EVENTS, "count": 4, "lowpass": ROUND3_LOWPASS},
}
# test_sfx.py と同じ分類（footstep は footstep_1〜3 と同じ扱い）
IMPACTS = {"block_land", "block_jump"}
LONG = {"goal": 2300, "save": 1300, "bell": 2300, "dash": 500}  # dash は 3マスの突進（0.3〜0.5 秒）
UNPITCHED = {
    "player_jump", "player_land", "footstep", "block_step", "radial_open",
    "ui_hover", "ui_cancel", "ui_open", "ui_pick", "ui_drop",
    "dash",  # 風を切る音（音程の無い雑音）
}


def limit_ms(event):
    return LONG.get(event, 80 if event == "ui_hover" else 450 if event.startswith("ui_") else 800)


def peak_target_db(event):
    return -12.0 if event == "ui_hover" else -9.0 if event.startswith("ui_") else -4.0


def prepare(src, event, lowpass_hz=None):
    x, sr = sf.read(src, always_2d=True)
    assert sr == 44100, sr
    x = x.mean(axis=1)
    x = build_sfx.highpass(x, 45 if event in IMPACTS | {"bell"} else 150)
    x = build_sfx.lowpass(x, 9000, order=2)
    if lowpass_hz:
        x = build_sfx.lowpass(x, lowpass_hz, order=4)
    peak = np.max(np.abs(x))
    start = max(0, int(np.argmax(np.abs(x) > peak * 10 ** (-40 / 20))) - int(0.003 * sr))
    x = x[start:]
    pre = min(len(x), int(0.003 * sr))
    x[:pre] *= np.linspace(0, 1, pre)  # 無音の部分だけを丸める（当たりは削らない）
    x = x[: int(limit_ms(event) / 1000 * sr)].copy()
    fade = min(len(x), int(0.015 * sr))
    x[-fade:] *= np.linspace(1, 0, fade)
    x *= 10 ** (peak_target_db(event) / 20) / (np.max(np.abs(x)) + 1e-12)
    return x, sr, start / sr


def failures(event, m):
    bad = []
    if m["peak_db"] > -2.9:
        bad.append("peak")
    if event not in UNPITCHED and m["dominant_hz"] >= 1100:
        bad.append("main≥1100Hz")
    if m["centroid_hz"] >= 2600:
        bad.append("centroid")
    if m["high_ratio"] >= 0.22:
        bad.append(">4k")
    if m["sizzle_ratio"] >= 0.015:
        bad.append(">9k")
    if m["harsh_ratio"] >= 0.55:
        bad.append("2-5k")
    if m["clarity"] < (0.15 if event in IMPACTS else 0.25):
        bad.append("muffled")
    if m["small_speaker"] < (0.4 if event in IMPACTS else 0.6):
        bad.append("small-speaker")
    if m["ms"] > limit_ms(event) + 0.5:
        bad.append("length")
    return bad


def main(src_dir, round_no=1):
    cfg = ROUNDS[round_no]
    out = cfg["out"]
    out.mkdir(parents=True, exist_ok=True)
    rows = []
    for event in cfg["events"]:
        for n in range(1, cfg["count"] + 1):
            src = Path(src_dir) / f"{cfg['prefix']}{event}_v{n}.wav"
            meta = json.loads(Path(f"{src}.json").read_text())
            lp = cfg["lowpass"].get(event)
            x, sr, cut = prepare(src, event, lp)
            dst = out / f"{event}_{n}.wav"
            with wave.open(str(dst), "wb") as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(sr)
                w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())
            m = analyze.measure(dst)
            m = {k: (round(float(v), 4) if not isinstance(v, str) else v) for k, v in m.items()}
            rows.append({
                "file": dst.name, "event": event, "n": n,
                "seed": meta.get("seed"), "prompt": meta.get("prompt_used") or meta.get("prompt"),
                "cfg": meta.get("cfg"), "negative_prompt": meta.get("negative_prompt"), "extra_lowpass_hz": lp,
                "generated_seconds": meta.get("duration_seconds") or meta.get("seconds"),
                "head_cut_ms": round(cut * 1000, 1), "limit_ms": limit_ms(event),
                "measure": m, "fails": failures(event, m),
            })
            print(f"{dst.name:24} {m['ms']:6.0f}ms main {m['dominant_hz']:6.0f} clear {m['clarity']:5.0%}"
                  f" >9k {m['sizzle_ratio']:6.2%} {' '.join(rows[-1]['fails']) or 'ok'}")
    (out / "measurements.json").write_text(json.dumps(rows, ensure_ascii=False, indent=1) + "\n")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("src_dir", nargs="?", default=str(Path.home() / "AudioStudio"))
    parser.add_argument("--round", type=int, choices=sorted(ROUNDS), default=1)
    args = parser.parse_args()
    main(args.src_dir, args.round)
