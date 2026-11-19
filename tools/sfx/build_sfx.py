"""効果音を、CC0 の実録音（art/audio/*.wav）から作って assets/audio/sfx/*.wav に書き出す（決定的）。

    python3 tools/sfx/build_sfx.py

本人の要望（2026-11-19）: 合成した音は毎回似ている。フリーの音源の波形や音程を見て、本当の音のようにしてほしい。
そこで合成をやめ、CC0 の録音から選んで、切り出し・音程の微調整・重ね・音量合わせだけをする。
- 素材と出典は art/audio/CREDITS.md（すべて CC0）。選んだ理由と測った値は docs/sound-design.md
- 素材は使う部分だけを 44.1kHz・モノラルの WAV にしてリポジトリに置く（CI でも同じ音を作り直せるように）
- 仕上げ（finish）は前と同じ: 低域・シャリつきの整理、端の処理、RMS で音量をそろえる
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


# --- 録音の扱い ---------------------------------------------------------------

SOURCE = Path(__file__).resolve().parents[2] / "art" / "audio"


def rec(name, start=0.0, end=None):
    """art/audio/<name>.wav を読み、start〜end 秒を切り出す（float、-1〜1）。"""
    with wave.open(str(SOURCE / f"{name}.wav")) as w:
        data = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(float) / 32768
    a = int(start * SR)
    b = len(data) if end is None else min(len(data), int(end * SR))
    return data[a:b].copy()


def repitch(x, factor):
    """音程を factor 倍にする（長さは 1/factor 倍。テープを速く・遅く回すのと同じ）。"""
    if abs(factor - 1.0) < 1e-6:
        return x
    return signal.resample_poly(x, int(round(1000 / factor)), 1000)


def fade(x, fade_in=0.002, fade_out=0.03):
    n_in = max(1, int(fade_in * SR))
    n_out = max(1, min(len(x), int(fade_out * SR)))
    x = x.copy()
    x[:n_in] *= np.linspace(0.0, 1.0, n_in)
    x[-n_out:] *= np.linspace(1.0, 0.0, n_out) ** 2
    return x


def trim_silence(x, threshold=0.02):
    """頭の無音を切る（叩いた瞬間から始める）。"""
    loud = np.where(np.abs(x) > threshold * np.max(np.abs(x)))[0]
    return x[max(0, loud[0] - int(0.002 * SR)):] if len(loud) else x


def norm(x):
    return x / (np.max(np.abs(x)) + 1e-9)


def mix(length, *parts):
    """(音, 開始秒, 音量) を重ねる。"""
    out = silence(length)
    for sound, at, gain in parts:
        out = place(out, sound * gain, at)
    return out


# --- UI -----------------------------------------------------------------------


def ui_hover():
    """指したとき: 小さなスイッチの「カチ」（rubberduck switch_01）。80ms に収める。"""
    x = fade(trim_silence(rec("rd_switch_01"))[: int(0.075 * SR)], fade_out=0.02)
    return finish(x, -36)


def ui_select():
    """選ぶ: 木を軽く叩く音（rubberduck RPG wood_02）。シャリつく上の方だけ弱める。"""
    return finish(fade(lowpass(trim_silence(rec("rpg_wood_02")), 6000)), -25)


def ui_confirm():
    """決定: 木の「コン」（rubberduck wooden_02）。少しだけ高くして明るく。"""
    x = fade(repitch(trim_silence(rec("rd_wooden_02", 0.0, 0.4)), 1.06), fade_out=0.06)
    return finish(x, -23)


def ui_cancel():
    """取り消し: 低めの木の「ゴツ」（rubberduck RPG wood_03）。"""
    x = fade(trim_silence(rec("rpg_wood_03")), fade_out=0.05)
    return finish(x, -26)


def ui_open():
    """持ち物・メニューを開く: 本を開く音（Kenney bookOpen）。"""
    return finish(fade(trim_silence(rec("ken_bookOpen"))), -24)


def ui_close():
    """閉じる: 本を置く音（Kenney bookPlace3）。"""
    return finish(fade(trim_silence(rec("ken_bookPlace3"))), -26)


def ui_pick():
    """つまむ: 小さな革の持ち手をつかむ音（Kenney handleSmallLeather）。"""
    return finish(fade(trim_silence(rec("ken_handleSmallLeather"))), -26)


def ui_drop():
    """置く: 本をそっと置く音（Kenney bookPlace1）。"""
    return finish(fade(trim_silence(rec("ken_bookPlace1"))), -23)


def ui_error():
    """できない: こもった「ドッ」（rubberduck hit_03）。ブザーにしない。"""
    x = fade(trim_silence(rec("rd_hit_03")), fade_out=0.08)
    return finish(x, -25, keep_low=True)


def radial_open():
    """円形 UI を開く: 紙をはじく音（rubberduck paper_02）を短く。"""
    x = fade(trim_silence(rec("rd_paper_02"))[: int(0.3 * SR)], fade_out=0.08)
    return finish(x, -29)


# --- 能力 ---------------------------------------------------------------------


def lend():
    """能力を渡す: 振った風の音（artisticdude swish-9）のあとに「ポン」（rubberduck plop_01）。"""
    # 振った風は低い成分が多く、そのままだとこもるので 700Hz 未満を削って空気の音にする
    swish = norm(highpass(trim_silence(rec("sw_swish-9")), 700))
    pop = norm(trim_silence(rec("rd_plop_01")))
    return finish(fade(mix(0.5, (swish, 0.0, 0.7), (pop, 0.12, 1.0))), -21)


def lend_range():
    """範囲に渡す: 大きめの風（pyranostudios air whoosh の一部）と、少しずつ音程を変えた「ポン」3つ。"""
    air = fade(norm(rec("wh_whoosh2", 3.05, 3.7)), 0.05, 0.2)
    pop = norm(trim_silence(rec("rd_plop_01")))
    parts = [(air, 0.0, 0.6)]
    for i, f in enumerate([0.94, 1.0, 1.06]):
        parts.append((repitch(pop, f), 0.2 + i * 0.07, 0.8))
    return finish(fade(mix(0.75, *parts)), -20)


def recall():
    """回収: 「ポン」（plop_02）と、逆回しの風（swish-9 を逆に）で手元へ吸い込む。"""
    swish = norm(trim_silence(rec("sw_swish-9")))[::-1].copy()
    pop = norm(trim_silence(rec("rd_plop_02")))
    return finish(fade(mix(0.5, (pop, 0.0, 0.9), (swish, 0.08, 0.8))), -21)


def prohibit():
    """禁止: 錠が掛かる「カチャ」（rubberduck RPG lock_02）。明るすぎる成分は弱める。"""
    x = fade(lowpass(trim_silence(rec("rpg_lock_02")), 4500, order=2), fade_out=0.05)
    return finish(x, -24)


# --- 世界 ---------------------------------------------------------------------


def block_jump():
    """ブロックが跳ぶ: ばねの音（rubberduck spring_05）。おもちゃの箱が跳ねる感じ。"""
    x = fade(trim_silence(rec("rd_spring_05"))[: int(0.6 * SR)], fade_out=0.15)
    return finish(x, -20, keep_low=True)


def block_land():
    """ブロックが着地: 木の箱を打ちつける「ドン」（rubberduck slam_04）。"""
    x = fade(trim_silence(rec("rd_slam_04")), fade_out=0.08)
    return finish(x, -19, keep_low=True)


def block_step():
    """ブロックが1マス動く: 石が地面をこする音（rubberduck RPG stones_02）を短く。"""
    x = fade(trim_silence(rec("rpg_stones_02"))[: int(0.42 * SR)], fade_out=0.12)
    return finish(lowpass(x, 6000), -22, keep_low=True)


def player_jump():
    """自分の跳躍: 服がこすれる音（Kenney cloth2）。"""
    x = fade(trim_silence(rec("ken_cloth2"))[: int(0.3 * SR)], fade_out=0.1)
    return finish(x, -27)


def player_land():
    """自分の着地: 柔らかい地面の足音（qubodup Fantozzi Sand）と、低い「トッ」（Kenney footstep08）。"""
    step = norm(trim_silence(rec("fz_Fantozzi-SandR2")))
    thud = norm(trim_silence(rec("ken_footstep08")))
    x = lowpass(fade(mix(0.3, (step, 0.0, 0.8), (thud, 0.0, 1.0))), 6000)
    return finish(x, -24, keep_low=True)


FOOTSTEPS = ["fz_Fantozzi-SandL2", "fz_Fantozzi-SandL1", "fz_Fantozzi-SandR3"]


def footstep(index):
    """草の上の足音（qubodup Fantozzi Sand の3つ）。柔らかい地面の音を、少し低く・暗くして使う。"""
    x = trim_silence(rec(FOOTSTEPS[index - 1]))[: int(0.25 * SR)]
    x = fade(lowpass(repitch(x, 0.9), 4500), fade_out=0.08)
    return finish(x, -31, keep_low=True)


def save():
    """保存できた: やわらかい呪文のきらめき（rubberduck RPG spell_01）。"""
    x = fade(lowpass(trim_silence(rec("rpg_spell_01")), 7000), fade_out=0.15)
    return finish(x, -21)


def goal():
    """到達: 銅鑼（rubberduck gong_01）を少し高くして、宝石のきらめき（item_gem_03）を重ねる。"""
    gong = norm(repitch(trim_silence(rec("rd_gong_01")), 1.05))
    gem = norm(trim_silence(rec("rpg_item_gem_03")))
    x = mix(1.9, (gong, 0.0, 1.0), (gem, 0.05, 0.5), (repitch(gem, 1.12), 0.25, 0.35))
    return finish(fade(x, fade_out=0.4), -19)


def bell():
    """鐘: 銅鑼（rubberduck gong_01）を音程 0.85 倍にして、大きな鐘の重さにする。"""
    x = fade(repitch(trim_silence(rec("rd_gong_01")), 0.85), fade_out=0.4)
    return finish(x, -19, keep_low=True)


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
