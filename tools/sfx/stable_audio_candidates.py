"""Stable Audio 3 で生成した効果音の候補を、ゲームの効果音と同じ形にそろえて測る（聴き比べ用。assets/ には触らない）。

    uv run --with numpy --with scipy --with soundfile python tools/sfx/stable_audio_candidates.py ~/AudioStudio
    uv run --with numpy --with scipy --with soundfile python tools/sfx/stable_audio_candidates.py ~/AudioStudio --round 2   # 3・4 も同じ

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
# 4回目（2026-11-21）: 足音とホットバーの音。鳴り終わるまでが長いと、次の音と重なって使えない。
# 頭の1打だけを切り出し、短いフェードで終える（ONE_SHOT）。seed を変えて 5 つずつ
ROUND4_EVENTS = ["footstep", "ui_select"]
ROUND4_LOWPASS = {"footstep": 6000}
ONE_SHOT = {"footstep": 120, "ui_select": 100}  # イベント → −20dB まで落ちる時間の上限（ms）
MAIN_RANGE = {"ui_select": (200, 600)}
# 4回目: 生成した音の音程を下げる（半音）。テープを遅く回すのと同じで、長さは 2^(半音/12) 倍に伸びる。
# ui_select は、頭をはっきりさせると 680〜700Hz になり、低くさせるとこもった。ゲームで音程を上げて鳴らすので、元を下げておく
PITCH_SEMITONES = {"ui_select": -3}  # 主な周波数の目安（ゲームで最大 +19 半音上げるので、元は低め）
ROUNDS = {
    1: {"prefix": "sfx_", "out": OUT, "events": EVENTS, "count": 2, "lowpass": {}},
    2: {"prefix": "sfx2_", "out": OUT.parent / "sfx2", "events": ROUND2_EVENTS, "count": 3, "lowpass": ROUND2_LOWPASS},
    3: {"prefix": "sfx3_", "out": OUT.parent / "sfx3", "events": ROUND3_EVENTS, "count": 4, "lowpass": ROUND3_LOWPASS},
    4: {"prefix": "sfx4_", "out": OUT.parent / "sfx4", "events": ROUND4_EVENTS, "count": 5, "lowpass": ROUND4_LOWPASS,
        "one_shot": True},
}
# test_sfx.py と同じ分類（footstep は footstep_1〜3 と同じ扱い）
IMPACTS = {"block_land", "block_jump"}
LONG = {"goal": 2300, "save": 1300, "bell": 2300, "dash": 500}  # dash は 3マスの突進（0.3〜0.5 秒）
UNPITCHED = {
    "player_jump", "player_land", "footstep", "block_step", "radial_open",
    "ui_hover", "ui_cancel", "ui_open", "ui_pick", "ui_drop",
    "dash",  # 風を切る音（音程の無い雑音）
}


def limit_ms(event, one_shot=False):
    if one_shot:
        return ONE_SHOT[event] + 60  # −20dB までの上限＋余韻（フェードまで含めた長さ）
    return LONG.get(event, 80 if event == "ui_hover" else 450 if event.startswith("ui_") else 800)


def peak_target_db(event):
    return -12.0 if event == "ui_hover" else -9.0 if event.startswith("ui_") else -4.0


def envelope_db(x, sr, window_ms=2.0):
    """2ms の RMS の包絡（ピークを 0dB とした dB）。"""
    n = max(1, int(window_ms / 1000 * sr))
    rms = np.sqrt(np.convolve(x**2, np.ones(n) / n, mode="same"))
    return 20 * np.log10(rms / (np.max(rms) + 1e-12) + 1e-12)


def onset_index(x):
    """analyze.measure と同じ、音の始まり（ピークの 10% を最初に超えたところ）。"""
    return int(np.argmax(np.abs(x) > 0.1 * np.max(np.abs(x))))


def decay20_ms(x, sr):
    """音の始まりから、包絡が最後に −20dB 以上だったところまでの時間（ms）。次の音と重なるかの目安。"""
    env = envelope_db(x, sr)
    above = np.where(env >= -20)[0]
    return (above[-1] - onset_index(x)) / sr * 1000 if len(above) else 0.0


def hit_starts(x, sr):
    """打音の始まりの位置。包絡が −20dB 未満に下がってから、また −12dB 以上に上がったら次の打音と数える。"""
    env = envelope_db(x, sr)
    starts, armed = [], True
    for i, v in enumerate(env):
        if armed and v >= -12:
            starts.append(i)
            armed = False
        elif not armed and v < -20:
            armed = True
    return starts


def first_hit(x, sr, limit_ms):
    """頭の1打だけを残す。2打目の手前、包絡が −30dB を下回ったところ、または上限（ms）の早いほうで切る。
    切る点で 10ms のフェードで終える。戻り値: (音, 切った理由, 切る前の −20dB までの時間)"""
    natural = decay20_ms(x, sr)
    env = envelope_db(x, sr)
    peak = int(np.argmax(env))
    starts = hit_starts(x, sr)
    ends = {"limit": onset_index(x) + int(limit_ms / 1000 * sr)}
    below = np.where(env[peak:] < -30)[0]
    if len(below):
        ends["-30dB"] = peak + int(below[0])
    later = [s_ for s_ in starts if s_ > peak]
    if later:
        # 2打目の始まりから少し戻った、いちばん小さいところ
        a = peak + int(np.argmin(env[peak:later[0]]))
        ends["2nd hit"] = a
    reason = min(ends, key=ends.get)
    end = min(len(x), ends[reason])
    y = x[:end].copy()
    fade = min(len(y), int(0.010 * sr))
    y[-fade:] *= np.linspace(1, 0, fade)
    return y, reason, natural


def prepare(src, event, lowpass_hz=None, one_shot=False):
    x, sr = sf.read(src, always_2d=True)
    assert sr == 44100, sr
    x = x.mean(axis=1)
    if one_shot and event in PITCH_SEMITONES:
        from fractions import Fraction

        from scipy import signal

        ratio = Fraction(2 ** (-PITCH_SEMITONES[event] / 12)).limit_denominator(200)
        x = signal.resample_poly(x, ratio.numerator, ratio.denominator)
    x = build_sfx.highpass(x, 45 if event in IMPACTS | {"bell"} else 150)
    x = build_sfx.lowpass(x, 9000, order=2)
    if lowpass_hz:
        x = build_sfx.lowpass(x, lowpass_hz, order=4)
    peak = np.max(np.abs(x))
    start = max(0, int(np.argmax(np.abs(x) > peak * 10 ** (-40 / 20))) - int(0.003 * sr))
    x = x[start:]
    pre = min(len(x), int(0.003 * sr))
    x[:pre] *= np.linspace(0, 1, pre)  # 無音の部分だけを丸める（当たりは削らない）
    info = {"pitch_semitones": PITCH_SEMITONES.get(event)} if one_shot else {}
    if one_shot:
        x, info["cut"], info["natural_decay20_ms"] = first_hit(x, sr, ONE_SHOT[event])
    else:
        x = x[: int(limit_ms(event) / 1000 * sr)].copy()
        fade = min(len(x), int(0.015 * sr))
        x[-fade:] *= np.linspace(1, 0, fade)
    x *= 10 ** (peak_target_db(event) / 20) / (np.max(np.abs(x)) + 1e-12)
    return (x, sr, start / sr, info) if one_shot else (x, sr, start / sr)


def failures(event, m, one_shot=False):
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
    if m["ms"] > limit_ms(event, one_shot) + 0.5:
        bad.append("length")
    if not one_shot:
        return bad
    if event in MAIN_RANGE and not MAIN_RANGE[event][0] <= m["dominant_hz"] <= MAIN_RANGE[event][1]:
        bad.append("main-range")
    if m["decay20_ms"] > ONE_SHOT[event]:
        bad.append("decay")
    if m["hits"] != 1:
        bad.append("hits")
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
            extra = {}
            if cfg.get("one_shot"):
                x, sr, cut, extra = prepare(src, event, lp, one_shot=True)
            else:
                x, sr, cut = prepare(src, event, lp)
            dst = out / f"{event}_{n}.wav"
            with wave.open(str(dst), "wb") as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(sr)
                w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())
            m = analyze.measure(dst)
            if cfg.get("one_shot"):
                xs, _ = analyze.load(dst)
                m["decay20_ms"] = decay20_ms(xs, sr)
                m["hits"] = len(hit_starts(xs, sr))
            m = {k: (round(float(v), 4) if not isinstance(v, str) else v) for k, v in m.items()}
            rows.append({
                "file": dst.name, "event": event, "n": n,
                "seed": meta.get("seed"), "prompt": meta.get("prompt_used") or meta.get("prompt"),
                "cfg": meta.get("cfg"), "negative_prompt": meta.get("negative_prompt"), "extra_lowpass_hz": lp,
                "created": meta.get("created"), **extra,
                "generated_seconds": meta.get("duration_seconds") or meta.get("seconds"),
                "head_cut_ms": round(cut * 1000, 1), "limit_ms": limit_ms(event, bool(cfg.get("one_shot"))),
                "measure": m, "fails": failures(event, m, bool(cfg.get("one_shot"))),
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
