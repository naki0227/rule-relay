"""効果音の基準（docs/sound-design.md）。「音程が高すぎる・シャリつく・こもる・小さなスピーカーで聞こえない」を数値で防ぐ。

    python3 -m unittest discover -s tools/sfx -p 'test_*.py'
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import analyze  # noqa: E402
import build_sfx  # noqa: E402

IMPACTS = {"block_land", "block_jump"}  # 低い胴鳴りが本体の衝撃音
LONG = {"goal": 2300, "save": 1300, "bell": 2300}
# 音程の無い雑音だけの音（服・草・足音）。主な周波数は偶然の山なので、音程の判定から外す
UNPITCHED = {
    "player_jump", "player_land", "footstep_1", "footstep_2", "footstep_3",
    "block_step", "radial_open",  # こする音、紙をはじく音
    "ui_hover", "ui_cancel", "ui_open", "ui_pick", "ui_drop",  # 紙の札・本の音（音程の無い雑音）
}


class SoundBudget(unittest.TestCase):
    def setUp(self):
        self.files = sorted(analyze.SFX.glob("*.wav"))

    def test_every_sound_in_the_list_exists(self):
        names = {p.stem for p in self.files}
        self.assertEqual(names, set(build_sfx.SOUNDS))

    def test_not_high_pitched_or_hissy(self):
        """「高い音」は音程（主な周波数）で防ぐ。明るさそのものは削らない（削るとこもる）。"""
        for path in self.files:
            m = analyze.measure(path)
            with self.subTest(path.stem):
                self.assertLessEqual(m["peak_db"], -2.9, "peak headroom")
                if path.stem not in UNPITCHED:
                    self.assertLess(m["dominant_hz"], 1100, "no high pitched fundamentals (C6 and up)")
                self.assertLess(m["centroid_hz"], 2600, "not shrill overall")
                self.assertLess(m["high_ratio"], 0.22, "not hissy above 4 kHz")
                self.assertLess(m["sizzle_ratio"], 0.015, "no sizzle above 9 kHz")
                self.assertLess(m["harsh_ratio"], 0.55, "2-5 kHz does not dominate")

    def test_not_muffled(self):
        """叩いた瞬間に耳の感度で 1.5kHz 以上の成分がある（輪郭がはっきりしている）。"""
        for path in self.files:
            m = analyze.measure(path)
            floor = 0.15 if path.stem in IMPACTS else 0.25
            with self.subTest(path.stem):
                self.assertGreaterEqual(m["clarity"], floor)

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
    def test_build_reproduces_the_committed_files(self):
        """スクリプトから同じ音が出る（原本のない音を防ぐ）。CPU やライブラリの違いによる
        最後の桁の差は許す（16bit の値で 2 まで）。"""
        np = build_sfx.np
        build_sfx.RNG = np.random.default_rng(20261118)
        for name, build in build_sfx.SOUNDS.items():
            fresh = (np.clip(build(), -1, 1) * 32767).astype(np.int16).astype(int)
            committed, _ = analyze.load(analyze.SFX / f"{name}.wav")
            committed = np.round(committed * 32768).astype(int)
            with self.subTest(name):
                self.assertEqual(len(fresh), len(committed), "regenerate with tools/sfx/build_sfx.py")
                self.assertLessEqual(int(np.max(np.abs(fresh - committed))), 2)


if __name__ == "__main__":
    unittest.main()
