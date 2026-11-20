# 音の候補 3回目（Stable Audio 3、2026-11-20）

2回目（`docs/sound-candidates-2026-11-20-round2.md`）でも合格が無かった4つと、新しく足した機能の音2つ（dash、ui_notice）。1イベントにつき seed を変えて4つ。
**ゲームの音（`assets/`）には触れていない。** 気に入ったものを ID（T01 など）で指定してもらえれば、rule-relay 側で取り込む。

> 追記（2026-11-20）: 本人の「採用できると判断したものは採用してよい」を受けて、2回目と同じ方法で測り直し、効果音 6 種を取り込んだ
> （T03→ui_confirm・T07→ui_error・T09→ui_open・T15→bell・T17→dash・T21→ui_notice）。下の「結果」の表の「採用」の列を参照。
> 選び方・採らなかった理由・聴いてほしい点は `docs/sound-design.md` の「5回目」。

- 生成: Audio Studio MCP 1.2.0（このMacでローカル生成）、モデル Stable Audio 3 medium（Stability AI、Hugging Face `stabilityai/stable-audio-3-optimized` の MLX 版 `dit_medium_f16`、リビジョン `30cb2644da54bfa63275d1bc7f1fa67fc718680f`）、steps 8、cfg 4.0。2026-11-20
- 置き場所: `art/audio/stable-audio/sfx3/<イベント名>_<n>.wav`（16bit モノラル 44.1kHz）。生成の設定は各ファイルの `.json` と `measurements.json`
- 加工と測定: `uv run --with numpy --with scipy --with soundfile python tools/sfx/stable_audio_candidates.py ~/AudioStudio --round 3`。基準は1・2回目と同じ。**外れたものも消さずに印を付けた**
- 長さの上限: dash は 500ms（0.3〜0.5 秒の指定から）。ui_notice は名前が `ui_` なので UI と同じ 450ms で、鳴りの余韻は 450ms で切っている（長くしたいときは上限を決めてもらえれば作り直す）
- ライセンスと規約: モデルの重みは Stability AI Community License。コンテストの規約で生成した音声が使えるかは、採用前に本人が確認する
- 限界: AI（Claude）は音を聴けない。数値は目安で、良し悪しは本人の耳で決める

## 結果

24 個のうち、基準をすべて満たしたのは **15 個**。

| イベント | 作り直す理由 | 合格した候補 | 追加のローパス | 採用 |
|---|---|---|---|---|
| ui_confirm | 2回目まで、こもり（頭の明るさ 1〜12%） | 3/4（T01・T03・T04） | — | **T03** |
| ui_error | 2回目まで、こもり | 2/4（T06・T07） | 6000Hz | **T07** |
| ui_open | 2回目まで、シャー（4kHz 以上が強い） | 2/4（T09・T11） | — | **T09** |
| bell | 2回目は低さは目標どおりだが、こもり | 1/4（T15） | — | **T15** |
| dash | 新しい音（3マスの突進） | 3/4（T17・T18・T19） | 4500Hz | **T17** |
| ui_notice | 新しい音（投票の開始・時間切れ） | 4/4（T21・T22・T23・T24） | — | **T21** |

## 直し方

- 依頼の方向どおりに題材を変えた: ui_confirm は「判を押す」をやめて小さな硬い木のブロックを硬い棒で打つ「カッ」、ui_error は同じブロックをやさしく2回、ui_open は紙をやめて木箱の留め金とふた、bell は硬い木槌で打つ鐘
- 全部 cfg 4。negative_prompt で、こもり（muffled, dull, thud）と、イベントごとに避けたい性質（ブザー・ビープ、紙のこすれ、金属のチャイム、SF の効果音など）を指定した
- 追加のローパス（4次）は、「なし／6000／4500／3500Hz」のうち、そのイベントの4つで合格がいちばん多い値（同じ数なら高い周波数）。ui_error は 6000Hz、dash は 4500Hz（6000Hz では合格2つ、4500Hz で3つ）

**試し直し（最初の試しで合格が少なかったイベント）**
試しの音はリポジトリに入れていない。プロンプトは下の表に残した。
- ui_open: 最初の「木箱のふた、warm low-mid」は、シャーは消えたが4つともこもった（頭の明るさ 0〜4%）→ ui_confirm で効いた「dense maple, crisp dry wooden click」を足して作り直した
- bell: 3回試した
  1. 「medium-sized low bell＋hard wooden mallet」: 打つ瞬間ははっきりした（28〜56%）が、主な周波数が 1371Hz（強い倍音）に上がった。次に強いのは 233Hz と 1146Hz なので、ローパスではこもらせずに下げられない
  2. 「large low bell」: 4つともこもった（0〜6%、主な周波数 78〜360Hz）
  3. 「medium-sized village bell＋hard mallet、高い倍音を negative_prompt で抑える」: T15 が 557Hz・明るさ 26% で合格。合格があったこの組を候補にした
  - このモデルでは、鐘の「大きさ（低さ）」と「打つ瞬間の明るさ」が一緒に動く。低くすると柔らかくなり、はっきりさせると高い倍音が勝つ

## 測って分かったこと（AI の見立て）

- **ui_confirm と ui_error は「小さな硬い木のブロック」で直った。** 2回目までの「判子」「指で机」より、題材を変えたのが効いた
- ui_error の T05・T08 は主な周波数が 3962Hz（甲高い「カン」）。T06・T07 を先に聴いてほしい
- ui_notice は4つとも合格。T21 は 213Hz と低く、T22〜T24 は 700〜820Hz
- dash の T20 はこもり判定（踏み込みの「ドッ」だけで風の音が弱い）

## 聴いてほしい順番

1. bell（T13〜T16）
2. 新しい音: dash（T17〜T20）、ui_notice（T21〜T24）
3. ui_confirm（T01〜T04）、ui_error（T05〜T08）、ui_open（T09〜T12）

## 一覧

印の意味: muffled＝頭 20ms が暗い（こもる）／>4k・>9k＝シャー・シャリ／centroid＝全体が甲高い／2-5k＝耳障りな帯域が多い／main≥1100Hz＝主な音程が C6 以上。LP＝追加のローパス

| ID | ファイル | seed | cfg | LP | 長さ | 主な周波数 | 頭20msの明るさ | 重心 | >4k | >9k | 250Hz以上(A) | 印 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **T01** | `sfx3/ui_confirm_1.wav` | 5000 | 4.0 | — | 450ms | 689Hz | 67% | 2053Hz | 9% | 0.4% | 100% | ok |
| **T02** | `sfx3/ui_confirm_2.wav` | 5001 | 4.0 | — | 450ms | 3100Hz | 98% | 3634Hz | 29% | 0.2% | 100% | ⚠ main≥1100Hz centroid >4k 2-5k |
| **T03** | `sfx3/ui_confirm_3.wav` | 5002 | 4.0 | — | 450ms | 689Hz | 47% | 1784Hz | 9% | 0.4% | 100% | ok |
| **T04** | `sfx3/ui_confirm_4.wav` | 5003 | 4.0 | — | 450ms | 691Hz | 56% | 2129Hz | 8% | 0.0% | 100% | ok |
| **T05** | `sfx3/ui_error_1.wav` | 5010 | 4.0 | 6000Hz | 450ms | 3962Hz | 87% | 4420Hz | 61% | 0.0% | 100% | ⚠ main≥1100Hz centroid >4k 2-5k |
| **T06** | `sfx3/ui_error_2.wav` | 5011 | 4.0 | 6000Hz | 450ms | 1033Hz | 97% | 2502Hz | 8% | 0.0% | 100% | ok |
| **T07** | `sfx3/ui_error_3.wav` | 5012 | 4.0 | 6000Hz | 450ms | 333Hz | 97% | 746Hz | 4% | 0.0% | 97% | ok |
| **T08** | `sfx3/ui_error_4.wav` | 5013 | 4.0 | 6000Hz | 450ms | 3962Hz | 88% | 3212Hz | 43% | 0.1% | 100% | ⚠ main≥1100Hz centroid >4k |
| **T09** | `sfx3/ui_open_1.wav` | 5320 | 4.0 | — | 450ms | 707Hz | 48% | 1906Hz | 12% | 0.2% | 100% | ok |
| **T10** | `sfx3/ui_open_2.wav` | 5321 | 4.0 | — | 450ms | 702Hz | 14% | 2346Hz | 20% | 0.1% | 100% | ⚠ muffled |
| **T11** | `sfx3/ui_open_3.wav` | 5322 | 4.0 | — | 450ms | 722Hz | 45% | 1831Hz | 18% | 0.1% | 99% | ok |
| **T12** | `sfx3/ui_open_4.wav` | 5323 | 4.0 | — | 450ms | 711Hz | 22% | 3574Hz | 48% | 1.4% | 100% | ⚠ centroid >4k muffled |
| **T13** | `sfx3/bell_1.wav` | 5630 | 4.0 | — | 2300ms | 1339Hz | 38% | 1431Hz | 3% | 0.0% | 100% | ⚠ main≥1100Hz |
| **T14** | `sfx3/bell_2.wav` | 5631 | 4.0 | — | 2300ms | 1342Hz | 10% | 1101Hz | 1% | 0.0% | 100% | ⚠ main≥1100Hz muffled |
| **T15** | `sfx3/bell_3.wav` | 5632 | 4.0 | — | 2300ms | 557Hz | 26% | 883Hz | 2% | 0.0% | 99% | ok |
| **T16** | `sfx3/bell_4.wav` | 5633 | 4.0 | — | 2300ms | 1322Hz | 60% | 1651Hz | 7% | 0.1% | 100% | ⚠ main≥1100Hz |
| **T17** | `sfx3/dash_1.wav` | 5040 | 4.0 | 4500Hz | 500ms | 126Hz | 32% | 500Hz | 2% | 0.0% | 82% | ok |
| **T18** | `sfx3/dash_2.wav` | 5041 | 4.0 | 4500Hz | 500ms | 176Hz | 29% | 883Hz | 1% | 0.0% | 95% | ok |
| **T19** | `sfx3/dash_3.wav` | 5042 | 4.0 | 4500Hz | 500ms | 266Hz | 32% | 1505Hz | 17% | 0.0% | 97% | ok |
| **T20** | `sfx3/dash_4.wav` | 5043 | 4.0 | 4500Hz | 500ms | 364Hz | 1% | 440Hz | 0% | 0.0% | 97% | ⚠ muffled |
| **T21** | `sfx3/ui_notice_1.wav` | 5050 | 4.0 | — | 450ms | 213Hz | 71% | 1538Hz | 11% | 0.0% | 98% | ok |
| **T22** | `sfx3/ui_notice_2.wav` | 5051 | 4.0 | — | 450ms | 698Hz | 62% | 976Hz | 4% | 0.0% | 96% | ok |
| **T23** | `sfx3/ui_notice_3.wav` | 5052 | 4.0 | — | 450ms | 824Hz | 57% | 1671Hz | 11% | 0.1% | 99% | ok |
| **T24** | `sfx3/ui_notice_4.wav` | 5053 | 4.0 | — | 450ms | 820Hz | 62% | 1527Hz | 18% | 0.3% | 98% | ok |

## プロンプト（同じイベントの4つは seed だけが違う。サーバーが付けた先頭の `TrackType: SFX,` を含む）

| イベント | プロンプト | negative_prompt |
|---|---|---|
| ui_confirm | `TrackType: SFX, a small hardwood block struck with a hard wooden stick, one dry wooden clack with a crisp click at the very start, very short decay, dense maple block, dry, articulate, woody mid tone, close-miked, dry, no reverb.` | `muffled, dull, boomy, distant, reverb, thud, low-pass filtered, metallic` |
| ui_error | `TrackType: SFX, a small hardwood block tapped twice with a felt-tipped wooden stick, two soft dry clacks in quick succession, the second slightly lower, rounded but clear attack, gentle not alarming, dense maple block, dry, warm woody mid tone, articulate, close-miked, dry, no reverb.` | `muffled, dull, boomy, distant, reverb, thud, low-pass filtered, buzzer, beep, electronic, metallic` |
| ui_open | `TrackType: SFX, a small hardwood box with a wooden latch being opened, a crisp dry wooden click as the latch flips open, then the lid lifts with a short soft creak, dense maple box and lid, dry, articulate woody tone, no paper rustle, close-miked, dry, no reverb.` | `paper rustle, page flip, hiss, sizzle, airy noise, squeaky door, metal hinge, muffled, dull, thud, boomy, reverb` |
| bell | `TrackType: SFX, a medium-sized bronze village bell hanging in a wooden frame, struck with a hard wooden mallet, a clear crisp knock of the mallet at the very start, then a warm mid-low ring that sustains and slowly fades, cast bronze, warm mid-low pitch, mellow overtones, round, outdoors, close, open air.` | `soft mallet, felt, muffled, dull, distant, high-pitched ringing, shrill overtones, tinkling, chime, glockenspiel, sub bass rumble, gong` |
| dash | `TrackType: SFX, a small character dashing forward quickly across grass, a light push-off thump of a foot at the start, then a short soft whoosh of air moving past, quick and over in half a second, soft shoe on earth and moving air, warm, rounded, no hiss, close-up, outdoors, dry.` | `hiss, sizzle, white noise, harsh, shrill, jet, sword swing, laser, sci-fi, reverb, long tail` |
| ui_notice | `TrackType: SFX, a single wooden tone bar struck once with a hard wooden mallet, one gentle attention-getting note with a clear crisp attack, then a short warm resonant ring that fades, rosewood bar over a wooden resonator box, low-mid pitch, warm and round, not shrill, close-miked, small wooden room, light short reverb.` | `muffled, dull, distant, high-pitched, shrill, tinkling, glockenspiel, metal chime, beep, electronic, alarm, sub bass rumble` |

### 採用しなかった試しのプロンプト

| イベント | 試し | seed | プロンプト | negative_prompt |
|---|---|---|---|---|
| bell | 1 | 5030〜5033 | `TrackType: SFX, a medium-sized low bronze bell hanging in a wooden frame, struck with a hard wooden mallet, a clear hard strike transient with a crisp knock at the very start, then a warm long low ring with slow gentle beating, cast bronze, warm low-mid tone, round, not shrill, outdoors, close, open air.` | `soft mallet, felt, muffled, dull, distant, tiny bell, tinkling, chime, glockenspiel, shrill, sub bass rumble, gong` |
| bell | 2 | 5330〜5333 | `TrackType: SFX, a large low bronze bell hanging in a wooden frame, struck with a hard wooden mallet, a clear hard strike transient with a crisp knock at the very start, then a warm long low hum and ring with slow gentle beating, thick cast bronze, low warm fundamental, round, not shrill, outdoors, close, open air.` | `soft mallet, felt, muffled, dull, distant, small bell, tinkling, chime, glockenspiel, shrill, high-pitched ringing, gong` |
| ui_open | 1 | 5020〜5023 | `TrackType: SFX, the hinged lid of a small wooden box being opened, a clear little knock as the latch releases, then a short soft creak of the hinge as the lid lifts, pine box and wooden lid, warm low-mid woody tone, no paper rustle, no hiss, close-miked, dry, small room.` | `paper rustle, page flip, hiss, sizzle, crackle, airy noise, shrill, squeaky door, metal hinge, muffled, reverb` |
