"""全効果音のスペクトログラム（0〜8kHz、縦軸は線形）を1枚に並べた PNG を書き出す。

    python3 tools/sfx/spectrogram_sheet.py <出力.png>
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analyze  # noqa: E402

W, H, COLS = 300, 150, 4


def spectrogram(x, sr):
    win = 1024
    hop = 128
    frames = [x[i : i + win] * np.hanning(win) for i in range(0, max(1, len(x) - win), hop)] or [
        np.pad(x, (0, win - len(x))) * np.hanning(win)
    ]
    spec = np.abs(np.fft.rfft(np.array(frames), axis=1)).T
    freqs = np.fft.rfftfreq(win, 1 / sr)
    spec = spec[freqs <= 8000]
    db = 20 * np.log10(spec + 1e-6)
    db = np.clip((db - db.max() + 70) / 70, 0, 1)
    return db[::-1]


def main():
    out = Path(sys.argv[1])
    files = sorted(analyze.SFX.glob("*.wav"))
    rows = (len(files) + COLS - 1) // COLS
    sheet = Image.new("RGB", (COLS * W, rows * (H + 22)), (255, 248, 236))
    draw = ImageDraw.Draw(sheet)
    for i, path in enumerate(files):
        x, sr = analyze.load(path)
        img = spectrogram(x, sr)
        rgb = np.stack([77 + img * 160, 58 + img * 120, 44 + img * 30], axis=-1).astype(np.uint8)
        tile = Image.fromarray(rgb).resize((W - 8, H))
        col, row = i % COLS, i // COLS
        sheet.paste(tile, (col * W + 4, row * (H + 22) + 20))
        draw.text((col * W + 6, row * (H + 22) + 4), f"{path.stem}  0-8kHz", fill=(77, 58, 44))
    sheet.save(out)


if __name__ == "__main__":
    main()
