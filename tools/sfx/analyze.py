"""効果音の測定: 長さ・ピーク・RMS・スペクトルの重心・4kHz 以上の割合・主な周波数。

    python3 tools/sfx/analyze.py            # 表を出す
「高すぎる・耳障り」を数値で避けるための確認に使う（基準は tools/sfx/test_sfx.py）。
"""

import wave
from pathlib import Path

import numpy as np

SFX = Path(__file__).resolve().parents[2] / "assets" / "audio" / "sfx"


def load(path):
    with wave.open(str(path)) as w:
        sr = w.getframerate()
        data = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(float) / 32768
    return data, sr


def measure(path):
    x, sr = load(path)
    spectrum = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    freqs = np.fft.rfftfreq(len(x), 1 / sr)
    power = spectrum**2
    total = np.sum(power) + 1e-12
    centroid = float(np.sum(freqs * power) / total)
    high = float(np.sum(power[freqs >= 4000]) / total)
    harsh = float(np.sum(power[(freqs >= 2000) & (freqs <= 5000)]) / total)
    dominant = float(freqs[np.argmax(spectrum * (freqs > 40))])
    # A 特性（人の耳の感度）で重みを付けたうえで、250Hz 以上にあるエネルギーの割合。
    # ノートPCの小さなスピーカーは 200Hz 付近より下をほとんど鳴らせないので、低い音でも半分以上はここに欲しい
    weighted = power * a_weight(freqs) ** 2
    audible = float(np.sum(weighted[freqs >= 250]) / (np.sum(weighted) + 1e-12))
    return {
        "name": path.stem,
        "ms": len(x) / sr * 1000,
        "peak_db": 20 * np.log10(np.max(np.abs(x)) + 1e-12),
        "rms_db": 20 * np.log10(np.sqrt(np.mean(x**2)) + 1e-12),
        "centroid_hz": centroid,
        "high_ratio": high,
        "harsh_ratio": harsh,
        "dominant_hz": dominant,
        "small_speaker": audible,
    }


def a_weight(f):
    """IEC 61672 の A 特性（振幅）。"""
    f2 = np.maximum(f, 1.0) ** 2
    num = (12194.0**2) * f2**2
    den = (f2 + 20.6**2) * np.sqrt((f2 + 107.7**2) * (f2 + 737.9**2)) * (f2 + 12194.0**2)
    return num / den / 0.794


def main():
    print(
        f"{'name':14} {'ms':>6} {'peak':>6} {'rms':>6} {'centroid':>9} {'>4k':>6} {'2-5k':>6}"
        f" {'main':>7} {'>250Hz(A)':>10}"
    )
    for path in sorted(SFX.glob("*.wav")):
        m = measure(path)
        print(
            f"{m['name']:14} {m['ms']:6.0f} {m['peak_db']:6.1f} {m['rms_db']:6.1f} "
            f"{m['centroid_hz']:9.0f} {m['high_ratio']:6.1%} {m['harsh_ratio']:6.1%} {m['dominant_hz']:7.0f}"
            f" {m['small_speaker']:10.0%}"
        )


if __name__ == "__main__":
    main()
