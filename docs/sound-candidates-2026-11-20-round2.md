# 音の候補 2回目（Stable Audio 3、2026-11-20）

1回目（`docs/sound-candidates-2026-11-20.md`）で基準を外れたイベントを作り直した候補。1イベントにつき seed を変えて3つ。
1回目で基準を満たした ui_hover・receive_stone・block_jump・block_step・player_jump・save は、ゲームに取り込み中なので作っていない。
**ゲームの音（`assets/`）には触れていない。** 気に入ったものを ID（R01 など）で指定してもらえれば、rule-relay 側で取り込む。

- 生成: Audio Studio MCP 1.2.0（このMacでローカル生成）、モデル Stable Audio 3 medium（Stability AI、`stabilityai/stable-audio-3-optimized` の MLX 版、`dit_medium_f16`、リビジョン `30cb264`）、steps 8。2026-11-20
- 置き場所: `art/audio/stable-audio/sfx2/<イベント名>_<n>.wav`（16bit モノラル 44.1kHz）。生成の設定は各ファイルの `.json` と `measurements.json`
- 加工と測定: `uv run --with numpy --with scipy --with soundfile python tools/sfx/stable_audio_candidates.py ~/AudioStudio --round 2`。基準は1回目と同じ（`tools/sfx/test_sfx.py`）。**外れたものも消さずに印を付けた**
- ライセンスと規約: モデルの重みは Stability AI Community License。コンテストの規約で生成した音声が使えるかは、採用前に本人が確認する（1回目と同じ）
- 限界: AI（Claude）は音を聴けない。数値は目安で、良し悪しは本人の耳で決める

## 結果

63 個のうち、基準をすべて満たしたのは **29 個**（1回目は同じイベントで 0 個）。

| イベント | 1回目の印 | 合格した候補 |
|---|---|---|
| ui_select | こもり | 2/3 （R01・R03） |
| ui_confirm | こもり | 0/3  |
| ui_close | こもり | 1/3 （R09） |
| ui_drop | こもり | 2/3 （R11・R12） |
| ui_error | こもり | 0/3  |
| prohibit | こもり | 2/3 （R16・R18） |
| receive_wood | こもり | 1/3 （R19） |
| receive_creature | こもり | 2/3 （R22・R24） |
| block_land | こもり | 1/3 （R26） |
| ui_cancel | シャー | 3/3 （R28・R29・R30） |
| ui_open | シャー | 0/3  |
| ui_pick | シャー | 1/3 （R36） |
| radial_open | シャー | 2/3 （R38・R39） |
| lend | シャー | 1/3 （R40） |
| lend_range | シャー | 1/3 （R43） |
| recall | シャー | 2/3 （R46・R47） |
| receive_grass | シャー | 2/3 （R49・R50） |
| player_land | シャー | 2/3 （R52・R53） |
| footstep | シャー | 3/3 （R55・R56・R57） |
| bell | 高すぎ | 0/3  |
| goal | 高すぎ | 1/3 （R63） |

## 直し方

**生成（プロンプト）**
- こもり組: cfg を 4 に上げ、「crisp transient」「a clear click at the start」と書き、negative_prompt に「muffled, dull, boomy, distant, reverb」を入れた
- シャー組: cfg を 4 に上げ、「rolled-off highs, no hiss, warm」と書き、negative_prompt に「hiss, sizzle, crackle, harsh, bright」を入れた
- 鐘: 中くらいの大きさの鐘（medium-sized bronze bell）。negative_prompt に「tiny bell, tinkling, chime, glockenspiel」を入れた

**加工**
- 1回目と同じ（モノラル → 150Hz 未満を切る・9kHz より上を弱める → 頭の無音を切る → 長さの上限で切る → ピークをそろえる）
- 追加のローパス（4次）を一部のイベントにだけ掛けた。値は「なし／6000／4500／3500Hz」のうち、そのイベントの3つで基準を満たす数がいちばん多い値（同じ数なら高い周波数）。イベントの中では3つとも同じ値: ui_select 3500Hz、ui_drop 6000Hz、prohibit 6000Hz、radial_open 6000Hz、receive_grass 3500Hz、player_land 3500Hz、footstep 3500Hz

**試し直し（1回の試しで合格が 0 個だったイベント）**
最初の試しで合格が 0 個だった11イベントは、プロンプトを変えて作り直し、作り直した方を候補にした（1イベント3つは変えていない）。試しの音はリポジトリに入れていない。
- ui_select: 「bright」と書いたら 4kHz 以上が 59〜93% と明るくなりすぎた → 「warm mid-low body」に変え、甲高さを negative_prompt に入れた（この時点で他のイベントにも同じ書き方を使った）
- ui_confirm・ui_drop・ui_error・block_land: 甲高さを negative_prompt に入れると、頭がまた暗くなった → negative_prompt から高域の言葉を外して「crisp dry clack」と書き、高すぎる分は加工のローパスで削った
- ui_open・receive_grass・player_land・footstep: 「warm, rolled-off highs」と cfg 4 では、高域が消えて今度はこもった → cfg を既定の 1.0 に戻して輪郭を残し、高域は加工のローパスで削った
- bell: 「large deep bell」で主な周波数が 77〜141Hz まで下がり、こもった → 「medium-sized」に変えた
- goal: 主な周波数は 330〜470Hz と目標に入ったが、こもった → 「clear crisp bell strike」を足した

## 測って分かったこと（AI の見立て）

- **叩く音はまだ難しい**: ui_confirm と ui_error は2回の試しとも全部こもった（頭 20ms の明るさが 1〜12%）。このモデルは「判を押す」「指で机をたたく」を、頭の暗い「ドッ」として出す傾向がある。block_land も3つのうち1つだけ（明るさ 19%、衝撃音の基準は 15%）
- **鐘は音程と明るさの両立が難しい**: bell_1（649Hz）と bell_3（462Hz）は主な周波数が目標の 400〜900Hz に入ったが、打った瞬間が柔らかく、こもりの判定になった。goal_3 は 467Hz で全部の基準を満たした
- **ローパスを 3500Hz まで下げた音**（ui_select・receive_grass・player_land・footstep）は、数値上はこもっていないが、聴くと少し丸く感じるかもしれない
- 2回目では cfg 4 の候補と cfg 1.0 の候補が混じっている（各ファイルの .json の cfg を参照）

## 聴いてほしい順番

1. goal（R61〜R63）、block_land（R25〜R27）、bell（R58〜R60）
2. UI: R01〜R15（select・confirm・close・drop・error）、R28〜R36（cancel・open・pick）
3. 残り

## 一覧

印の意味: muffled＝頭 20ms が暗い（こもる）／>4k・>9k＝シャー・シャリ／centroid＝全体が甲高い／2-5k＝耳障りな帯域が多い／main≥1100Hz＝主な音程が C6 以上。LP＝追加のローパス

| ID | ファイル | seed | cfg | LP | 長さ | 主な周波数 | 頭20msの明るさ | 重心 | >4k | >9k | 250Hz以上(A) | 印 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **R01** | `sfx2/ui_select_1.wav` | 4000 | 4.0 | 3500Hz | 450ms | 249Hz | 100% | 1159Hz | 2% | 0.0% | 96% | ok |
| **R02** | `sfx2/ui_select_2.wav` | 4001 | 4.0 | 3500Hz | 450ms | 1049Hz | 11% | 1096Hz | 2% | 0.0% | 100% | ⚠ muffled |
| **R03** | `sfx2/ui_select_3.wav` | 4002 | 4.0 | 3500Hz | 450ms | 976Hz | 56% | 1622Hz | 9% | 0.0% | 100% | ok |
| **R04** | `sfx2/ui_confirm_1.wav` | 4310 | 4.0 | — | 450ms | 227Hz | 11% | 2046Hz | 12% | 1.3% | 98% | ⚠ muffled |
| **R05** | `sfx2/ui_confirm_2.wav` | 4311 | 4.0 | — | 450ms | 231Hz | 9% | 830Hz | 4% | 0.5% | 97% | ⚠ muffled |
| **R06** | `sfx2/ui_confirm_3.wav` | 4312 | 4.0 | — | 450ms | 531Hz | 12% | 1234Hz | 6% | 1.9% | 99% | ⚠ >9k muffled |
| **R07** | `sfx2/ui_close_1.wav` | 4020 | 4.0 | — | 450ms | 793Hz | 9% | 859Hz | 3% | 0.1% | 99% | ⚠ muffled |
| **R08** | `sfx2/ui_close_2.wav` | 4021 | 4.0 | — | 450ms | 218Hz | 16% | 965Hz | 8% | 0.2% | 96% | ⚠ muffled |
| **R09** | `sfx2/ui_close_3.wav` | 4022 | 4.0 | — | 450ms | 231Hz | 70% | 665Hz | 2% | 0.1% | 96% | ok |
| **R10** | `sfx2/ui_drop_1.wav` | 4330 | 4.0 | 6000Hz | 450ms | 529Hz | 12% | 1254Hz | 7% | 0.0% | 100% | ⚠ muffled |
| **R11** | `sfx2/ui_drop_2.wav` | 4331 | 4.0 | 6000Hz | 450ms | 698Hz | 32% | 1513Hz | 11% | 0.0% | 99% | ok |
| **R12** | `sfx2/ui_drop_3.wav` | 4332 | 4.0 | 6000Hz | 450ms | 236Hz | 52% | 1629Hz | 12% | 0.0% | 99% | ok |
| **R13** | `sfx2/ui_error_1.wav` | 4340 | 4.0 | — | 450ms | 231Hz | 8% | 717Hz | 1% | 0.0% | 95% | ⚠ muffled |
| **R14** | `sfx2/ui_error_2.wav` | 4341 | 4.0 | — | 450ms | 231Hz | 9% | 714Hz | 0% | 0.1% | 96% | ⚠ muffled |
| **R15** | `sfx2/ui_error_3.wav` | 4342 | 4.0 | — | 450ms | 513Hz | 4% | 1342Hz | 11% | 0.8% | 100% | ⚠ muffled |
| **R16** | `sfx2/prohibit_1.wav` | 4050 | 4.0 | 6000Hz | 800ms | 156Hz | 94% | 366Hz | 1% | 0.0% | 92% | ok |
| **R17** | `sfx2/prohibit_2.wav` | 4051 | 4.0 | 6000Hz | 800ms | 120Hz | 8% | 298Hz | 0% | 0.0% | 84% | ⚠ muffled |
| **R18** | `sfx2/prohibit_3.wav` | 4052 | 4.0 | 6000Hz | 800ms | 148Hz | 73% | 1205Hz | 13% | 0.0% | 96% | ok |
| **R19** | `sfx2/receive_wood_1.wav` | 4060 | 4.0 | — | 800ms | 861Hz | 74% | 845Hz | 2% | 0.2% | 99% | ok |
| **R20** | `sfx2/receive_wood_2.wav` | 4061 | 4.0 | — | 800ms | 420Hz | 5% | 458Hz | 0% | 0.0% | 99% | ⚠ muffled |
| **R21** | `sfx2/receive_wood_3.wav` | 4062 | 4.0 | — | 800ms | 424Hz | 12% | 437Hz | 0% | 0.0% | 97% | ⚠ muffled |
| **R22** | `sfx2/receive_creature_1.wav` | 4070 | 4.0 | — | 800ms | 366Hz | 37% | 1140Hz | 11% | 0.8% | 97% | ok |
| **R23** | `sfx2/receive_creature_2.wav` | 4071 | 4.0 | — | 800ms | 135Hz | 20% | 786Hz | 3% | 0.5% | 98% | ⚠ muffled |
| **R24** | `sfx2/receive_creature_3.wav` | 4072 | 4.0 | — | 800ms | 238Hz | 29% | 529Hz | 2% | 0.5% | 91% | ok |
| **R25** | `sfx2/block_land_1.wav` | 4380 | 4.0 | — | 800ms | 248Hz | 4% | 815Hz | 2% | 0.2% | 97% | ⚠ muffled |
| **R26** | `sfx2/block_land_2.wav` | 4381 | 4.0 | — | 800ms | 781Hz | 19% | 1029Hz | 5% | 0.8% | 98% | ok |
| **R27** | `sfx2/block_land_3.wav` | 4382 | 4.0 | — | 800ms | 861Hz | 14% | 1586Hz | 10% | 0.9% | 100% | ⚠ muffled |
| **R28** | `sfx2/ui_cancel_1.wav` | 4090 | 4.0 | — | 450ms | 162Hz | 72% | 596Hz | 2% | 0.1% | 89% | ok |
| **R29** | `sfx2/ui_cancel_2.wav` | 4091 | 4.0 | — | 450ms | 249Hz | 38% | 704Hz | 2% | 0.4% | 95% | ok |
| **R30** | `sfx2/ui_cancel_3.wav` | 4092 | 4.0 | — | 450ms | 247Hz | 80% | 2399Hz | 16% | 0.7% | 99% | ok |
| **R31** | `sfx2/ui_open_1.wav` | 4400 | 1.0 | — | 450ms | 2613Hz | 67% | 3605Hz | 34% | 1.2% | 100% | ⚠ centroid >4k 2-5k |
| **R32** | `sfx2/ui_open_2.wav` | 4401 | 1.0 | — | 450ms | 3438Hz | 54% | 3177Hz | 26% | 0.8% | 100% | ⚠ centroid >4k 2-5k |
| **R33** | `sfx2/ui_open_3.wav` | 4402 | 1.0 | — | 450ms | 2860Hz | 99% | 3716Hz | 38% | 1.4% | 100% | ⚠ centroid >4k |
| **R34** | `sfx2/ui_pick_1.wav` | 4110 | 4.0 | — | 450ms | 2493Hz | 28% | 4076Hz | 37% | 10.8% | 100% | ⚠ centroid >4k >9k |
| **R35** | `sfx2/ui_pick_2.wav` | 4111 | 4.0 | — | 450ms | 349Hz | 0% | 1269Hz | 1% | 0.6% | 100% | ⚠ muffled |
| **R36** | `sfx2/ui_pick_3.wav` | 4112 | 4.0 | — | 450ms | 1760Hz | 80% | 2271Hz | 5% | 0.7% | 100% | ok |
| **R37** | `sfx2/radial_open_1.wav` | 4120 | 4.0 | 6000Hz | 800ms | 158Hz | 3% | 1317Hz | 7% | 0.0% | 97% | ⚠ muffled |
| **R38** | `sfx2/radial_open_2.wav` | 4121 | 4.0 | 6000Hz | 800ms | 524Hz | 100% | 755Hz | 3% | 0.0% | 99% | ok |
| **R39** | `sfx2/radial_open_3.wav` | 4122 | 4.0 | 6000Hz | 800ms | 198Hz | 72% | 889Hz | 0% | 0.0% | 96% | ok |
| **R40** | `sfx2/lend_1.wav` | 4130 | 4.0 | — | 800ms | 108Hz | 80% | 809Hz | 6% | 0.6% | 85% | ok |
| **R41** | `sfx2/lend_2.wav` | 4131 | 4.0 | — | 800ms | 129Hz | 20% | 273Hz | 1% | 0.1% | 63% | ⚠ muffled |
| **R42** | `sfx2/lend_3.wav` | 4132 | 4.0 | — | 800ms | 198Hz | 0% | 1285Hz | 10% | 1.2% | 90% | ⚠ muffled |
| **R43** | `sfx2/lend_range_1.wav` | 4140 | 4.0 | — | 800ms | 581Hz | 95% | 1425Hz | 10% | 0.2% | 99% | ok |
| **R44** | `sfx2/lend_range_2.wav` | 4141 | 4.0 | — | 800ms | 285Hz | 11% | 617Hz | 2% | 0.2% | 90% | ⚠ muffled |
| **R45** | `sfx2/lend_range_3.wav` | 4142 | 4.0 | — | 800ms | 289Hz | 0% | 726Hz | 3% | 0.2% | 95% | ⚠ muffled |
| **R46** | `sfx2/recall_1.wav` | 4150 | 4.0 | — | 800ms | 134Hz | 56% | 919Hz | 7% | 0.4% | 93% | ok |
| **R47** | `sfx2/recall_2.wav` | 4151 | 4.0 | — | 800ms | 135Hz | 98% | 697Hz | 4% | 0.2% | 91% | ok |
| **R48** | `sfx2/recall_3.wav` | 4152 | 4.0 | — | 800ms | 134Hz | 10% | 1729Hz | 14% | 1.8% | 98% | ⚠ >9k muffled |
| **R49** | `sfx2/receive_grass_1.wav` | 4460 | 1.0 | 3500Hz | 800ms | 538Hz | 79% | 1758Hz | 7% | 0.0% | 100% | ok |
| **R50** | `sfx2/receive_grass_2.wav` | 4461 | 1.0 | 3500Hz | 800ms | 365Hz | 82% | 1135Hz | 2% | 0.0% | 99% | ok |
| **R51** | `sfx2/receive_grass_3.wav` | 4462 | 1.0 | 3500Hz | 800ms | 1445Hz | 73% | 2277Hz | 6% | 0.0% | 100% | ⚠ main≥1100Hz |
| **R52** | `sfx2/player_land_1.wav` | 4470 | 1.0 | 3500Hz | 800ms | 155Hz | 81% | 1852Hz | 1% | 0.0% | 99% | ok |
| **R53** | `sfx2/player_land_2.wav` | 4471 | 1.0 | 3500Hz | 800ms | 1548Hz | 81% | 1806Hz | 2% | 0.0% | 100% | ok |
| **R54** | `sfx2/player_land_3.wav` | 4472 | 1.0 | 3500Hz | 800ms | 2881Hz | 59% | 2148Hz | 2% | 0.0% | 100% | ⚠ 2-5k |
| **R55** | `sfx2/footstep_1.wav` | 4480 | 1.0 | 3500Hz | 800ms | 784Hz | 64% | 1996Hz | 4% | 0.0% | 100% | ok |
| **R56** | `sfx2/footstep_2.wav` | 4481 | 1.0 | 3500Hz | 800ms | 796Hz | 44% | 1672Hz | 2% | 0.0% | 100% | ok |
| **R57** | `sfx2/footstep_3.wav` | 4482 | 1.0 | 3500Hz | 800ms | 734Hz | 70% | 1847Hz | 3% | 0.0% | 100% | ok |
| **R58** | `sfx2/bell_1.wav` | 4490 | 4.0 | — | 2300ms | 649Hz | 3% | 1002Hz | 1% | 0.0% | 100% | ⚠ muffled |
| **R59** | `sfx2/bell_2.wav` | 4491 | 4.0 | — | 2300ms | 132Hz | 12% | 551Hz | 0% | 0.0% | 96% | ⚠ muffled |
| **R60** | `sfx2/bell_3.wav` | 4492 | 4.0 | — | 2300ms | 462Hz | 3% | 778Hz | 2% | 0.4% | 98% | ⚠ muffled |
| **R61** | `sfx2/goal_1.wav` | 4500 | 4.0 | — | 2300ms | 1644Hz | 54% | 1867Hz | 7% | 0.3% | 100% | ⚠ main≥1100Hz |
| **R62** | `sfx2/goal_2.wav` | 4501 | 4.0 | — | 2300ms | 1643Hz | 90% | 2435Hz | 18% | 0.2% | 100% | ⚠ main≥1100Hz |
| **R63** | `sfx2/goal_3.wav` | 4502 | 4.0 | — | 2300ms | 467Hz | 97% | 744Hz | 1% | 0.0% | 100% | ok |

## プロンプト（同じイベントの3つは seed だけが違う。サーバーが付けた先頭の `TrackType: SFX,` を含む）

| イベント | プロンプト | negative_prompt |
|---|---|---|
| ui_select | `TrackType: SFX, the edge of a stiff paper card tapped onto a hard maple desk, crisp transient with a clear click at the start, then a short warm woody tock that stops quickly, hard maple and cardstock, warm mid-low woody body, articulate attack, no hiss, close-miked, dry, no reverb.` | `muffled, dull, boomy, distant, reverb, harsh, shrill, hiss, high-pitched, metallic` |
| ui_confirm | `TrackType: SFX, a wooden hand stamp pressed firmly onto paper on a hardwood desk, a bright crisp click at the very start, then one firm short woody thump, boxwood stamp and paper on hardwood, articulate, present, woody, close-miked, dry, no reverb.` | `muffled, dull, boomy, distant, reverb, soft thud, low-pass filtered` |
| ui_close | `TrackType: SFX, a small cloth-bound hardcover book snapped shut, crisp transient as the covers meet with a clear clap at the start, a tiny puff of air, quick stop, board covers and paper block, warm mid-low clap, articulate attack, no hiss, close-miked, dry, no reverb.` | `muffled, dull, boomy, distant, reverb, harsh, shrill, hiss, high-pitched, metallic` |
| ui_drop | `TrackType: SFX, a stiff paper card dropped flat onto a hard wooden table, a crisp dry clack at the very start as the card hits, then a tiny papery settle, stiff cardstock on hard maple, articulate, present, woody, close-miked, dry, no reverb.` | `muffled, dull, boomy, distant, reverb, soft thud, low-pass filtered` |
| ui_error | `TrackType: SFX, a knuckle rapping twice on a hard wooden tabletop, two quick dry clacks in succession, each with a crisp click at the start, gentle not alarming, hard maple, articulate, present, woody knock, no buzzer, no beep, close-miked, dry, no reverb.` | `muffled, dull, boomy, distant, reverb, soft thud, low-pass filtered, buzzer, beep` |
| prohibit | `TrackType: SFX, a heavy wooden seal stamp pressed down onto paper, crisp transient with a clear knock at the start, one firm thud, then a short low slightly detuned hum that settles, friendly not scary, dense hardwood and paper, warm low body, articulate attack, no hiss, close-miked, dry, small room.` | `muffled, dull, boomy, distant, reverb, harsh, shrill, hiss, high-pitched, metallic, scary` |
| receive_wood | `TrackType: SFX, a hollow wooden crate knocked once with a knuckle, crisp transient with a clear click at the start, one resonant knock, short hollow ring, dry pine boards, hollow box body, warm mid-low woody tone, articulate attack, no hiss, close-miked, outdoors, dry.` | `muffled, dull, boomy, distant, reverb, harsh, shrill, hiss, high-pitched, metallic` |
| receive_creature | `TrackType: SFX, a small soft round plush-like creature bouncing once on a wooden floor, a clear little pop at the start, then a soft rounded squishy bop and a tiny rising puff of breath, cute and short, soft fur and a springy body, warm mid tone, articulate attack, no hiss, close-miked, dry, no reverb.` | `muffled, dull, boomy, distant, reverb, harsh, shrill, hiss, high-pitched, squeak toy, cartoon boing` |
| block_land | `TrackType: SFX, a hollow wooden crate dropped onto hard packed earth, a crisp dry woody clack at the moment of impact, then a heavy short hollow thunk and a tiny rattle, pine boards, hollow box body, articulate, present, woody, close-miked, outdoors, dry.` | `muffled, dull, boomy, distant, reverb, soft thud, low-pass filtered, sub bass rumble` |
| ui_cancel | `TrackType: SFX, a paper card slid back across a wooden desk under a fingertip, one short smooth slide that stops softly with a tiny woody tap, thick cardstock on varnished wood, warm, soft, rolled-off highs, no hiss, close-up, dry, small room.` | `hiss, sizzle, crackle, harsh, bright, airy noise, shrill, white noise, swoosh` |
| ui_open | `TrackType: SFX, a small cloth-bound hardcover book being opened, the cover lifts with a clear soft knock of the spine, then a short flutter of thick pages settling, thick old paper and cloth board, warm, close and clear, close-up, dry, small room.` | — |
| ui_pick | `TrackType: SFX, a paper card picked up off a wooden table, one very short soft lift as the card leaves the surface, a tiny papery tick, thick cardstock, warm, soft, rolled-off highs, no hiss, close-up, dry, small room.` | `hiss, sizzle, crackle, harsh, bright, airy noise, shrill, white noise, swoosh` |
| radial_open | `TrackType: SFX, three thick paper cards fanned out by hand on a wooden table, a quick soft sequence of three gentle flicks spreading out, short, thick cardstock, warm papery taps, rolled-off highs, no hiss, close-up, dry, small room.` | `hiss, sizzle, crackle, harsh, bright, airy noise, shrill, white noise, swoosh` |
| lend | `TrackType: SFX, a paper card flicked from the fingers, then the rim of a large glass bowl rubbed with a wet fingertip, a soft papery flick followed by a short low singing tone that swells gently and fades, paper and thick glass, warm low round tone, soft beating, rolled-off highs, no hiss, close-up, small wooden room, light short reverb.` | `hiss, sizzle, crackle, harsh, bright, airy noise, shrill, white noise, high-pitched ringing` |
| lend_range | `TrackType: SFX, the rims of several large glass bowls rubbed with wet fingertips one after another, a soft staggered cluster of low singing tones spreading outward, swelling and fading together, thick glass, warm low round tones slightly detuned against each other, rolled-off highs, no hiss, small wooden room, light short reverb.` | `hiss, sizzle, crackle, harsh, bright, airy noise, shrill, white noise, high-pitched ringing` |
| recall | `TrackType: SFX, a low glass singing tone drawn back into a hand, ending with a thick paper card caught between fingers, the tone swells in like reversed audio, then a soft clear papery tap at the end, thick glass and cardstock, warm low round tone, rolled-off highs, no hiss, close-up, small wooden room, light short reverb.` | `hiss, sizzle, crackle, harsh, bright, airy noise, shrill, white noise, whoosh` |
| receive_grass | `TrackType: SFX, a hand patting a patch of grassy soil, one clear soft thump with a short rustle of grass blades, packed earth and grass, warm low body with a clear leafy edge, close-up, outdoors, dry.` | — |
| player_land | `TrackType: SFX, a small person landing on short grass after a hop, one clear soft thud of both feet with a short crunch of grass, soft shoes, packed earth and grass blades, warm low body with a clear leafy edge, close-up, outdoors, dry.` | — |
| footstep | `TrackType: SFX, a single footstep of a soft shoe on short grass, one light step, a clear soft pat with a quick crunch of grass, very short, grass blades over soil, warm, gentle and natural, close-up, outdoors, dry.` | — |
| bell | `TrackType: SFX, a medium-sized bronze village bell hanging in a wooden frame, struck once by its clapper, a clear crisp strike, then a warm mid-low ringing decay with slow gentle beating, cast bronze, warm mid-low tone, round and clear, not shrill, outdoors, short distance, open air.` | `tiny bell, tinkling, chime, glockenspiel, shrill, sleigh bell, sub bass rumble, muffled, distant gong` |
| goal | `TrackType: SFX, rims of glass bowls rubbed with wet fingertips, then a medium-sized bronze bell nearby, a quick rising sequence of warm singing tones, then one clear crisp bell strike ringing out and fading, joyful but calm, glass and cast bronze, warm mid-low tones, round and clear, not shrill, outdoors, open air, gentle natural reverb.` | `tiny bell, tinkling, chime, glockenspiel, shrill, sparkle, sub bass rumble, muffled, distant gong` |

### 採用しなかった最初の試しのプロンプト

| イベント | seed | cfg | プロンプト | negative_prompt |
|---|---|---|---|---|
| bell | 4190〜4192 | 4.0 | `TrackType: SFX, a large deep bronze temple bell hanging in a heavy wooden frame, struck once by a wooden beam, a clear strike then a long warm low ringing decay with slow gentle beating, thick cast bronze, low deep fundamental, warm and round, not shrill, outdoors, short distance, open air.` | `small bell, high-pitched, tinkling, chime, glockenspiel, shrill, sleigh bell, hiss` |
| block_land | 4080〜4082 | 4.0 | `TrackType: SFX, a hollow wooden crate dropped onto packed earth, crisp transient with a clear woody knock at the moment of impact, one heavy satisfying thunk, a brief rattle, quick decay, pine boards and packed earth, deep warm hollow body, articulate attack, no hiss, close-miked, outdoors, dry.` | `muffled, dull, boomy, distant, reverb, harsh, shrill, hiss, high-pitched, metallic` |
| footstep | 4180〜4182 | 4.0 | `TrackType: SFX, a single footstep of a soft shoe on short soft grass, one light step, a soft rounded pat with a gentle brush of grass, very short, soft grass over moist soil, warm, gentle, rolled-off highs, no hiss, close-up, outdoors, dry.` | `hiss, sizzle, crackle, harsh, bright, airy noise, shrill, white noise, dry leaves crunch, gravel` |
| goal | 4200〜4202 | 4.0 | `TrackType: SFX, rims of large glass bowls rubbed with wet fingertips, then a large deep bronze bell in the distance, a quick rising sequence of warm low singing tones, then one deep bell strike ringing out and fading, joyful but calm, thick glass and cast bronze, low deep warm tones, round, not shrill, outdoors, open air, gentle natural reverb.` | `small bell, high-pitched, tinkling, chime, glockenspiel, shrill, sparkle, hiss` |
| player_land | 4170〜4172 | 4.0 | `TrackType: SFX, a small person landing on soft grass after a hop, one soft rounded thud of both feet with a short gentle brush of grass, soft shoes, packed earth and soft grass, warm low body, rolled-off highs, no hiss, close-up, outdoors, dry.` | `hiss, sizzle, crackle, harsh, bright, airy noise, shrill, white noise, dry leaves crunch, gravel` |
| receive_grass | 4160〜4162 | 4.0 | `TrackType: SFX, a hand patting a patch of soft grassy soil, one soft rounded thump with a brief gentle brush of grass, moist packed earth and soft grass, warm low body, rolled-off highs, no hiss, close-up, outdoors, dry.` | `hiss, sizzle, crackle, harsh, bright, airy noise, shrill, white noise, dry leaves crunch` |
| ui_confirm | 4010〜4012 | 4.0 | `TrackType: SFX, a wooden hand stamp pressed firmly onto paper on a hardwood desk, crisp transient with a clear click at the start, then one firm warm thump that stops quickly, boxwood stamp, rubber and paper on hardwood, warm mid-low body, articulate attack, no hiss, close-miked, dry, no reverb.` | `muffled, dull, boomy, distant, reverb, harsh, shrill, hiss, high-pitched, metallic` |
| ui_drop | 4030〜4032 | 4.0 | `TrackType: SFX, a paper card set down flat on a wooden table, crisp transient, a clear little tap at the start as the card lands, then a short soft papery pat, cardstock on hardwood, warm mid tone, articulate attack, no hiss, close-miked, dry, no reverb.` | `muffled, dull, boomy, distant, reverb, harsh, shrill, hiss, high-pitched, metallic` |
| ui_error | 4040〜4042 | 4.0 | `TrackType: SFX, a knuckle knocking twice on a solid wooden tabletop, two gentle knocks in quick succession, each with a crisp transient and a clear click at the start, friendly not alarming, solid oak, warm mid-low woody knock, articulate attack, no buzzer, no beep, no hiss, close-miked, dry, no reverb.` | `muffled, dull, boomy, distant, reverb, harsh, shrill, hiss, high-pitched, metallic, buzzer, beep` |
| ui_open | 4100〜4102 | 4.0 | `TrackType: SFX, a small cloth-bound hardcover book being opened, the cover lifts with a soft creak of the spine, then a gentle short flutter of thick pages settling, thick old paper and cloth, warm, soft, rolled-off highs, no hiss, close-up, dry, small room.` | `hiss, sizzle, crackle, harsh, bright, airy noise, shrill, white noise, crinkle` |
| ui_select | 4000〜4002 | 4.0 | `TrackType: SFX, the edge of a stiff paper card tapped onto a hard maple desk, crisp transient, a clear bright click at the very start, then a short woody tock that stops quickly, hard maple and cardstock, articulate, present, mid-pitched woody tone, close-miked, dry, no reverb.` | `muffled, dull, low-pass filtered, boomy, distant, thud, reverb` |
