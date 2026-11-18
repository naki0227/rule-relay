"""効果音を合成して assets/audio/sfx/*.wav に書き出す（決定的・固定シード）。

    python3 tools/sfx/build_sfx.py

音の系統（全部をここから作り、統一感を出す。docs/sound-design.md）:
- 木: STK の ModalBar（Perry Cook）の Wood1 / Wood2 / Marimba の振動の比率と減衰を使ったモーダル合成。
  打った瞬間の短い雑音（マレットの当たり）を、やわらかく低域寄りに絞って足す
- 布・紙・草: 色付きの雑音（ピンク・ブラウン）を帯域通過させ、ゆっくり立ち上げる
- 音程: 主にハ長調の五音（C D E G A）の C4〜C5 付近。高い音（C6 以上）は使わない
- 仕上げ: 120Hz 未満を切り（低い衝撃音は除く）、4kHz 以上を弱め、短いやわらかい残響を足す
"""

import wave
from pathlib import Path

import numpy as np
from scipy import signal

SR = 44100
OUT = Path(__file__).resolve().parents[2] / "assets" / "audio" / "sfx"
RNG = np.random.default_rng(20261118)

# ハ長調の五音（Hz）。C4=261.63
NOTE = {
    "G3": 196.00, "A3": 220.00, "C4": 261.63, "D4": 293.66, "E4": 329.63,
    "G4": 392.00, "A4": 440.00, "C5": 523.25, "D5": 587.33, "E5": 659.25,
}

# STK ModalBar の値（比率、44.1kHz での極の半径、モードの重み）
MARIMBA = ([1.0, 3.99, 10.65], [0.9996, 0.9994, 0.9994], [0.04, 0.01, 0.01])
WOOD1 = ([1.0, 2.777, 7.378, 15.377], [0.996, 0.994, 0.994, 0.99], [0.04, 0.01, 0.01, 0.008])
WOOD2 = ([1.0, 1.777, 2.378, 3.377], [0.996, 0.994, 0.994, 0.99], [0.04, 0.01, 0.01, 0.008])


def t(seconds):
    return np.arange(int(seconds * SR)) / SR


def silence(seconds):
    return np.zeros(int(seconds * SR))


def modal(freq, preset, seconds, hardness=0.6, decay_scale=1.0):
    """叩いた棒・板の音。各モードは指数減衰する正弦波。高いモードは hardness で弱める。"""
    ratios, radii, gains = preset
    x = t(seconds)
    out = np.zeros_like(x)
    for ratio, radius, gain in zip(ratios, radii, gains):
        f = ratio * freq
        if f > 6000:  # 高すぎるモードは入れない（耳障りな高域を作らない）
            continue
        tau = -1.0 / (SR * np.log(radius)) * decay_scale
        weight = gain * (hardness ** (ratio > 1.5))
        out += weight * np.sin(2 * np.pi * f * x) * np.exp(-x / tau)
    # マレットの当たり: 3ms の雑音を 0.6〜3kHz に絞る（輪郭。小さなスピーカーでも聞こえる帯域）
    n_hit = int(0.003 * SR)
    hit = RNG.standard_normal(n_hit) * np.hanning(n_hit)
    hit = band(hit, 600, 3000) * 0.015 * hardness
    out[:n_hit] += hit[: len(out)]
    # 鳴っている途中で切ると「ぷつっ」と鳴るので、最後の 15ms を必ず消していく
    tail = min(len(out), int(0.015 * SR))
    out[-tail:] *= np.linspace(1.0, 0.0, tail) ** 2
    return out


def pitched_body(f0, f1, seconds, curve=1.0):
    """音程が f0 から f1 へ動く、やわらかい丸い音（正弦波＋少しの2倍音）。"""
    x = t(seconds)
    f = f0 + (f1 - f0) * (x / seconds) ** curve
    phase = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(phase) + 0.18 * np.sin(2 * phase)


def colored_noise(seconds, color="pink"):
    n = int(seconds * SR)
    white = RNG.standard_normal(n)
    spectrum = np.fft.rfft(white)
    freqs = np.fft.rfftfreq(n, 1 / SR)
    freqs[0] = 1.0
    power = 0.5 if color == "pink" else 1.0  # brown
    spectrum /= freqs**power
    out = np.fft.irfft(spectrum, n)
    return out / (np.max(np.abs(out)) + 1e-9)


def band(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, hi], btype="bandpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def lowpass(x, hz, order=2):
    sos = signal.butter(order, hz, btype="lowpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def highpass(x, hz, order=2):
    sos = signal.butter(order, hz, btype="highpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def envelope(n, attack, release, hold=0.0):
    """やわらかい立ち上がりと終わり（秒）。"""
    env = np.ones(n)
    a = max(1, int(attack * SR))
    r = max(1, int(release * SR))
    env[:a] = np.sin(np.linspace(0, np.pi / 2, a)) ** 2
    start = min(n, a + int(hold * SR))
    tail = np.linspace(1, 0, max(1, n - start)) ** 2
    env[start:] = tail[: n - start]
    if r < n:
        env[-r:] *= np.linspace(1, 0, r)
    return env


def place(base, sound, at):
    i = int(at * SR)
    end = min(len(base), i + len(sound))
    base[i:end] += sound[: end - i]
    return base


def soft_room(x, length=0.12, mix=0.12):
    """短いやわらかい残響（減衰する雑音のインパルス応答を低域寄りに絞る）。"""
    n = int(length * SR)
    ir = RNG.standard_normal(n) * np.exp(-np.arange(n) / (n / 5))
    ir = lowpass(ir, 2500)
    ir /= np.sum(np.abs(ir)) + 1e-9
    dry = np.concatenate([x, np.zeros(n)])
    wet = signal.fftconvolve(x, ir)
    wet = np.pad(wet, (0, max(0, len(dry) - len(wet))))[: len(dry)]
    return dry * (1 - mix) + wet * mix * 6.0


def finish(x, rms_db, keep_low=False, tilt_hz=4000):
    """仕上げ: 低域・高域の整理、端の処理、音量をそろえる（RMS 基準、ピークは -3dBFS 以下）。"""
    # 120Hz 未満を切る。低い衝撃音（keep_low）でも、聞こえない 45Hz 未満と直流は切る
    x = highpass(x, 45 if keep_low else 120)
    x = lowpass(x, tilt_hz, order=1)  # 高域をなだらかに弱める
    fade = int(0.004 * SR)
    x[:fade] *= np.linspace(0, 1, fade)
    x[-fade:] *= np.linspace(1, 0, fade)
    rms = np.sqrt(np.mean(x**2)) + 1e-12
    x *= 10 ** (rms_db / 20) / rms
    peak = np.max(np.abs(x))
    limit = 10 ** (-3 / 20)
    if peak > limit:
        x *= limit / peak
    return x


def write(name, x):
    OUT.mkdir(parents=True, exist_ok=True)
    data = np.clip(x, -1, 1)
    pcm = (data * 32767).astype(np.int16)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


# --- UI -----------------------------------------------------------------------


def ui_hover():
    """指したとき: ごく小さな木の「コッ」。目立たせない。"""
    x = modal(NOTE["C5"], WOOD2, 0.05, hardness=0.45)
    return finish(x, -34)


def ui_select():
    """ホットバーを選ぶ: やわらかいマリンバの「トッ」。"""
    x = modal(NOTE["G4"], MARIMBA, 0.16, hardness=0.55, decay_scale=1.2)
    return finish(soft_room(x, mix=0.08), -24)


def ui_confirm():
    """決定: 2音で上がる（G4→C5）。"""
    a = modal(NOTE["G4"], MARIMBA, 0.18, hardness=0.55)
    b = modal(NOTE["C5"], MARIMBA, 0.26, hardness=0.55, decay_scale=1.4)
    x = place(place(silence(0.30), a, 0.0), b * 1.1, 0.06)
    return finish(soft_room(x), -22)


def ui_cancel():
    """取り消し・閉じる: 2音で下がる（E4→C4）。控えめ。"""
    a = modal(NOTE["E4"], MARIMBA, 0.16, hardness=0.45)
    b = modal(NOTE["C4"], MARIMBA, 0.22, hardness=0.45)
    x = place(place(silence(0.26), a, 0.0), b, 0.06)
    return finish(soft_room(x), -25)


def ui_open():
    """持ち物・メニューを開く: 布をめくる音と、低い木の「トン」。"""
    rustle = band(colored_noise(0.22, "pink"), 350, 2200) * envelope(int(0.22 * SR), 0.05, 0.12)
    thump = modal(NOTE["C4"], WOOD2, 0.2, hardness=0.45)
    x = place(rustle * 0.5, thump * 6.0, 0.06)
    return finish(soft_room(x), -24)


def ui_close():
    """閉じる: 短い布の音と、さらに低い「トン」。"""
    rustle = band(colored_noise(0.16, "pink"), 300, 1800) * envelope(int(0.16 * SR), 0.02, 0.1)
    thump = modal(NOTE["A3"], WOOD2, 0.16, hardness=0.4)
    x = place(rustle * 0.5, thump * 6.0, 0.02)
    return finish(x, -26)


def ui_pick():
    """アイテムをつまむ: 小さな丸い「ポッ」（音程が少し下がる）。"""
    n = int(0.09 * SR)
    x = pitched_body(420, 300, 0.09, curve=0.5) * envelope(n, 0.004, 0.07)
    return finish(x, -25)


def ui_drop():
    """アイテムを置く: 木の札を置く「コトッ」。"""
    a = modal(NOTE["G4"], WOOD1, 0.12, hardness=0.55)
    b = modal(NOTE["C4"], WOOD2, 0.14, hardness=0.45)
    x = place(place(silence(0.16), a, 0.0), b * 0.8, 0.012)
    return finish(x, -22)


def ui_error():
    """できない・保存できない: ブザーにしない。低い木を2回軽くたたく（下がる）。"""
    a = modal(NOTE["G4"], WOOD2, 0.12, hardness=0.45)
    b = modal(NOTE["D4"], WOOD2, 0.16, hardness=0.45)
    x = place(place(silence(0.26), a, 0.0), b, 0.09)
    return finish(x, -24)


# --- 能力 ---------------------------------------------------------------------


def whoosh(seconds, lo0, hi0, lo1, hi1, attack=0.08):
    """帯域が動く柔らかい風の音。いくつかの帯域で通した雑音を、時間に沿って重みを移しながら混ぜる
    （帯域を切り替えた所でぷつっと鳴らないように）。"""
    n = int(seconds * SR)
    noise = colored_noise(seconds, "pink")
    steps = 8
    pos = np.linspace(0, steps - 1, n)
    out = np.zeros(n)
    for k in range(steps):
        u = k / (steps - 1)
        filtered = band(noise, lo0 + (lo1 - lo0) * u, hi0 + (hi1 - hi0) * u)
        weight = np.clip(1.0 - np.abs(pos - k), 0.0, 1.0)
        out += filtered * weight
    out = lowpass(out, 3000)
    return out * envelope(n, attack, seconds * 0.6)


def lend():
    """能力を渡す: ふわっと上がる風と、着いたところでやさしい音（E4・G4）。"""
    air = whoosh(0.28, 250, 900, 500, 1600)
    note_a = modal(NOTE["E4"], MARIMBA, 0.3, hardness=0.55, decay_scale=1.5)
    note_b = modal(NOTE["G4"], MARIMBA, 0.32, hardness=0.55, decay_scale=1.5)
    x = place(place(place(silence(0.5), air * 0.35, 0.0), note_a * 6, 0.16), note_b * 5, 0.2)
    return finish(soft_room(x, mix=0.15), -20)


def lend_range():
    """範囲に渡す: 少し大きい風と、C4・E4・G4 を速くばらした和音。"""
    air = whoosh(0.34, 200, 700, 400, 1400)
    x = place(silence(0.62), air * 0.4, 0.0)
    for i, name in enumerate(["C4", "E4", "G4"]):
        x = place(x, modal(NOTE[name], MARIMBA, 0.34, hardness=0.55, decay_scale=1.5) * 5, 0.18 + i * 0.05)
    return finish(soft_room(x, mix=0.15), -19)


def recall():
    """回収: 下がる風と、手元に戻る低い音（G4→C4）。"""
    air = whoosh(0.24, 500, 1600, 200, 800)
    a = modal(NOTE["G4"], MARIMBA, 0.22, hardness=0.55)
    b = modal(NOTE["C4"], MARIMBA, 0.3, hardness=0.55, decay_scale=1.4)
    x = place(place(place(silence(0.46), air * 0.35, 0.0), a * 5, 0.12), b * 6, 0.18)
    return finish(soft_room(x, mix=0.15), -20)


def prohibit():
    """禁止を拾った・禁止で止まった: こもった低い「トッ」を2回。怖くしない。"""
    a = modal(NOTE["E4"], WOOD1, 0.12, hardness=0.4)
    b = modal(NOTE["C4"], WOOD1, 0.14, hardness=0.4)
    x = place(place(silence(0.22), a, 0.0), b, 0.07)
    return finish(lowpass(x, 2200), -23)


# --- 世界 ---------------------------------------------------------------------


def block_jump():
    """ブロックが跳ぶ: 木の当たりと、ゆるく上がる丸い音（ばねっぽくしすぎない）。"""
    knock = modal(NOTE["C4"], WOOD1, 0.08, hardness=0.6)
    n = int(0.2 * SR)
    rise = pitched_body(170, 320, 0.2, curve=0.6) * envelope(n, 0.01, 0.15)
    x = place(place(silence(0.24), knock * 5, 0.0), rise * 0.35, 0.01)
    return finish(x, -19, keep_low=True)


def block_land():
    """ブロックが着地: 低い木の「ドッ」。"""
    body = modal(110.0, WOOD1, 0.22, hardness=0.5, decay_scale=2.0)
    knock = modal(220.0, WOOD1, 0.14, hardness=0.7, decay_scale=1.5)  # 小さなスピーカー用の1オクターブ上
    knock_hi = modal(NOTE["E4"], WOOD1, 0.1, hardness=0.6)
    n = int(0.18 * SR)
    thud = band(colored_noise(0.18, "brown"), 60, 600) * envelope(n, 0.002, 0.15)
    x = place(silence(0.24), body * 6, 0.0)
    x = place(x, knock * 5, 0.0)
    x = place(x, knock_hi * 6, 0.0)
    x = place(x, thud * 0.4, 0.0)
    return finish(x, -18, keep_low=True, tilt_hz=3000)


def block_step():
    """ブロックが1マス動く: 木が地面をこする低い音。"""
    n = int(0.42 * SR)
    scrape = band(colored_noise(0.42, "brown"), 150, 900) * envelope(n, 0.08, 0.2)
    grain = band(colored_noise(0.42, "pink"), 600, 1600) * envelope(n, 0.1, 0.2) * 0.15
    scrape = scrape + grain
    bump = modal(196.0, WOOD2, 0.15, hardness=0.5)
    x = place(scrape * 0.8, bump * 6, 0.3)
    return finish(x, -21, keep_low=True, tilt_hz=2500)


def player_jump():
    """自分の跳躍: 服がなびく短い音。"""
    n = int(0.14 * SR)
    x = band(colored_noise(0.14, "pink"), 400, 1800) * envelope(n, 0.02, 0.1)
    return finish(x, -27)


def player_land():
    """自分の着地: 草の上にやわらかく降りる。"""
    n = int(0.12 * SR)
    thud = band(colored_noise(0.12, "brown"), 70, 450) * envelope(n, 0.003, 0.1)
    pat = band(colored_noise(0.12, "pink"), 300, 1200) * envelope(n, 0.003, 0.06) * 0.6
    grass = band(colored_noise(0.12, "pink"), 900, 2600) * envelope(n, 0.004, 0.08) * 0.3
    return finish(thud + pat + grass, -24, keep_low=True, tilt_hz=3000)


def footstep(seed):
    """草の上の足音（3種類）。小さく。"""
    local = np.random.default_rng(seed)
    n = int(0.09 * SR)
    noise = local.standard_normal(n)
    crunch = band(noise, 700 + seed * 60, 2400) * envelope(n, 0.004, 0.07) * 0.5
    thud = band(local.standard_normal(n), 120, 500) * envelope(n, 0.002, 0.06)
    return finish(crunch + thud * 1.5, -31, keep_low=True, tilt_hz=3000)


def save():
    """保存できた: 温かいマリンバの上がる分散和音（C4 E4 G4 C5）。"""
    x = silence(1.0)
    for i, name in enumerate(["C4", "E4", "G4", "C5"]):
        x = place(x, modal(NOTE[name], MARIMBA, 0.6, hardness=0.55, decay_scale=2.2) * 5, i * 0.09)
    return finish(soft_room(x, length=0.2, mix=0.2), -21)


def goal():
    """到達: 五音で上がる旋律と、ゆっくり立ち上がるやわらかい和音（C4 E4 G4）。"""
    x = silence(1.9)
    for i, name in enumerate(["C4", "D4", "E4", "G4", "A4", "C5"]):
        x = place(x, modal(NOTE[name], MARIMBA, 0.8, hardness=0.55, decay_scale=2.5) * 5, i * 0.11)
    n = int(1.3 * SR)
    pad = sum(np.sin(2 * np.pi * NOTE[nm] * t(1.3)) for nm in ["C4", "E4", "G4"]) / 3
    x = place(x, pad * envelope(n, 0.35, 0.7) * 0.25, 0.5)
    return finish(soft_room(x, length=0.25, mix=0.22), -19)


def radial_open():
    return finish(modal(NOTE["E4"], WOOD2, 0.08, hardness=0.45), -28)


SOUNDS = {
    "ui_hover": ui_hover,
    "ui_select": ui_select,
    "ui_confirm": ui_confirm,
    "ui_cancel": ui_cancel,
    "ui_open": ui_open,
    "ui_close": ui_close,
    "ui_pick": ui_pick,
    "ui_drop": ui_drop,
    "ui_error": ui_error,
    "radial_open": radial_open,
    "lend": lend,
    "lend_range": lend_range,
    "recall": recall,
    "prohibit": prohibit,
    "block_jump": block_jump,
    "block_land": block_land,
    "block_step": block_step,
    "player_jump": player_jump,
    "player_land": player_land,
    "footstep_1": lambda: footstep(1),
    "footstep_2": lambda: footstep(2),
    "footstep_3": lambda: footstep(3),
    "save": save,
    "goal": goal,
}


def main():
    for name, build in SOUNDS.items():
        write(name, build())
    print(f"wrote {len(SOUNDS)} sounds to {OUT}")


if __name__ == "__main__":
    main()
