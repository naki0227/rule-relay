"""効果音を合成して assets/audio/sfx/*.wav に書き出す（決定的・固定シード）。

    python3 tools/sfx/build_sfx.py

世界観（ゆるふわの木のおもちゃの箱庭）に合わせて、役割ごとに楽器を分ける（2026-11-20、docs/sound-design.md）:
- UI の選ぶ・決定・取り消し: カリンバ（親指ピアノ）。開く・閉じる: オカリナ風の息。つまむ: 泡の「ポッ」
- 置く・ブロック: 木のおもちゃ（木魚・拍子木）。跳ぶ: おもちゃのばね。動く: ぜんまいの「カタタン」
- 円形 UI・範囲: ハープのつまびき（Karplus-Strong）。禁止・できない: 弱音のフェルトピアノ
- 足音: 柔らかい「ぽふっ」。保存: オルゴール。到達: カリンバの旋律と和音。鐘: 温かい村の鐘
- キーはハ長調の五音（主に C4〜E5）でそろえ、高すぎる音（C6 以上）は使わない
- 仕上げ: 低域・シャリつきの整理、端の処理、RMS で音量をそろえる
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
        if f > 11000:  # 聞こえにくく、シャリつくだけの帯域は入れない
            continue
        tau = -1.0 / (SR * np.log(radius)) * decay_scale
        if ratio > 1.5:
            # 実際の木や鍵盤と同じく、上のモードほど早く消える。音程（基音）は低いまま、
            # 叩いた瞬間だけ明るく聞こえる（こもらない）
            tau /= ratio**0.45
        weight = gain * (hardness ** (ratio > 1.5)) * 6.0 ** (ratio > 1.5)
        out += weight * np.sin(2 * np.pi * f * x) * np.exp(-x / tau)
    # マレットの当たり: 4ms の雑音を 1.5〜8kHz に絞る。これが「コッ」の輪郭で、無いとこもる
    n_hit = int(0.004 * SR)
    hit = RNG.standard_normal(n_hit) * np.hanning(n_hit)
    hit = band(hit, 1500, 8000) * 0.07 * hardness
    out[:n_hit] += hit[: len(out)]
    # 木の胴の短い鳴り（2〜3kHz 付近に 20ms ほど）。木魚・拍子木の「カッ」に近い成分
    n_body = min(len(out), int(0.03 * SR))
    body = band(RNG.standard_normal(n_body), 1800 + freq, 3200 + freq, order=2)
    out[:n_body] += body * np.exp(-np.arange(n_body) / (0.006 * SR)) * 0.035 * hardness
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
    ir = lowpass(ir, 6000)
    ir /= np.sum(np.abs(ir)) + 1e-9
    dry = np.concatenate([x, np.zeros(n)])
    wet = signal.fftconvolve(x, ir)
    wet = np.pad(wet, (0, max(0, len(dry) - len(wet))))[: len(dry)]
    return dry * (1 - mix) + wet * mix * 6.0


def finish(x, rms_db, keep_low=False, tilt_hz=9000):
    """仕上げ: 低域・高域の整理、端の処理、音量をそろえる（RMS 基準、ピークは -3dBFS 以下）。"""
    # 120Hz 未満を切る。低い衝撃音（keep_low）でも、聞こえない 45Hz 未満と直流は切る
    x = highpass(x, 45 if keep_low else 150)
    x = lowpass(x, tilt_hz, order=2)  # シャリつく帯域（9kHz〜）だけを弱める
    fade = int(0.004 * SR)
    x[:fade] *= np.linspace(0, 1, fade)
    x[-fade:] *= np.linspace(1, 0, fade)
    rms = np.sqrt(np.mean(x**2)) + 1e-12
    x *= 10 ** (rms_db / 20) / rms
    # 叩いた瞬間の短い山だけが大きいと、ピークに合わせて全体が小さくなる。やわらかく丸めてから戻す
    limit = 10 ** (-3 / 20)
    if np.max(np.abs(x)) > limit:
        x = limit * np.tanh(x / limit)
        x *= 10 ** (rms_db / 20) / (np.sqrt(np.mean(x**2)) + 1e-12)
        peak = np.max(np.abs(x))
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


def fade(x, fade_in=0.002, fade_out=0.03):
    n_in = max(1, int(fade_in * SR))
    n_out = max(1, min(len(x), int(fade_out * SR)))
    x = x.copy()
    x[:n_in] *= np.linspace(0.0, 1.0, n_in)
    x[-n_out:] *= np.linspace(1.0, 0.0, n_out) ** 2
    return x


def norm(x):
    return x / (np.max(np.abs(x)) + 1e-9)


def mix(length, *parts):
    """(音, 開始秒, 音量) を重ねる。"""
    out = silence(length)
    for sound, at, gain in parts:
        out = place(out, sound * gain, at)
    return out


# --- 楽器（世界観: ゆるふわの木のおもちゃの箱庭） -----------------------------
#
# 本人の要望（2026-11-20）: 実録音はリアルに寄りすぎる。合成でよいので、楽器を変えるなどして、世界観に合った音の出し方に。
# 前の合成（2026-11-18）は全部が同じ仕組み（木を叩くモデル）だったので、どの音も似ていた。
# そこで役割ごとに楽器を分け、キー（ハ長調の五音、主に C4〜E5）だけはそろえて、ひとつの曲のようにまとめる。

NOTE.update({"C3": 130.81, "G3": 196.00, "A4": 440.00, "G5": 783.99, "A5": 880.00})


def kalimba(freq, seconds=0.6, bright=0.6):
    """カリンバ（親指ピアノ）: 金属の舌の基音＋片持ちの棒の倍音（6.27倍、すぐ消える）＋木の箱の響き＋はじく音。"""
    x = t(seconds)
    tone = np.sin(2 * np.pi * freq * x) * np.exp(-x / 0.5)
    tone += 0.12 * np.sin(2 * np.pi * 2 * freq * x) * np.exp(-x / 0.12)
    if freq * 6.27 < 9000:
        tone += 1.0 * bright * np.sin(2 * np.pi * freq * 6.27 * x) * np.exp(-x / 0.035)
    body = band(tone, 250, 900) * 0.35  # 共鳴箱
    n = int(0.008 * SR)
    click = band(RNG.standard_normal(n), 1500, 5000) * np.exp(-np.arange(n) / (0.003 * SR))
    out = tone + body
    out[:n] += click * 3.5 * bright
    return fade(out, 0.001, 0.05)


def music_box(freq, seconds=0.9):
    """オルゴール: 櫛の歯（片持ちの棒）。カリンバより金属的で、上の倍音が少し長く残る。低めの音域だけ使う。"""
    x = t(seconds)
    tone = np.sin(2 * np.pi * freq * x) * np.exp(-x / 0.6)
    if freq * 6.27 < 9000:
        tone += 0.25 * np.sin(2 * np.pi * freq * 6.27 * x) * np.exp(-x / 0.12)
    n = int(0.004 * SR)
    tone[:n] += band(RNG.standard_normal(n), 2500, 7000) * 0.3
    return fade(tone, 0.001, 0.08)


def pluck(freq, seconds=0.8, damping=0.996, brightness=0.55):
    """ハープのつまびき（Karplus-Strong）。木の弦の、やわらかい減衰。"""
    period = max(2, int(round(SR / freq)))
    buf = lowpass(RNG.standard_normal(period), 1500 + 6000 * brightness, order=1)
    n = int(seconds * SR)
    out = np.zeros(n)
    for i in range(n):
        j = i % period
        out[i] = buf[j]
        buf[j] = damping * 0.5 * (buf[j] + buf[(j + 1) % period])
    return fade(out / (np.max(np.abs(out)) + 1e-9), 0.001, 0.06)


def ocarina(f0, f1, seconds, vibrato=5.5, breath=0.12):
    """オカリナ風の息の音: ほぼ純粋な音に息のかすれ。音程を f0 から f1 へなめらかに動かす。"""
    x = t(seconds)
    glide = f0 + (f1 - f0) * (0.5 - 0.5 * np.cos(np.pi * np.clip(x / (seconds * 0.7), 0, 1)))
    vib = 1.0 + 0.006 * np.sin(2 * np.pi * vibrato * x) * np.clip((x - 0.08) / 0.1, 0, 1)
    phase = 2 * np.pi * np.cumsum(glide * vib) / SR
    tone = np.sin(phase) + 0.08 * np.sin(2 * phase)
    air = band(colored_noise(seconds, "pink"), 900, 3500) * breath
    n = len(x)
    out = (tone + air) * envelope(n, 0.05, seconds * 0.45)
    # 吹き始めの「チッ」（笛の息の立ち上がり）。これが無いと、ぼやけた音になる
    m = int(0.03 * SR)
    out[:m] += band(RNG.standard_normal(m), 1500, 6000) * np.exp(-np.arange(m) / (0.008 * SR)) * 0.9
    return out


def bubble(f0, f1, seconds=0.07):
    """泡がはじける「ポッ」: 音程が急に上がる短い正弦波。"""
    x = t(seconds)
    f = f0 * (f1 / f0) ** (x / seconds)
    phase = 2 * np.pi * np.cumsum(f) / SR
    out = np.sin(phase) * np.exp(-x / (seconds * 0.4))
    m = int(0.01 * SR)
    out[:m] += band(RNG.standard_normal(m), 2000, 6000) * np.exp(-np.arange(m) / (0.003 * SR)) * 3.5
    return fade(out, 0.001, 0.01)


def felt_piano(freq, seconds=0.5, hardness=0.5):
    """フェルトピアノ（弱音器をかけた柔らかいピアノ）: 少し伸びた倍音列、フェルトのハンマーで高い倍音が弱い。
    2本の弦をわずかにずらして、温かいうなりを出す。"""
    x = t(seconds)
    out = np.zeros_like(x)
    for detune in (0.9995, 1.0005):
        for k in range(1, 7):
            fk = k * freq * detune * np.sqrt(1 + 0.0004 * k * k)
            if fk > 8000:
                break
            amp = (1.0 / k ** 1.4) * np.exp(-(k - 1) * (1.0 - hardness) * 0.8)
            out += amp * np.sin(2 * np.pi * fk * x) * np.exp(-x / (1.0 / (1 + 0.6 * k)))
    n = int(0.012 * SR)
    hit = band(RNG.standard_normal(n), 1500, 5000) * np.exp(-np.arange(n) / (0.004 * SR))
    out[:n] += hit * 7.0  # フェルトのハンマーが弦に当たる音
    return fade(out * 0.5, 0.001, 0.06)


def toy_wood(freq, seconds=0.12, hardness=0.8):
    """木のおもちゃの「コッ」（木魚・拍子木。前のモーダル合成を、硬めに短く。大きさを 1 にそろえる）。"""
    return norm(modal(freq, WOOD1, seconds, hardness=hardness))


def boing(f0, f1, seconds=0.35):
    """おもちゃのばね: 音程が上がりながら、揺れがだんだん収まる。"""
    x = t(seconds)
    base_f = f0 + (f1 - f0) * (1 - np.exp(-x / 0.08))
    wobble = 1.0 + 0.12 * np.sin(2 * np.pi * 16 * x) * np.exp(-x / 0.12)
    phase = 2 * np.pi * np.cumsum(base_f * wobble) / SR
    tone = np.sin(phase) + 0.25 * np.sin(3 * phase)
    return fade(tone * np.exp(-x / 0.18), 0.003, 0.05)


def puff(seed, cutoff=1400, pitch=180):
    """柔らかい足音「ぽふっ」: 短い息のような雑音と、小さな低い当たり。"""
    local = np.random.default_rng(seed)
    n = int(0.07 * SR)
    noise = local.standard_normal(n)
    air = band(noise, 350, cutoff) * np.exp(-np.arange(n) / (0.018 * SR))
    tap = np.sin(2 * np.pi * pitch * np.arange(n) / SR) * np.exp(-np.arange(n) / (0.012 * SR))
    tick = band(local.standard_normal(n), 1800, 4500) * np.exp(-np.arange(n) / (0.003 * SR)) * 1.8
    return fade(air + tap * 0.6 + tick, 0.002, 0.02)


def warm_pad(names, seconds):
    """やわらかい和音（少しずらした正弦波を重ね、ゆっくり立ち上げる）。"""
    x = t(seconds)
    out = np.zeros_like(x)
    for nm in names:
        for d in (0.998, 1.002):
            out += np.sin(2 * np.pi * NOTE[nm] * d * x)
    return out / (2 * len(names)) * envelope(len(x), seconds * 0.3, seconds * 0.5)


# --- UI -----------------------------------------------------------------------


def ui_hover():
    """指したとき: ごく小さなカリンバ（弱音）。目立たせない。"""
    return finish(kalimba(NOTE["G4"], 0.07, bright=0.5), -36)


def ui_select():
    """ホットバーを選ぶ: カリンバの1音（枠の番号ごとの音程は鳴らす側で変える）。"""
    return finish(kalimba(NOTE["C5"], 0.32, bright=0.7), -25)


def ui_confirm():
    """決定: カリンバで上がる2音（G4 → C5）。"""
    x = mix(0.32, (kalimba(NOTE["G4"], 0.25), 0.0, 0.8), (kalimba(NOTE["C5"], 0.25), 0.07, 1.0))
    return finish(soft_room(x, mix=0.1), -23)


def ui_cancel():
    """取り消し: カリンバで下がる2音（E4 → C4）。はじく音を少し弱く。"""
    x = mix(0.4, (kalimba(NOTE["E4"], 0.28, 0.5), 0.0, 0.9), (kalimba(NOTE["C4"], 0.32, 0.5), 0.07, 1.0))
    return finish(x, -26)


def ui_open():
    """持ち物・メニューを開く: オカリナ風の息がふわっと上がる（C4 → G4）。"""
    return finish(soft_room(ocarina(NOTE["C4"], NOTE["G4"], 0.32), mix=0.12), -25)


def ui_close():
    """閉じる: 息がふわっと下がる（G4 → C4）。"""
    return finish(ocarina(NOTE["G4"], NOTE["C4"], 0.26), -27)


def ui_pick():
    """つまむ: 泡がはじける「ポッ」。"""
    return finish(bubble(NOTE["G4"], NOTE["C5"] * 1.5, 0.08), -26)


def ui_drop():
    """置く: 木のおもちゃを置く「コトッ」（高めと低めの2つ）。"""
    x = mix(0.16, (toy_wood(NOTE["G4"], 0.12), 0.0, 1.0), (toy_wood(NOTE["C4"], 0.14, 0.6), 0.012, 0.8))
    return finish(x, -23)


def ui_error():
    """できない: フェルトピアノの低い2音を、少しずらして「とん、とん」。ブザーにしない。"""
    x = mix(0.4, (felt_piano(NOTE["D4"], 0.25), 0.0, 1.0), (felt_piano(NOTE["C4"], 0.3), 0.11, 1.0))
    return finish(x, -25)


def radial_open():
    """円形 UI を開く: ハープを3本、速くつまびく（C4 E4 G4）。"""
    x = silence(0.4)
    for i, nm in enumerate(["C4", "E4", "G4"]):
        x = place(x, pluck(NOTE[nm], 0.3, 0.994) * 0.6, i * 0.035)
    return finish(x, -28)


# --- 能力 ---------------------------------------------------------------------


def lend():
    """能力を渡す: 息がふわっと上がり（E4 → A4）、着いたところでカリンバ（E5）。"""
    air = ocarina(NOTE["E4"], NOTE["A4"], 0.25, breath=0.2)
    x = mix(0.6, (air, 0.0, 0.6), (kalimba(NOTE["E5"], 0.4), 0.18, 1.0))
    return finish(soft_room(x, mix=0.15), -21)


def lend_range():
    """範囲に渡す: ハープを上へ流すように（C4 D4 E4 G4 A4 C5）。範囲に広がる感じ。"""
    x = silence(0.66)
    for i, nm in enumerate(["C4", "D4", "E4", "G4", "A4", "C5"]):
        x = place(x, pluck(NOTE[nm], 0.4, 0.995, brightness=0.3), i * 0.045)
    return finish(soft_room(x, mix=0.18), -20)


def recall():
    """回収: 息が下がって（A4 → E4）手元へ、最後に小さな「ポッ」。"""
    air = ocarina(NOTE["A4"], NOTE["E4"], 0.25, breath=0.2)
    x = mix(0.5, (air, 0.0, 0.6), (bubble(NOTE["C5"], NOTE["G4"], 0.07), 0.2, 0.9))
    return finish(soft_room(x, mix=0.12), -21)


def prohibit():
    """禁止: 弱音のフェルトピアノで半音ずつ下がる2音（E4 → D#4 の響き）と、木の「コッ」。怖くしない。"""
    x = mix(
        0.4,
        (toy_wood(NOTE["C4"], 0.1, 0.7), 0.0, 0.8),
        (felt_piano(NOTE["E4"], 0.2), 0.02, 0.9),
        (felt_piano(NOTE["E4"] * 2 ** (-1 / 12), 0.28), 0.11, 0.9),
    )
    return finish(x, -24)


# --- 世界 ---------------------------------------------------------------------


def block_jump():
    """ブロックが跳ぶ: 木の「コッ」と、おもちゃのばね（G3 → C4）。"""
    x = mix(0.4, (toy_wood(NOTE["C4"], 0.08), 0.0, 1.0), (boing(NOTE["G3"], NOTE["C4"], 0.35), 0.01, 0.5))
    return finish(x, -19, keep_low=True)


def block_land():
    """ブロックが着地: 木の積み木を置く「コトン」（低い胴鳴り＋高い当たり）。"""
    low = modal(110.0, WOOD1, 0.22, hardness=0.5, decay_scale=2.0)
    mid = toy_wood(NOTE["E4"], 0.1, 0.9)
    x = mix(0.24, (low, 0.0, 6.0), (mid, 0.0, 5.0))
    return finish(x, -18, keep_low=True, tilt_hz=7000)


def block_step():
    """ブロックが1マス動く: ぜんまいの「カタタン」（木の小さな当たりを3回、だんだん弱く）。"""
    x = silence(0.42)
    for i, (nm, g) in enumerate([("G4", 1.0), ("E4", 0.8), ("C4", 0.9)]):
        x = place(x, toy_wood(NOTE[nm], 0.08, 0.85) * g, 0.06 + i * 0.09)
    return finish(x, -22)


def player_jump():
    """自分の跳躍: 小さな息の「ふっ」（短く上がる）。"""
    x = ocarina(NOTE["C4"], NOTE["E4"], 0.12, vibrato=0.0, breath=0.5) * 0.7
    return finish(x, -28)


def player_land():
    """自分の着地: 柔らかい「ぽふっ」を大きめに。"""
    return finish(puff(7, cutoff=1200, pitch=140), -24, keep_low=True)


def footstep(seed):
    """草の上の足音: 柔らかい「ぽふっ」（3種類。少しずつ高さと明るさを変える）。"""
    return finish(puff(seed, cutoff=1300 + seed * 250, pitch=170 + seed * 25), -31, keep_low=True)


def save():
    """保存できた: オルゴールで C4 E4 G4 C5 を上がる。"""
    x = silence(1.0)
    for i, nm in enumerate(["C4", "E4", "G4", "C5"]):
        x = place(x, music_box(NOTE[nm], 0.65), i * 0.11)
    return finish(soft_room(x, length=0.25, mix=0.2), -21)


def goal():
    """到達: カリンバで五音を上がる旋律と、やわらかい和音（C4 E4 G4）。"""
    x = silence(1.9)
    for i, nm in enumerate(["C4", "D4", "E4", "G4", "A4", "C5"]):
        x = place(x, kalimba(NOTE[nm], 0.8, bright=0.85), i * 0.11)
    x = place(x, warm_pad(["C4", "E4", "G4"], 1.3) * 0.6, 0.5)
    return finish(soft_room(x, length=0.3, mix=0.22), -19)


def bell():
    """鐘: 村の鐘。教会の鐘の倍音の比（唸り 0.5・基音 1・短三度 1.19・五度 1.5・オクターブ 2）を、
    少しずらした2つで重ねて温かくする。基音は C4。"""
    x = t(2.0)
    partials = [
        (0.5, 0.5, 1.6), (1.0, 1.0, 1.2), (1.19, 0.5, 0.8), (1.5, 0.3, 0.6),
        (2.0, 0.45, 0.5), (2.5, 0.2, 0.3), (4.2, 1.2, 0.12), (5.4, 1.0, 0.09), (6.8, 0.7, 0.07),
    ]
    out = np.zeros_like(x)
    for detune in (0.998, 1.002):
        for ratio, gain, decay in partials:
            out += gain * np.sin(2 * np.pi * NOTE["C4"] * ratio * detune * x) * np.exp(-x / decay)
    n = int(0.01 * SR)
    out[:n] += band(RNG.standard_normal(n), 2000, 6000) * np.exp(-np.arange(n) / (0.003 * SR)) * 16.0
    return finish(soft_room(fade(out, 0.001, 0.1), length=0.3, mix=0.15), -19)


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
    "bell": bell,
}


def main():
    for name, build in SOUNDS.items():
        write(name, build())
    print(f"wrote {len(SOUNDS)} sounds to {OUT}")


if __name__ == "__main__":
    main()
