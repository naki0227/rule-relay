"""効果音を合成して assets/audio/sfx/*.wav に書き出す（決定的・固定シード）。

    python3 tools/sfx/build_sfx.py

世界観（ゆるふわの木のおもちゃの箱庭）に合わせて、役割ごとに楽器を分ける（2026-11-20、docs/sound-design.md）:
- UI の選ぶ・決定・取り消し: カリンバ（親指ピアノ）。開く・閉じる: オカリナ風の息。つまむ: 泡の「ポッ」
- 置く・ブロック: 木のおもちゃ（木魚・拍子木）。跳ぶ: おもちゃのばね。動く: ぜんまいの「カタタン」
- 円形 UI・範囲: ハープのつまびき（Karplus-Strong）。禁止・できない: 弱音のフェルトピアノ
- 足音: 柔らかい「ぽふっ」。保存: オルゴール。到達: カリンバの旋律と和音。鐘: 温かい村の鐘
- キーはハ長調の五音（主に C4〜E5）でそろえ、高すぎる音（C6 以上）は使わない
- 仕上げ: 低域・シャリつきの整理、端の処理、RMS で音量をそろえる
- 2026-11-20: 6種は Stable Audio 3 medium で生成した候補に置き換えた（ADOPTED。合成の関数は戻せるように残す）
- 2026-11-20: 2回目の候補からさらに 15 種を置き換えた（ADOPTED の sfx2/。docs/sound-design.md）
- 2026-11-20: 3回目の候補から 4 種を置き換え、新しい音 dash・ui_notice を足した（ADOPTED の sfx3/）
- 2026-11-21: 4回目の候補から足音 4 種（3 種から 4 種に増やした）と ui_select を置き換えた（ADOPTED の sfx4/）。
  これで合成のまま残る音は無い（合成の関数は戻し先として残す）
"""

import wave
from pathlib import Path

import numpy as np
from scipy import signal

import analyze

SR = 44100
OUT = Path(__file__).resolve().parents[2] / "assets" / "audio" / "sfx"
RNG = np.random.default_rng(20261118)
CANDIDATES = Path(__file__).resolve().parents[2] / "art" / "audio" / "stable-audio"

# Stable Audio 3 medium の候補から採用した音（docs/sound-design.md、docs/sound-candidates-2026-11-20.md、
# docs/sound-candidates-2026-11-20-round2.md、docs/sound-candidates-2026-11-20-round3.md、docs/sound-candidates-round4.md）。
# イベント名: (候補のファイル, 置き換え前の合成音の RMS dBFS)。候補はピークでそろえてあるので、
# ゲームの中の音量の釣り合いを変えないよう、置き換え前の RMS に合わせる（ピークは -3dBFS を超えない）
ADOPTED = {
    # 1回目（E01〜E54）
    "ui_hover": ("sfx/ui_hover_1.wav", -37.0),  # E01
    "receive_stone": ("sfx/receive_stone_2.wav", -32.8),  # E32
    "block_jump": ("sfx/block_jump_2.wav", -27.6),  # E38
    "block_step": ("sfx/block_step_2.wav", -22.0),  # E42
    "player_jump": ("sfx/player_jump_1.wav", -28.0),  # E45
    "save": ("sfx/save_1.wav", -21.3),  # E51
    # 2回目（R01〜R63）
    "ui_close": ("sfx2/ui_close_3.wav", -26.0),  # R09
    "ui_drop": ("sfx2/ui_drop_3.wav", -23.0),  # R12
    "prohibit": ("sfx2/prohibit_1.wav", -24.0),  # R16
    "receive_wood": ("sfx2/receive_wood_1.wav", -33.1),  # R19
    "receive_creature": ("sfx2/receive_creature_1.wav", -23.0),  # R22
    "block_land": ("sfx2/block_land_2.wav", -32.9),  # R26
    "ui_cancel": ("sfx2/ui_cancel_2.wav", -27.0),  # R29
    "ui_pick": ("sfx2/ui_pick_3.wav", -27.0),  # R36
    "radial_open": ("sfx2/radial_open_2.wav", -29.0),  # R38
    "lend": ("sfx2/lend_1.wav", -22.4),  # R40
    "lend_range": ("sfx2/lend_range_1.wav", -20.0),  # R43
    "recall": ("sfx2/recall_2.wav", -27.8),  # R47
    "receive_grass": ("sfx2/receive_grass_2.wav", -29.0),  # R50
    "player_land": ("sfx2/player_land_2.wav", -25.0),  # R53
    "goal": ("sfx2/goal_3.wav", -20.1),  # R63
    # 3回目（T01〜T24）。dash・ui_notice は置き換え前の音が無いので、近い役割の音に合わせた
    # （dash は自分の跳躍 player_jump と同じ -28.0、ui_notice は UI の ui_close と同じ -26.0）
    "ui_confirm": ("sfx3/ui_confirm_3.wav", -28.6),  # T03
    "ui_error": ("sfx3/ui_error_3.wav", -27.3),  # T07
    "ui_open": ("sfx3/ui_open_1.wav", -26.1),  # T09
    "bell": ("sfx3/bell_3.wav", -34.5),  # T15
    "dash": ("sfx3/dash_1.wav", -28.0),  # T17
    "ui_notice": ("sfx3/ui_notice_1.wav", -26.0),  # T21
    # 4回目（U01〜U10、1回だけの短い打音）。数値は RMS ではなく、置き換え前の当たりの大きさ（MATCH_HIT）。
    # 足音は本人の判断（2026-11-20）で 4 種を順番に鳴らす。footstep_4 は置き換え前の音が無いので、ほかの足音と同じ値。
    # ui_select（U07）は生成した音を加工で −3 半音下げてある（docs/sound-candidates-round4.md）
    "footstep_1": ("sfx4/footstep_1.wav", -26.2),  # U01
    "footstep_2": ("sfx4/footstep_3.wav", -26.2),  # U03
    "footstep_3": ("sfx4/footstep_4.wav", -26.2),  # U04
    "footstep_4": ("sfx4/footstep_5.wav", -26.2),  # U05
    "ui_select": ("sfx4/ui_select_2.wav", -19.8),  # U07
}
# ファイル全体の RMS ではなく、当たりの大きさ（いちばん大きい 30ms の RMS、analyze.hit_db）でそろえる音。
# 4回目の候補は 38〜134ms の打音で、置き換え前（足音 100ms、ui_select 390ms の余韻つき）と長さも形も違う。
# 全体の RMS でそろえると、足音どうしで当たりが 5.4dB ばらつき、ui_select は当たりが 8.8dB 小さくなった（docs/sound-design.md 6回目）
MATCH_HIT = {"footstep_1", "footstep_2", "footstep_3", "footstep_4", "ui_select"}
# 当たりの位置をそろえる音（当たりの 20ms 前から始め、2ms でフェードイン）。足音は 0.34 秒ごとに順番に鳴るので、
# 当たりがファイルの 8〜122ms のどこにあるかがばらばらだと、歩く拍がぶれて足を引きずるように聞こえる（6回目の測定）。
# 当たりの前の草の音は削れる（AI の判断、2026-11-20。聴いて草の音を残したいときはここから外す）
ALIGN_HIT = {"footstep_1", "footstep_2", "footstep_3", "footstep_4"}
ALIGN_LEAD = 0.020

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
    # 空気のかすかな雑音（ピークの約 -54 dB）。録音には必ずあり、完全な無音はデジタルっぽく聞こえる
    x = x + lowpass(np.random.default_rng(len(x)).standard_normal(len(x)), 5000, order=1) * (
        np.max(np.abs(x)) * 0.002
    )
    x = highpass(x, 45 if keep_low else 150)
    x = lowpass(x, tilt_hz, order=2)  # シャリつく帯域（9kHz〜）だけを弱める
    # 頭は 0.3ms だけ（「ぷつっ」を防ぐ最小限）。2026-11-20 までは 4ms で、叩いた瞬間を毎回弱めていた
    head = int(0.0003 * SR)
    tail = int(0.004 * SR)
    x[:head] *= np.linspace(0, 1, head)
    x[-tail:] *= np.linspace(1, 0, tail)
    rms = np.sqrt(np.mean(x**2)) + 1e-12
    x *= 10 ** (rms_db / 20) / rms
    # ピークが -3 dBFS を超えたら、全体の音量を下げる（山を丸めない）。2026-11-20 までは tanh で山を
    # 丸めていたが、叩いた瞬間の山が潰れて輪郭が消え、こもった機械的な音の原因の1つになっていた
    limit = 10 ** (-3 / 20)
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


def adopted(name):
    """採用した候補（tools/sfx/stable_audio_candidates.py で加工済みの 16bit モノラル 44.1kHz）を読み、
    音量だけを置き換え前にそろえる（RMS、MATCH_HIT の音は当たりの大きさ）。音色（フィルター・長さ）はそのまま使う。"""
    file, level_db = ADOPTED[name]
    with wave.open(str(CANDIDATES / file)) as w:
        assert w.getframerate() == SR and w.getnchannels() == 1 and w.getsampwidth() == 2
        x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(float) / 32768
    if name in ALIGN_HIT:
        x = _align_hit(x)
    current = analyze.hit_db(x, SR) if name in MATCH_HIT else 20 * np.log10(np.sqrt(np.mean(x**2)) + 1e-12)
    x = x * 10 ** ((level_db - current) / 20)
    limit = 10 ** (-3 / 20)
    peak = np.max(np.abs(x))
    if peak > limit:
        x *= limit / peak
    return x


def _align_hit(x):
    """いちばん大きい 5ms の窓（当たり）の ALIGN_LEAD 前から始める。頭は 2ms でフェードイン。"""
    win = int(0.005 * SR)
    energy = np.convolve(x**2, np.ones(win), mode="valid")
    offset = int(np.argmax(energy)) - int(ALIGN_LEAD * SR)
    if offset < 0:
        return np.concatenate([np.zeros(-offset), x])  # 当たりが頭に近い音は、前に無音を足してそろえる
    y = x[offset:].copy()
    fade = min(len(y), int(0.002 * SR))
    y[:fade] *= np.linspace(0.0, 1.0, fade)
    return y


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


# --- 物理寄りの合成（2026-11-20 の見直し） ------------------------------------
#
# 本人の感想: 「クロードが作った音という感じがすごくする。量産型。このゲームのユニークさに合わせてほしい」。
# 実録音 257 個と比べた結果（tools/sfx/compare_realism.py、docs/sound-design.md）:
#   スペクトルの平坦さが約 600 分の 1、スペクトルの山の数が 628 対 18、時間による音色の変化が 3 分の 1。
#   つまり「きれいすぎる（成分が少ない）」「音色が止まっている」のが AI っぽさの正体だった。
# そこで:
# - 物は数十〜百の振動（モード）を、材質ごとの規則でばらつかせて持つ。叩く・こする・はじく雑音で鳴らす
#   （正弦波を足すのではなく、雑音を共鳴させる。実物と同じく成分が密になる）
# - 鳴っている間に、音程をわずかに下げ、高い成分ほど早く消し、近いモードどうしでうなりを出す（音色が動く）
# - 小さな部屋の反射（まばらな初期反射＋短い残響）を足す
# 音の考え方（ユニークさ）: 「島の物そのものが楽器」。持ち物は紙の札と本、能力は「法則の音」
#   （能力ごとに音程が決まったモチーフ）、受け取った物は自分の材質の声で応える。

def resonate(excitation, modes, seconds):
    """excitation を、モード [(周波数, 減衰の時間, 大きさ)] の共鳴器の組で鳴らす（2極の共鳴フィルター）。"""
    n = int(seconds * SR)
    x = np.zeros(n)
    x[: min(n, len(excitation))] = excitation[:n]
    out = np.zeros(n)
    for f, tau, gain in modes:
        if f <= 20 or f >= SR * 0.45:
            continue
        r = np.exp(-1.0 / (tau * SR))
        theta = 2 * np.pi * f / SR
        # 2極の共鳴器は、そのままだと低い周波数ほど山が高くなる（全体が暗くなる偏り）。
        # 山の高さが周波数によらずほぼ gain になるよう 2·sin(θ) を掛ける
        b = [gain * (1 - r) * 2 * np.sin(theta)]
        a = [1.0, -2 * r * np.cos(theta), r * r]
        out += signal.lfilter(b, a, x)
    return out


def material(kind, base, count=60, seed=0):
    """材質ごとのモードの組。base は主な音の高さ（Hz）。"""
    kinds = ["wood", "stone", "paper", "glass", "bell", "flesh"]
    rng = np.random.default_rng(seed * 31 + kinds.index(kind) * 7919)
    modes = []
    if kind == "wood":
        # 木の棒・板: 自由振動の比（1, 2.76, 5.40, 8.93）を主にして、そのまわりに板の細かい振動をばらまく
        for k, ratio in enumerate([1.0, 2.76, 5.40, 8.93]):
            for _ in range(3):
                f = base * ratio * rng.uniform(0.97, 1.03)
                modes.append((f, 0.12 / (1 + k) * rng.uniform(0.6, 1.3), 1.0 / (1 + k) ** 2))
        for _ in range(count):
            f = base * rng.uniform(1.5, 14)
            # 木は高い振動ほど早く止まる（内部の摩擦）。長く残る高い振動は金属っぽく聞こえる
            tau = rng.uniform(0.01, 0.05) * min(1.0, (1500 / f) ** 0.7)
            modes.append((f, tau, rng.uniform(0.03, 0.15)))
    elif kind == "stone":
        # 石: 規則の無い密なモード。すぐ止まる。低めは少し長い
        for _ in range(count):
            f = base * np.exp(rng.uniform(0, np.log(12)))
            modes.append((f, rng.uniform(0.008, 0.04) * (base * 2 / f) ** 0.3, rng.uniform(0.2, 1.0)))
    elif kind == "paper":
        # 紙・札: 高い帯域に広がった、ごく短いモードの集まり
        for _ in range(count):
            f = np.exp(rng.uniform(np.log(800), np.log(7000)))
            modes.append((f, rng.uniform(0.002, 0.012), rng.uniform(0.2, 1.0)))
    elif kind == "glass":
        # 「法則の音」: ガラスの棒のような、長く鳴る少数の主音と、うなりを作る近い対
        for k, ratio in enumerate([1.0, 2.0, 2.92, 4.16, 5.4]):
            for d in (1.0, 1.0 + rng.uniform(0.002, 0.006)):
                modes.append((base * ratio * d, 0.5 / (1 + 0.8 * k), 1.0 / (1 + k) ** 1.6))
        for _ in range(count // 3):
            modes.append((base * rng.uniform(1.2, 9), rng.uniform(0.02, 0.08), rng.uniform(0.02, 0.1)))
    elif kind == "bell":
        for ratio, gain, tau in [(0.5, 0.5, 1.6), (1.0, 1.0, 1.2), (1.19, 0.5, 0.8), (1.5, 0.3, 0.6),
                                 (2.0, 0.45, 0.5), (2.5, 0.2, 0.3), (4.2, 0.4, 0.15), (5.4, 0.3, 0.1)]:
            for d in (1.0, 1.0 + rng.uniform(0.001, 0.004)):
                modes.append((base * ratio * d, tau, gain))
        for _ in range(count):
            modes.append((base * rng.uniform(2, 14), rng.uniform(0.02, 0.15), rng.uniform(0.02, 0.15)))
    elif kind == "flesh":
        # 生き物のやわらかい体: 低い数モード、強い減衰
        for _ in range(12):
            modes.append((base * rng.uniform(0.8, 3.5), rng.uniform(0.02, 0.06), rng.uniform(0.3, 1.0)))
    return modes


def strike(hardness=0.6, length=0.004, seed=0):
    """叩く: 短い雑音。硬いほど短く、高い成分が多い。"""
    rng = np.random.default_rng(seed)
    n = max(8, int(length * SR))
    burst = rng.standard_normal(n) * np.hanning(n)
    return lowpass(burst, 2000 + 9000 * hardness, order=1)


def scrape(seconds, density=300, seed=0):
    """こする・擦れる: まばらな小さい衝撃の列（摩擦の引っかかり）と、うすい雑音。"""
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    out = rng.standard_normal(n) * 0.08
    count = int(density * seconds)
    for _ in range(count):
        i = rng.integers(0, n)
        out[i] += rng.uniform(-1, 1) * rng.uniform(0.3, 1.0)
    return out * envelope(n, seconds * 0.15, seconds * 0.5)


def crackle(seconds, density=400, bright=4000, seed=0):
    """草・紙のくしゃっとした音: 不規則な小さい破裂の集まり。"""
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    out = np.zeros(n)
    times = rng.integers(0, n, int(density * seconds))
    for i in times:
        m = min(n - i, int(rng.uniform(0.0005, 0.002) * SR))
        out[i : i + m] += rng.standard_normal(m) * np.exp(-np.arange(m) / (m * 0.3 + 1)) * rng.uniform(0.2, 1)
    return band(out, 600, bright)


def droop(x, cents=-15, seconds=0.08):
    """鳴り始めの音程がわずかに下がる（張力が戻る。実物の打撃音に多い）。時間を少しずつ引き伸ばして近似する。"""
    n = len(x)
    idx = np.arange(n, dtype=float)
    ratio = 2 ** (cents / 1200)
    warp = idx * (1 + (ratio - 1) * (1 - np.exp(-idx / (seconds * SR))))
    return np.interp(warp, idx, x)


def room(x, size=0.6, mix_amount=0.12, seed=0):
    """小さな部屋: まばらな初期反射（5〜35ms）と短い拡散の残響。"""
    rng = np.random.default_rng(seed)
    n = int((0.04 + 0.25 * size) * SR)
    ir = np.zeros(n)
    for _ in range(9):
        i = int(rng.uniform(0.005, 0.035) * SR)
        ir[i] += rng.uniform(-1, 1) * 0.6
    tail = rng.standard_normal(n) * np.exp(-np.arange(n) / (0.07 * size * SR)) * 0.2
    ir += lowpass(tail, 5000)
    ir /= np.sum(np.abs(ir)) + 1e-9
    dry = np.concatenate([x, np.zeros(n)])
    wet = signal.fftconvolve(x, ir)[: len(dry)]
    wet = np.pad(wet, (0, len(dry) - len(wet)))
    return dry + wet * mix_amount * 3  # 控えめに（強いと最初の反射が叩いた瞬間の輪郭を濁す）


def air_bed(n, level=0.004, seed=0):
    """空気のかすかな雑音（録音には必ずある部屋の空気。完全な無音を避ける）。"""
    return lowpass(np.random.default_rng(seed).standard_normal(n), 6000, order=1) * level


def hit(kind, base, seconds, hardness=0.6, seed=0, count=60):
    """材質 kind の物を1回叩いた音: 物の響き（共鳴）に、当たった瞬間の接触音そのものを重ねる。
    実物の打撃音は「響き」だけでなく「接触」も聞こえる。これが無いと、こもって機械的になる。"""
    exc = strike(hardness, 0.002 + 0.006 * (1 - hardness), seed)
    body = norm(droop(resonate(exc, material(kind, base, count, seed), seconds)))
    contact = band(exc, 1200, 3000 + 6000 * hardness)
    contact = contact / (np.max(np.abs(contact)) + 1e-9) * (0.6 + 0.9 * hardness)
    body[: len(contact)] += contact[: len(body)]
    body += air_bed(len(body), seed=seed)
    return norm(body)


def rule_tone(semitone=0, seconds=0.6, seed=0):
    """法則の音: 能力ごとに音程が決まったモチーフ（A4 から五音で上がる）。ガラスの棒を指でこするように、
    少し長めの雑音で鳴らす（立ち上がりがやわらかく、うなりのある澄んだ音）。"""
    base = NOTE["A4"] * 2 ** (semitone / 12) * 0.5
    exc = np.random.default_rng(seed).standard_normal(int(0.05 * SR)) * np.hanning(int(0.05 * SR))
    out = norm(resonate(exc, material("glass", base, 30, seed), seconds))
    # 指がガラスをこする音（摩擦の雑音）を少し残す
    rub = band(exc, 1500, 6000)
    out[: len(rub)] += rub / (np.max(np.abs(rub)) + 1e-9) * 0.7
    out += air_bed(len(out), seed=seed)
    return norm(out)


# --- 持ち物（紙の札と本） -------------------------------------------------------


def ui_hover():
    """指したとき: 札の角に指が触れる小さな「チッ」。"""
    tick = lowpass(hit("paper", 1500, 0.06, 0.8, seed=1, count=40), 2200)
    tap = hit("wood", 420, 0.06, 0.6, seed=15)
    x = lowpass(mix(0.06, (tick, 0.0, 0.6), (tap, 0.0, 0.6)), 3500)
    return finish(fade(x, 0.001, 0.02), -37)


def ui_select():
    """選ぶ: 札を机に軽く当てる「トッ」（木の机＋紙）。"""
    desk = hit("wood", 330, 0.25, 0.5, seed=16)  # 甲高い振動が強く出ない木の個体を選んだ
    card = hit("paper", 1800, 0.08, 0.7, seed=3)
    x = lowpass(mix(0.25, (desk, 0.0, 1.0), (lowpass(card, 1500), 0.0, 0.15)), 4500)
    return finish(room(x, 0.4, 0.08, 2), -25)


def ui_confirm():
    """決定: 判を押す「トン」（木の判＋紙）。低めで、手ごたえのある音。"""
    stamp = hit("wood", NOTE["G4"] * 0.5, 0.3, 0.45, seed=4)
    card = hit("paper", 1200, 0.1, 0.6, seed=5)
    x = mix(0.26, (stamp, 0.0, 1.0), (card, 0.004, 0.5))
    return finish(room(x, 0.4, 0.1, 4), -23)


def ui_cancel():
    """取り消し: 札を手元へすべらせて戻す（紙のこすれ）。"""
    x = resonate(scrape(0.18, 500, seed=6), material("paper", 0, 50, 6), 0.22)
    return finish(fade(norm(x), 0.01, 0.06), -27)


def ui_open():
    """持ち物を開く: 本を開く（紙がめくれる「パラッ」と、背の小さなきしみ）。"""
    flutter = crackle(0.22, 900, 4000, seed=7) * envelope(int(0.22 * SR), 0.03, 0.12)
    spine = hit("wood", 180, 0.15, 0.4, seed=8)
    x = mix(0.28, (norm(flutter), 0.0, 1.0), (spine, 0.02, 0.6))
    return finish(room(x, 0.4, 0.1, 7), -25)


def ui_close():
    """閉じる: 本を閉じる「パタン」（空気が押し出される音と、表紙の当たり）。"""
    air = np.random.default_rng(9).standard_normal(int(0.06 * SR))
    puff_air = lowpass(air, 1500) * envelope(int(0.06 * SR), 0.03, 0.03)
    cover = hit("wood", 140, 0.2, 0.5, seed=9)
    x = mix(0.26, (puff_air, 0.0, 0.5), (cover, 0.05, 1.0))
    return finish(room(x, 0.5, 0.08, 9), -26, keep_low=True)


def ui_pick():
    """つまむ: 札を持ち上げる（紙が離れる短い「スッ」）。"""
    x = resonate(scrape(0.07, 900, seed=10), material("paper", 0, 50, 10), 0.09)
    return finish(fade(norm(x), 0.005, 0.03), -27)


def ui_drop():
    """置く: 札を置く「パサ」（紙＋木の机のごく小さな当たり）。"""
    card = resonate(scrape(0.05, 1500, seed=11), material("paper", 0, 50, 11), 0.08)
    desk = hit("wood", NOTE["E4"], 0.15, 0.4, seed=12)
    x = mix(0.16, (norm(lowpass(card, 5000)), 0.0, 0.6), (desk, 0.02, 0.8))
    return finish(x, -23)


def ui_error():
    """できない: 机を指の腹で2回「とん、とん」（低く鈍い。ブザーにしない）。"""
    a = hit("wood", 160, 0.18, 0.55, seed=13)
    b = hit("wood", 150, 0.2, 0.55, seed=14)
    x = mix(0.3, (a, 0.0, 1.0), (b, 0.12, 0.9))
    return finish(room(x, 0.3, 0.08, 13), -25, keep_low=True)


def radial_open():
    """円形 UI: 札を扇に広げる（紙を3枚すばやくはじく）。"""
    x = silence(0.32)
    for i in range(3):
        flick = resonate(strike(0.9, 0.002, seed=20 + i), material("paper", 0, 50, 20 + i), 0.1)
        x = place(x, norm(flick) * (0.7 + 0.15 * i), i * 0.045)
    return finish(x, -29)


# --- 能力（法則の音） -----------------------------------------------------------


def lend():
    """能力を渡す: 札をはじく音と、法則の音（音程は能力ごとに鳴らす側で変える）。受け取った物の音は別に鳴る。"""
    flick = norm(resonate(strike(0.9, 0.002, seed=30), material("paper", 0, 50, 30), 0.1))
    tone = rule_tone(0, 0.5, seed=31)
    x = mix(0.55, (flick, 0.0, 0.6), (tone, 0.03, 1.0))
    return finish(room(x, 0.6, 0.15, 30), -21)


def lend_range():
    """範囲に渡す: 法則の音が、少しずつずれて広がる（5つ重ねて、遅れとずれを付ける）。"""
    x = silence(0.6)
    for i, (shift, at) in enumerate([(0, 0.0), (0.06, 0.04), (-0.05, 0.08), (0.1, 0.13), (-0.08, 0.18)]):
        x = place(x, rule_tone(shift, 0.42, seed=40 + i) * (1.0 - 0.12 * i), at)
    flick = norm(resonate(strike(0.9, 0.002, seed=45), material("paper", 0, 50, 45), 0.1))
    x = place(x, flick * 0.6, 0.0)
    return finish(room(x, 0.6, 0.2, 40), -20)


def recall():
    """回収: 法則の音を逆にふくらませて、最後に札が手に戻る「パシッ」。"""
    tone = rule_tone(0, 0.4, seed=50)[::-1].copy() * np.linspace(0.2, 1.0, int(0.4 * SR))
    snap = norm(resonate(strike(0.9, 0.002, seed=51), material("paper", 0, 50, 51), 0.1))
    lift = norm(resonate(strike(0.9, 0.002, seed=52), material("paper", 0, 50, 52), 0.08))
    # 札が相手から離れる「ピッ」→ 法則の音がふくらみながら戻る → 手に戻る「パシッ」
    x = mix(0.55, (lift, 0.0, 0.8), (tone, 0.02, 0.45), (snap, 0.4, 1.0))
    return finish(fade(room(x, 0.6, 0.1, 50), 0.001, 0.05), -21)


def prohibit():
    """禁止: 封をする「ドン」（重い木の判）と、法則の音が半音ずれて濁る。怖くしない。"""
    stamp = hit("wood", 240, 0.3, 0.65, seed=60)
    a = rule_tone(0, 0.35, seed=61)
    b = rule_tone(1, 0.35, seed=62)
    x = mix(0.4, (stamp, 0.0, 1.0), (a, 0.02, 0.35), (b, 0.02, 0.35))
    return finish(room(x, 0.5, 0.1, 60), -24, keep_low=True)


def receive(kind, base, hardness, seed):
    """受け取った物が、自分の材質の声で応える。"""
    return finish(room(hit(kind, base, 0.3, hardness, seed), 0.6, 0.1, seed), -23, keep_low=True)


def receive_wood():
    """木のブロック・発射台が受け取った: 中が空の木箱の「コン」。"""
    return receive("wood", 260, 0.6, 70)


def receive_stone():
    """石・砂岩のセルが受け取った: 石の「コツ」（すぐ止まる）。"""
    return receive("stone", 400, 0.8, 71)


def receive_grass():
    """草の地面が受け取った: 土の鈍い「ボフ」と、草のこすれ。"""
    soil = hit("stone", 120, 0.2, 0.2, seed=72)
    grass = crackle(0.15, 700, 4500, seed=73) * envelope(int(0.15 * SR), 0.005, 0.1)
    x = mix(0.3, (soil, 0.0, 1.0), (norm(grass), 0.0, 0.5))
    return finish(room(x, 0.5, 0.08, 72), -23, keep_low=True)


def receive_creature():
    """生き物が受け取った: やわらかい体の「ぽむ」と、小さな鳴き声のような上がる息。"""
    body = hit("flesh", 260, 0.2, 0.85, seed=74)
    chirp = ocarina(NOTE["E4"], NOTE["A4"], 0.15, vibrato=9.0, breath=0.3) * 0.5
    x = mix(0.3, (body, 0.0, 1.0), (chirp, 0.01, 0.6))
    return finish(x, -23)


# --- 世界 ---------------------------------------------------------------------


def block_jump():
    """ブロックが跳ぶ: 木の板がしなって弾む（板のきしみ＋踏み切りの「ドッ」）。"""
    kick = hit("wood", 120, 0.15, 0.5, seed=80)
    creak = resonate(scrape(0.18, 600, seed=81), material("wood", 300, 40, 81), 0.25)
    x = mix(0.3, (kick, 0.0, 1.0), (norm(creak), 0.02, 0.4))
    return finish(room(x, 0.6, 0.08, 80), -19, keep_low=True)


def block_land():
    """ブロックが着地: 中が空の木箱を地面に置く「ゴトン」。"""
    a = hit("wood", 95, 0.25, 0.5, seed=82)
    b = hit("wood", 260, 0.12, 0.7, seed=83)
    x = mix(0.26, (a, 0.0, 1.0), (b, 0.0, 0.5))
    return finish(room(x, 0.6, 0.1, 82), -18, keep_low=True)


def block_step():
    """ブロックが1マス動く: 木箱を地面の上で引きずる（摩擦の引っかかり）。"""
    drag = resonate(scrape(0.38, 220, seed=84), material("wood", 150, 50, 84), 0.42)
    return finish(fade(norm(drag), 0.03, 0.08), -22, keep_low=True)


def player_jump():
    """自分の跳躍: 服がはためく「バサッ」（布のこすれ）。"""
    n = int(0.16 * SR)
    cloth = band(crackle(0.16, 1500, 3500, seed=85), 400, 3000) * envelope(n, 0.02, 0.1)
    return finish(norm(cloth), -28)


def player_land():
    """自分の着地: 草の上に降りる（土の「ドッ」と、草のくしゃっ）。"""
    soil = hit("stone", 90, 0.15, 0.2, seed=86)
    grass = crackle(0.12, 1200, 4500, seed=87) * envelope(int(0.12 * SR), 0.003, 0.08)
    x = mix(0.2, (soil, 0.0, 1.0), (norm(grass), 0.0, 0.6))
    return finish(x, -24, keep_low=True)


def footstep(seed):
    """草の上の足音（seed ごとに少しずつ違う。2026-11-21 から 4 種とも候補に置き換え、これは戻し先）: 草のくしゃっと、土のごく小さな当たり。"""
    grass = crackle(0.1, 1300 + seed * 200, 3600 + seed * 150, seed=90 + seed)
    grass *= envelope(int(0.1 * SR), 0.004, 0.07)
    soil = hit("stone", 100 + seed * 12, 0.08, 0.2, seed=95 + seed)
    x = mix(0.1, (norm(grass), 0.0, 0.8), (soil, 0.0, 0.5))
    return finish(x, -31, keep_low=True)


def save():
    """保存: 法則の音で、ここまでの能力のモチーフを上がる（A C D E）。札を綴じる小さな音から。"""
    x = silence(1.05)
    x = place(x, hit("wood", NOTE["G4"], 0.12, 0.6, seed=100) * 0.6, 0.0)
    for i, st in enumerate([0, 3, 5, 7]):
        x = place(x, rule_tone(st, 0.6, seed=101 + i) * 0.8, 0.05 + i * 0.1)
    return finish(room(x, 0.8, 0.18, 100), -21)


def goal():
    """到達: すべての法則の音が五音で上がり、最後に鐘が遠くで鳴る。"""
    x = silence(1.9)
    for i, st in enumerate([0, 2, 4, 7, 9, 12]):
        x = place(x, rule_tone(st, 0.7, seed=110 + i), i * 0.1)
    bell_tone = resonate(strike(0.6, 0.004, seed=120), material("bell", NOTE["C4"], 40, 120), 1.2)
    x = place(x, norm(bell_tone) * 0.6, 0.6)
    return finish(room(x, 1.0, 0.22, 110), -19)


def bell():
    """鐘: 村の鐘（教会の鐘の比の主音に、近い対のうなりと細かい振動を足した密なモード）。"""
    tone = resonate(strike(0.6, 0.004, seed=130), material("bell", NOTE["C4"], 60, 130), 2.0)
    return finish(room(norm(droop(tone, -8, 0.2)), 1.0, 0.15, 130), -19, keep_low=True)


def dash():
    """ダッシュ（T17 をやめるときの合成版）: 踏み込みの土の「ドッ」と、短い風。"""
    soil = hit("stone", 110, 0.12, 0.3, seed=140)
    air = band(np.random.default_rng(141).standard_normal(int(0.3 * SR)), 300, 2500)
    air *= envelope(int(0.3 * SR), 0.06, 0.2)
    x = mix(0.4, (soil, 0.0, 1.0), (norm(air), 0.03, 0.5))
    return finish(fade(x, 0.001, 0.08), -28, keep_low=True)


def ui_notice():
    """お知らせ（T21 をやめるときの合成版）: 木の音板を1回打つ（G4）。"""
    bar = hit("wood", NOTE["G4"], 0.3, 0.6, seed=150)
    return finish(room(fade(bar, 0.001, 0.08), 0.4, 0.1, 150), -26)


SOUNDS = {
    "ui_hover": lambda: adopted("ui_hover"),  # 合成版は ui_hover()
    "ui_select": lambda: adopted("ui_select"),  # 合成版は ui_select()
    "ui_confirm": lambda: adopted("ui_confirm"),  # 合成版は ui_confirm()
    "ui_cancel": lambda: adopted("ui_cancel"),  # 合成版は ui_cancel()
    "ui_open": lambda: adopted("ui_open"),  # 合成版は ui_open()
    "ui_close": lambda: adopted("ui_close"),  # 合成版は ui_close()
    "ui_pick": lambda: adopted("ui_pick"),  # 合成版は ui_pick()
    "ui_drop": lambda: adopted("ui_drop"),  # 合成版は ui_drop()
    "ui_error": lambda: adopted("ui_error"),  # 合成版は ui_error()
    "ui_notice": lambda: adopted("ui_notice"),  # 合成版は ui_notice()
    "radial_open": lambda: adopted("radial_open"),  # 合成版は radial_open()
    "lend": lambda: adopted("lend"),  # 合成版は lend()
    "lend_range": lambda: adopted("lend_range"),  # 合成版は lend_range()
    "recall": lambda: adopted("recall"),  # 合成版は recall()
    "prohibit": lambda: adopted("prohibit"),  # 合成版は prohibit()
    "receive_wood": lambda: adopted("receive_wood"),  # 合成版は receive_wood()
    "receive_stone": lambda: adopted("receive_stone"),  # 合成版は receive_stone()
    "receive_grass": lambda: adopted("receive_grass"),  # 合成版は receive_grass()
    "receive_creature": lambda: adopted("receive_creature"),  # 合成版は receive_creature()
    "block_jump": lambda: adopted("block_jump"),  # 合成版は block_jump()
    "block_land": lambda: adopted("block_land"),  # 合成版は block_land()
    "block_step": lambda: adopted("block_step"),  # 合成版は block_step()
    "player_jump": lambda: adopted("player_jump"),  # 合成版は player_jump()
    "player_land": lambda: adopted("player_land"),  # 合成版は player_land()
    "footstep_1": lambda: adopted("footstep_1"),  # 合成版は footstep(1)。以下 2〜4 も同じ
    "footstep_2": lambda: adopted("footstep_2"),
    "footstep_3": lambda: adopted("footstep_3"),
    "footstep_4": lambda: adopted("footstep_4"),
    "save": lambda: adopted("save"),  # 合成版は save()
    "goal": lambda: adopted("goal"),  # 合成版は goal()
    "bell": lambda: adopted("bell"),  # 合成版は bell()
    "dash": lambda: adopted("dash"),  # 合成版は dash()
}


def main():
    for name, build in SOUNDS.items():
        write(name, build())
    print(f"wrote {len(SOUNDS)} sounds to {OUT}")


if __name__ == "__main__":
    main()
