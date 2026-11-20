"""合成した効果音と実録音を、同じ物差しで比べる（「AI が作った音っぽい」の原因を数字で探す）。

    python3 tools/sfx/compare_realism.py <実録音の WAV があるフォルダ> [合成音のフォルダ]

合成音が機械的に聞こえる理由として知られているものを、1つずつ測る:
- flatness: スペクトルの平坦さ（0〜1）。雑音・密な倍音が多いほど大きい。合成音は数本の正弦波で、谷が深い
- flux: 時間とともに音色が変わる量。実際の物は鳴っている間に音色が動く。合成音は形が止まっている
- floor_db: いちばん静かな部分の大きさ（ピーク比）。実録音には部屋の空気・機材の雑音がある。合成音は完全な無音（-120 dB）
- jitter: 音程の揺れ（%）。人がはじく・吹く音は少し揺れる。合成音は完全に一定
- peaks: 長い目で見たスペクトルの山の数。実物は山が多く、合成音は少ない
- decay_r2: 減衰を dB で直線にあてはめた当てはまり（1 に近いほど、教科書どおりの指数減衰＝機械的）
- silence: 完全な無音（-80 dB 未満）の割合。録音には必ず空気の雑音があり、ほぼ 0
"""

import sys
import wave
from pathlib import Path

import numpy as np
from scipy import signal

DEFAULT_SYNTH = Path(__file__).resolve().parents[2] / "assets" / "audio" / "sfx"


def load(path):
    with wave.open(str(path)) as w:
        sr = w.getframerate()
        ch = w.getnchannels()
        raw = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(float) / 32768
    return raw.reshape(-1, ch).mean(axis=1), sr


def frames(x, size=1024, hop=512):
    n = max(1, 1 + (len(x) - size) // hop)
    return np.stack([x[i * hop : i * hop + size] for i in range(n) if i * hop + size <= len(x)])


def measure(x, sr):
    x = x / (np.max(np.abs(x)) + 1e-12)
    fr = frames(x)
    win = np.hanning(fr.shape[1])
    spec = np.abs(np.fft.rfft(fr * win, axis=1)) ** 2 + 1e-12
    energy = spec.sum(axis=1)
    loud = energy > energy.max() * 1e-3
    flat = np.exp(np.mean(np.log(spec), axis=1)) / np.mean(spec, axis=1)
    norm = spec / spec.sum(axis=1, keepdims=True)
    flux = np.sum(np.abs(np.diff(norm, axis=0)), axis=1) if len(norm) > 1 else np.zeros(1)
    rms = np.sqrt(np.mean(fr**2, axis=1)) + 1e-9
    floor_db = 20 * np.log10(np.percentile(rms, 10) / rms.max())
    long_spec = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    long_db = 10 * np.log10(long_spec / long_spec.max() + 1e-12)
    peaks, _ = signal.find_peaks(long_db, height=-40, distance=max(1, int(len(long_db) / 2000)))
    return {
        "flatness": float(np.median(flat[loud])) if loud.any() else 0.0,
        "flux": float(np.median(flux[loud[1:]])) if len(flux) > 1 and loud[1:].any() else 0.0,
        "floor_db": float(max(floor_db, -120)),
        "jitter": jitter(x, sr),
        "peaks": int(len(peaks)),
        "decay_r2": decay_r2(rms),
        "silence": float(np.mean(np.abs(x) < 1e-4)),
    }


def jitter(x, sr):
    """音程の揺れ（%）。自己相関で 20ms ごとの基本周波数を求め、その変動係数。音程が無ければ nan。"""
    size = int(0.04 * sr)
    hop = int(0.02 * sr)
    f0s = []
    for i in range(0, len(x) - size, hop):
        seg = x[i : i + size]
        if np.sqrt(np.mean(seg**2)) < 0.05:
            continue
        ac = np.correlate(seg, seg, "full")[size - 1 :]
        lo, hi = int(sr / 1200), int(sr / 80)
        if hi >= len(ac):
            continue
        lag = lo + int(np.argmax(ac[lo:hi]))
        if ac[lag] > 0.5 * ac[0]:
            f0s.append(sr / lag)
    if len(f0s) < 4:
        return float("nan")
    f0s = np.array(f0s)
    return float(np.std(f0s) / np.mean(f0s) * 100)


def decay_r2(rms):
    """ピークの後の減衰を dB で直線にあてはめた決定係数。"""
    i = int(np.argmax(rms))
    db = 20 * np.log10(rms[i:] / rms[i])
    keep = db > -50
    db = db[keep]
    if len(db) < 5:
        return float("nan")
    t = np.arange(len(db))
    a, b = np.polyfit(t, db, 1)
    pred = a * t + b
    ss = np.sum((db - db.mean()) ** 2) + 1e-12
    return float(1 - np.sum((db - pred) ** 2) / ss)


def summarize(folder):
    rows = []
    for p in sorted(Path(folder).glob("*.wav")):
        x, sr = load(p)
        if len(x) < 2048:
            continue
        rows.append(measure(x, sr))
    keys = rows[0].keys()
    return {k: np.nanmedian([r[k] for r in rows]) for k in keys}, len(rows)


def main():
    real_dir = Path(sys.argv[1])
    synth_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_SYNTH
    real, n_real = summarize(real_dir)
    synth, n_synth = summarize(synth_dir)
    print(f"{'指標':10} {'実録音(' + str(n_real) + ')':>14} {'合成(' + str(n_synth) + ')':>12}")
    for k in real:
        print(f"{k:10} {real[k]:14.4g} {synth[k]:12.4g}")


if __name__ == "__main__":
    main()
