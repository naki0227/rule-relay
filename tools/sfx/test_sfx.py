"""効果音の基準（docs/sound-design.md）。「高すぎる・耳障り・小さなスピーカーで聞こえない」を数値で防ぐ。

    python3 -m unittest discover -s tools/sfx -p 'test_*.py'
"""

import hashlib
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import analyze  # noqa: E402
import build_sfx  # noqa: E402

IMPACTS = {"block_land", "block_jump"}  # 低い胴鳴りが本体の衝撃音
LONG = {"goal": 2300, "save": 1300}


class SoundBudget(unittest.TestCase):
    def setUp(self):
        self.files = sorted(analyze.SFX.glob("*.wav"))

    def test_every_sound_in_the_list_exists(self):
        names = {p.stem for p in self.files}
        self.assertEqual(names, set(build_sfx.SOUNDS))

    def test_not_harsh_or_high(self):
        for path in self.files:
            m = analyze.measure(path)
            with self.subTest(path.stem):
                self.assertLessEqual(m["peak_db"], -2.9, "peak headroom")
                self.assertLess(m["high_ratio"], 0.06, "energy above 4 kHz")
                self.assertLess(m["harsh_ratio"], 0.15, "energy in the harsh 2-5 kHz band")
                self.assertLess(m["dominant_hz"], 1100, "no high pitched fundamentals (C6 and up)")
                self.assertLess(m["centroid_hz"], 1500, "overall brightness")

    def test_audible_on_small_speakers(self):
        for path in self.files:
            m = analyze.measure(path)
            floor = 0.4 if path.stem in IMPACTS else 0.6
            with self.subTest(path.stem):
                self.assertGreaterEqual(m["small_speaker"], floor)

    def test_durations(self):
        for path in self.files:
            m = analyze.measure(path)
            name = path.stem
            limit = LONG.get(name, 80 if name == "ui_hover" else 450 if name.startswith("ui_") else 800)
            with self.subTest(name):
                self.assertLessEqual(m["ms"], limit)

    def test_ui_is_quieter_than_world(self):
        rms = {p.stem: analyze.measure(p)["rms_db"] for p in self.files}
        ui = max(v for k, v in rms.items() if k.startswith("ui_"))
        world = max(rms[k] for k in ["block_jump", "block_land", "lend", "goal"])
        self.assertLess(ui, world, "UI stays under gameplay sounds")


class Reproducible(unittest.TestCase):
    def test_build_is_deterministic(self):
        before = {p.stem: hashlib.sha256(p.read_bytes()).hexdigest() for p in analyze.SFX.glob("*.wav")}
        build_sfx.RNG = build_sfx.np.random.default_rng(20261118)
        for name, build in build_sfx.SOUNDS.items():
            data = build()
            pcm = (build_sfx.np.clip(data, -1, 1) * 32767).astype(build_sfx.np.int16).tobytes()
            path = analyze.SFX / f"{name}.wav"
            with self.subTest(name):
                self.assertIn(pcm, path.read_bytes(), "regenerate with tools/sfx/build_sfx.py")
        self.assertTrue(before)


if __name__ == "__main__":
    unittest.main()
