# 音の候補（Stable Audio 3、2026-11-20）

本人が聴き比べて選ぶための候補。**ゲームの音（`assets/audio/sfx/`）は置き換えていない。** 気に入ったものを ID（B1、E07 など）で指定してもらえれば、それを取り込む作業を別にする。

> 追記（2026-11-20）: 本人の「採用できると判断したものは採用してよい」を受けて、測り直したうえで効果音 6 種を取り込んだ
> （E01・E32・E38・E42・E45・E51）。経緯と数値は `docs/sound-design.md` の「2026-11-20（3回目）」。BGM は取り込んでいない。

- 生成: このMacの Audio Studio MCP（Stable Audio 3 medium、Stability AI。ローカルで生成し、外部のサービスには送っていない）。歌・歌詞は無し
- 置き場所: `art/audio/stable-audio/`（`art/` は `.gdignore` で Godot から除外されている）。生成時の設定（prompt・seed・steps など）は、各ファイルの横の `.json` と `sfx/measurements.json` にある
- 再現: 同じ prompt・seed・duration・steps=8・cfg=1.0 で同じ音が出る。効果音の加工と測定は `tools/sfx/stable_audio_candidates.py`
- ライセンス: モデルの重みは Stability AI Community License（年間収入 100 万ドル未満は商用利用可）。**コンテストの応募規約・AI 利用ガイドライン（https://gc2026.jp.square-enix.com/guideline/）で生成した音声が使えるかは未確認。採用する前に本人が確認する**
- 限界: AI（Claude）は音を聴けない。下の数値は「明らかにおかしい」を防ぐ目安で、良し悪しは本人の耳で決める

## 聴いてほしい順番

1. BGM（B1〜B6）
2. 当たりの強い効果音: block_land（E39・E40）、bell（E43・E44）、goal（E53・E54）
3. UI の効果音（E01〜E18）
4. 残り

## BGM（OGG、44.1kHz ステレオ、継ぎ目なくループ）

曲どうしでジャンルと主な楽器を変えた: ハブ＝アコースティックのフォーク（ナイロン弦ギター・木のマリンバ・手で鳴らす打楽器）、考えているとき＝ドラム無しのアンビエント（フェルトピアノ・チェロとヴィオラの持続音）、タイトル＝軽い室内楽（ピチカート・クラリネットとファゴット・チェレスタ・ティンパニ）。

加工（`process_audio`）: 生成した曲は最後の数秒で消えていくので、その前で切った。出だしも音量が本体に近いところから使う（1/4 秒ごとの音量が中央値から −6dB 以内の範囲）。最後を頭へクロスフェードしてループにした。音量はハブとタイトルが −16 LUFS、考えているときは邪魔をしないように −18 LUFS。

| ID | ファイル | 場面 | seed | BPM | 生成 | 使った範囲 | クロスフェード | ループの長さ | 音量 |
|---|---|---|---|---|---|---|---|---|---|
| **B1** | `music/hub_1.ogg` | ハブ・探索 | 20261120 | 96 | 112.0 秒 | 0.5–108.5 秒 | 1500 ms | **106.5 秒** | -15.98 LUFS |
| **B2** | `music/hub_2.ogg` | ハブ・探索 | 20261121 | 96 | 112.0 秒 | 0.25–107.25 秒 | 1500 ms | **105.5 秒** | -15.98 LUFS |
| **B3** | `music/think_1.ogg` | 考えているとき | 20261130 | 68 | 94.0 秒 | 0.0–86.5 秒 | 2500 ms | **84.0 秒** | -18.0 LUFS |
| **B4** | `music/think_2.ogg` | 考えているとき | 20261131 | 68 | 94.0 秒 | 0.0–87.5 秒 | 2500 ms | **85.0 秒** | -18.04 LUFS |
| **B5** | `music/title_1.ogg` | タイトル | 20261140 | 108 | 42.0 秒 | 0.5–38.5 秒 | 1000 ms | **37.0 秒** | -16.17 LUFS |
| **B6** | `music/title_2.ogg` | タイトル | 20261141 | 108 | 42.0 秒 | 0.0–39.0 秒 | 1000 ms | **38.0 秒** | -15.79 LUFS |

プロンプト（同じ場面の2つは seed だけが違う）:

- ハブ・探索: `TrackType: Music, VocalType: Instrumental, Warm, gentle acoustic folk track with fingerpicked nylon guitar and soft wooden marimba melody, light hand percussion of shakers, wooden blocks and frame drum, mellow upright bass, relaxed and cozy for wandering a small sunny island. BPM: 96.`
- 考えているとき: `TrackType: Music, VocalType: Instrumental, Calm minimal ambient piece with soft felt piano playing sparse gentle chords, warm sustained cello and viola drones, faint brushed texture and no drums, quiet, unobtrusive and thoughtful for concentrating on a puzzle. BPM: 68.`
- タイトル: `TrackType: Music, VocalType: Instrumental, Whimsical light chamber orchestra opening with bouncy pizzicato strings, playful clarinet and bassoon melody, soft celesta sparkles and gentle timpani swells, hopeful and full of anticipation, warm and charming. BPM: 108.`

## 効果音（WAV、16bit モノラル 44.1kHz）

`sfx/<イベント名>_<n>.wav`。footstep は1つの足音で、ゲームの footstep_1〜3 の代わりになるかを聴く用。

加工（`tools/sfx/stable_audio_candidates.py`）:
1. モノラルにする
2. いまの効果音の仕上げ（`build_sfx.finish`）と同じフィルター: 150Hz 未満を切る（block_jump・block_land・bell は 45Hz 未満だけ）、9kHz より上を弱める（2次のローパス）
3. 頭の無音を切る（ピークから −40dB を最初に超える 3ms 前から。当たりは削らない）
4. 長さの上限（ホバー 80ms、UI 450ms、そのほか 800ms、save 1300ms、goal・bell 2300ms）で切り、最後を 15ms で消す。**生成した音はもっと長いので、余韻を途中で切ったものが多い**
5. ピークをそろえる: ホバー −12dBFS、UI −9dBFS、そのほか −4dBFS（UI はゲームの音より小さく）

測定は `tools/sfx/analyze.py` の `measure()`、基準は `tools/sfx/test_sfx.py` と同じ。**外れても消していない。** 54 個のうち、基準を全部満たしたのは 8 個。

印の意味: muffled＝頭 20ms が暗い（こもる）／>4k・>9k＝シャー・シャリ／centroid＝全体が甲高い／2-5k＝耳障りな帯域が多い／main≥1100Hz＝主な音程が C6 以上

| ID | ファイル | seed | 長さ | 主な周波数 | 頭20msの明るさ | 重心 | >4k | >9k | 250Hz以上(A) | 印 |
|---|---|---|---|---|---|---|---|---|---|---|
| **E01** | `sfx/ui_hover_1.wav` | 3000 | 80ms | 112Hz | 92% | 1078Hz | 8% | 0.1% | 96% | ok |
| **E02** | `sfx/ui_hover_2.wav` | 3001 | 80ms | 175Hz | 98% | 2632Hz | 32% | 0.0% | 99% | ⚠ centroid >4k 2-5k |
| **E03** | `sfx/ui_select_1.wav` | 3010 | 450ms | 264Hz | 0% | 295Hz | 0% | 0.0% | 88% | ⚠ muffled |
| **E04** | `sfx/ui_select_2.wav` | 3011 | 450ms | 287Hz | 0% | 373Hz | 0% | 0.0% | 93% | ⚠ muffled |
| **E05** | `sfx/ui_confirm_1.wav` | 3020 | 450ms | 320Hz | 0% | 439Hz | 0% | 0.0% | 96% | ⚠ muffled |
| **E06** | `sfx/ui_confirm_2.wav` | 3021 | 450ms | 320Hz | 0% | 320Hz | 0% | 0.0% | 91% | ⚠ muffled |
| **E07** | `sfx/ui_cancel_1.wav` | 3030 | 450ms | 842Hz | 96% | 4199Hz | 44% | 8.6% | 100% | ⚠ centroid >4k >9k |
| **E08** | `sfx/ui_cancel_2.wav` | 3031 | 450ms | 538Hz | 90% | 4610Hz | 47% | 8.2% | 100% | ⚠ centroid >4k >9k |
| **E09** | `sfx/ui_open_1.wav` | 3040 | 450ms | 4889Hz | 96% | 4140Hz | 47% | 2.5% | 100% | ⚠ centroid >4k >9k 2-5k |
| **E10** | `sfx/ui_open_2.wav` | 3041 | 450ms | 3716Hz | 94% | 3514Hz | 30% | 1.1% | 100% | ⚠ centroid >4k 2-5k |
| **E11** | `sfx/ui_close_1.wav` | 3050 | 450ms | 209Hz | 7% | 517Hz | 1% | 0.0% | 90% | ⚠ muffled |
| **E12** | `sfx/ui_close_2.wav` | 3051 | 450ms | 136Hz | 15% | 983Hz | 6% | 0.1% | 95% | ⚠ muffled |
| **E13** | `sfx/ui_pick_1.wav` | 3060 | 450ms | 680Hz | 79% | 2484Hz | 17% | 3.5% | 100% | ⚠ >9k |
| **E14** | `sfx/ui_pick_2.wav` | 3061 | 450ms | 764Hz | 97% | 2315Hz | 16% | 4.8% | 100% | ⚠ >9k |
| **E15** | `sfx/ui_drop_1.wav` | 3070 | 450ms | 407Hz | 12% | 721Hz | 1% | 0.1% | 98% | ⚠ muffled |
| **E16** | `sfx/ui_drop_2.wav` | 3071 | 450ms | 536Hz | 18% | 1178Hz | 1% | 0.0% | 100% | ⚠ muffled |
| **E17** | `sfx/ui_error_1.wav` | 3080 | 450ms | 367Hz | 0% | 393Hz | 0% | 0.0% | 93% | ⚠ muffled |
| **E18** | `sfx/ui_error_2.wav` | 3081 | 450ms | 369Hz | 0% | 386Hz | 0% | 0.0% | 95% | ⚠ muffled |
| **E19** | `sfx/radial_open_1.wav` | 3090 | 800ms | 2858Hz | 97% | 5126Hz | 61% | 7.5% | 100% | ⚠ centroid >4k >9k |
| **E20** | `sfx/radial_open_2.wav` | 3091 | 800ms | 1699Hz | 98% | 3102Hz | 31% | 2.0% | 100% | ⚠ centroid >4k >9k |
| **E21** | `sfx/lend_1.wav` | 3100 | 800ms | 86Hz | 96% | 2273Hz | 27% | 3.3% | 98% | ⚠ >4k >9k |
| **E22** | `sfx/lend_2.wav` | 3101 | 800ms | 102Hz | 98% | 1799Hz | 19% | 1.5% | 96% | ⚠ >9k |
| **E23** | `sfx/lend_range_1.wav` | 3110 | 800ms | 8051Hz | 99% | 7271Hz | 90% | 18.0% | 100% | ⚠ main≥1100Hz centroid >4k >9k |
| **E24** | `sfx/lend_range_2.wav` | 3111 | 800ms | 136Hz | 98% | 4600Hz | 48% | 24.7% | 98% | ⚠ centroid >4k >9k |
| **E25** | `sfx/recall_1.wav` | 3120 | 800ms | 172Hz | 14% | 2535Hz | 25% | 1.5% | 97% | ⚠ >4k muffled |
| **E26** | `sfx/recall_2.wav` | 3121 | 800ms | 149Hz | 98% | 5208Hz | 74% | 1.2% | 100% | ⚠ centroid >4k |
| **E27** | `sfx/prohibit_1.wav` | 3130 | 800ms | 180Hz | 11% | 413Hz | 0% | 0.0% | 91% | ⚠ muffled |
| **E28** | `sfx/prohibit_2.wav` | 3131 | 800ms | 236Hz | 5% | 369Hz | 0% | 0.0% | 87% | ⚠ muffled |
| **E29** | `sfx/receive_wood_1.wav` | 3140 | 800ms | 289Hz | 3% | 429Hz | 0% | 0.0% | 99% | ⚠ muffled |
| **E30** | `sfx/receive_wood_2.wav` | 3141 | 800ms | 388Hz | 6% | 500Hz | 0% | 0.0% | 100% | ⚠ muffled |
| **E31** | `sfx/receive_stone_1.wav` | 3150 | 800ms | 652Hz | 57% | 1707Hz | 6% | 0.0% | 100% | ok |
| **E32** | `sfx/receive_stone_2.wav` | 3151 | 800ms | 700Hz | 39% | 1302Hz | 3% | 0.0% | 100% | ok |
| **E33** | `sfx/receive_grass_1.wav` | 3160 | 800ms | 142Hz | 41% | 1301Hz | 11% | 2.3% | 97% | ⚠ >9k |
| **E34** | `sfx/receive_grass_2.wav` | 3161 | 800ms | 498Hz | 39% | 1579Hz | 13% | 2.3% | 99% | ⚠ >9k |
| **E35** | `sfx/receive_creature_1.wav` | 3170 | 800ms | 188Hz | 4% | 265Hz | 0% | 0.0% | 72% | ⚠ muffled |
| **E36** | `sfx/receive_creature_2.wav` | 3171 | 800ms | 264Hz | 1% | 283Hz | 0% | 0.0% | 81% | ⚠ muffled |
| **E37** | `sfx/block_jump_1.wav` | 3180 | 800ms | 81Hz | 8% | 434Hz | 1% | 0.1% | 97% | ⚠ muffled |
| **E38** | `sfx/block_jump_2.wav` | 3181 | 800ms | 80Hz | 20% | 463Hz | 1% | 0.0% | 97% | ok |
| **E39** | `sfx/block_land_1.wav` | 3190 | 800ms | 319Hz | 3% | 339Hz | 0% | 0.0% | 93% | ⚠ muffled |
| **E40** | `sfx/block_land_2.wav` | 3191 | 800ms | 251Hz | 2% | 335Hz | 0% | 0.0% | 90% | ⚠ muffled |
| **E41** | `sfx/block_step_1.wav` | 3200 | 800ms | 765Hz | 29% | 2308Hz | 17% | 1.5% | 100% | ok |
| **E42** | `sfx/block_step_2.wav` | 3201 | 800ms | 734Hz | 47% | 1253Hz | 5% | 0.3% | 100% | ok |
| **E43** | `sfx/bell_1.wav` | 3210 | 2300ms | 1767Hz | 70% | 1787Hz | 2% | 0.0% | 100% | ⚠ main≥1100Hz |
| **E44** | `sfx/bell_2.wav` | 3211 | 2300ms | 2183Hz | 53% | 4836Hz | 67% | 10.2% | 100% | ⚠ main≥1100Hz centroid >4k >9k |
| **E45** | `sfx/player_jump_1.wav` | 3220 | 800ms | 318Hz | 45% | 1728Hz | 16% | 1.0% | 99% | ok |
| **E46** | `sfx/player_jump_2.wav` | 3221 | 800ms | 134Hz | 7% | 492Hz | 3% | 0.2% | 83% | ⚠ muffled |
| **E47** | `sfx/player_land_1.wav` | 3230 | 800ms | 3294Hz | 90% | 4909Hz | 56% | 7.9% | 100% | ⚠ centroid >4k >9k |
| **E48** | `sfx/player_land_2.wav` | 3231 | 800ms | 3014Hz | 79% | 4457Hz | 44% | 10.0% | 100% | ⚠ centroid >4k >9k |
| **E49** | `sfx/footstep_1.wav` | 3240 | 800ms | 3759Hz | 96% | 5594Hz | 66% | 18.2% | 100% | ⚠ centroid >4k >9k |
| **E50** | `sfx/footstep_2.wav` | 3241 | 800ms | 4995Hz | 81% | 5197Hz | 56% | 20.6% | 100% | ⚠ centroid >4k >9k |
| **E51** | `sfx/save_1.wav` | 3250 | 1300ms | 142Hz | 99% | 1072Hz | 8% | 0.8% | 95% | ok |
| **E52** | `sfx/save_2.wav` | 3251 | 1300ms | 258Hz | 0% | 1808Hz | 18% | 2.0% | 94% | ⚠ >9k muffled |
| **E53** | `sfx/goal_1.wav` | 3260 | 2300ms | 1630Hz | 100% | 1798Hz | 1% | 0.0% | 100% | ⚠ main≥1100Hz |
| **E54** | `sfx/goal_2.wav` | 3261 | 2300ms | 1643Hz | 100% | 1866Hz | 2% | 0.1% | 100% | ⚠ main≥1100Hz |

### 測って分かったこと（AI の見立て。聴いて確かめてほしい）

- **二つに分かれた。** 木を叩く・判を押す・木箱・机を指でたたく音（ui_select、ui_confirm、ui_error、receive_wood、block_land、prohibit など）は、頭 20ms の 1.5kHz 以上がほぼ 0〜10%。プロンプトに「crisp attack」「clear transient」と書いても、こもった音が出た。逆に紙・草・足音（ui_cancel、ui_open、radial_open、footstep、player_land）は 4kHz 以上が多く、シャーっと鳴る
- bell と goal は主な周波数が 1.6〜2.2kHz（C6 以上）。鐘の倍音が強く出ている。基準は C4 くらいの鐘を想定している
- 基準を全部満たしたもの: ui_hover_1、receive_stone_1・2、block_jump_2、block_step_1・2、player_jump_1、save_1
- 直し方の案（本人が「方向はよい」と言ったら）: こもった音は cfg を上げて negative_prompt に「muffled, dull」を入れて作り直す、または叩いた瞬間だけ明るくする EQ。シャーっと鳴る音は 4kHz より上をもっと弱める

### プロンプト（同じイベントの _1 と _2 は seed だけが違う）

| イベント | プロンプト（サーバーが付けた先頭の `TrackType: SFX,` を含む） |
|---|---|
| ui_hover | `TrackType: SFX, fingertip brushing the corner of a thick paper card, a single tiny soft tick, instant attack, almost no tail, thick cardstock, crisp but quiet, low pitched, close-up, dry, quiet room.` |
| ui_select | `TrackType: SFX, a paper card tapped edge-down onto a wooden desk, one light tap with a crisp attack and a short woody decay, cardstock on a solid oak desk, warm low knock, clear transient, close-up, dry, small room.` |
| ui_confirm | `TrackType: SFX, a wooden rubber stamp pressed firmly onto paper on a desk, one firm satisfying thump, crisp attack, quick decay, wooden stamp handle, rubber and paper on hardwood, warm solid low knock, close-up, dry, small room.` |
| ui_cancel | `TrackType: SFX, a paper card slid back across a wooden desk by a fingertip, one short quick slide that stops softly, smooth cardstock friction on varnished wood, soft but clear, close-up, dry, small room.` |
| ui_open | `TrackType: SFX, a small cloth-bound hardcover book being opened, cover lifts with a soft spine creak, then a quick flutter of pages settling open, old paper pages and cloth cover, warm, crisp page texture, close-up, dry, small room.` |
| ui_close | `TrackType: SFX, a small cloth-bound hardcover book being closed, cover claps shut with a short puff of air, immediate attack, short decay, cloth-bound board cover and paper block, warm low clap, close-up, dry, small room.` |
| ui_pick | `TrackType: SFX, a paper card picked up off a wooden table, one short quick swipe as the card leaves the surface, thin cardstock, soft airy friction, crisp start, close-up, dry, small room.` |
| ui_drop | `TrackType: SFX, a paper card set down flat on a wooden table, one light flat pat, very short, with a tiny woody tap underneath, cardstock on hardwood, soft papery with clear attack, close-up, dry, small room.` |
| ui_error | `TrackType: SFX, a fingertip knocking on a wooden tabletop twice, two soft dull knocks in quick succession, gentle, not alarming, solid wood tabletop, low and rounded knock with a clear edge, no buzzer, no beep, close-up, dry, small room.` |
| radial_open | `TrackType: SFX, three paper cards fanned out quickly by hand, a rapid sequence of three crisp flicks spreading outward, short, stiff cardstock, papery snap, clear but soft, close-up, dry, small room.` |
| lend | `TrackType: SFX, a paper card flicked from the fingers, then a glass rod rubbed with a wet fingertip, a quick papery flick followed by a short clear singing tone that swells gently and fades, paper and glass, warm low singing tone with a soft beating shimmer, close-up, small wooden room, light short reverb.` |
| lend_range | `TrackType: SFX, several glass rods rubbed with wet fingertips one after another, a soft staggered cluster of low singing tones spreading outward, swelling and fading together, glass, warm low tones slightly detuned against each other, gentle shimmer, small wooden room, light short reverb.` |
| recall | `TrackType: SFX, a low glass singing tone drawn back into a hand, ending with a paper card snapped between fingers, tone swells in like reversed audio, then a crisp short paper snap at the end, glass and stiff cardstock, warm low tone, clear snap, close-up, small wooden room, light short reverb.` |
| prohibit | `TrackType: SFX, a heavy wooden seal stamp pressed down onto paper, one heavy firm thud followed by a short low slightly detuned hum that settles, friendly not scary, dense hardwood and paper, low warm thud with clear attack, close-up, small wooden room, dry.` |
| receive_wood | `TrackType: SFX, a hollow wooden crate knocked once with a knuckle, single resonant knock, crisp attack, short hollow ring, dry pine boards, hollow box body, warm woody tone, close-up, outdoors, dry.` |
| receive_stone | `TrackType: SFX, a small smooth stone tapped by another stone, one short clack that stops almost immediately, dense river stone, hard, dry, mid-low click with a solid body, close-up, outdoors, dry.` |
| receive_grass | `TrackType: SFX, a hand patting a patch of grassy soil, one soft dull thump with a brief rustle of grass blades, packed earth and dry grass, soft low body with a crisp leafy edge, close-up, outdoors, dry.` |
| receive_creature | `TrackType: SFX, a small soft round plush-like creature bouncing once, a soft squishy bop, then a tiny rising puff of breath, cute and short, soft fur and a squishy body, warm, rounded, mid-low, close-up, outdoors, dry.` |
| block_jump | `TrackType: SFX, a wooden crate springing up off a flexible wooden plank, the plank creaks and flexes, then a springy thump as the crate launches upward, pine plank and hollow crate, woody creak, low punchy thump with clear attack, close-up, outdoors, dry.` |
| block_land | `TrackType: SFX, a hollow wooden crate dropped onto grassy ground, one heavy satisfying thunk with a brief woody rattle, quick decay, pine boards and packed earth, deep hollow body with a clear knock on impact, close-up, outdoors, dry.` |
| block_step | `TrackType: SFX, a wooden crate pushed one step across the ground, a short scraping slide that stops with a small bump, wood on packed dirt and small pebbles, gritty friction, woody body, close-up, outdoors, dry.` |
| bell | `TrackType: SFX, a small bronze village bell hanging in a wooden frame, struck once by its clapper, clear strike then a long warm ringing decay with gentle beating, cast bronze, low warm tone, rich but not shrill, outdoors, short distance, open air.` |
| player_jump | `TrackType: SFX, a cloth tunic flapping as a small person hops up, one quick short whoosh of fabric, soft cotton cloth, airy, clear rustle, close-up, outdoors, dry.` |
| player_land | `TrackType: SFX, a small person landing on short grass after a hop, one soft thud of both feet with a brief crunch of grass, soft shoes, packed earth and grass blades, low soft body with crisp leafy edge, close-up, outdoors, dry.` |
| footstep | `TrackType: SFX, a single footstep of a soft shoe on short grass, one light step, quick soft crunch, very short, grass blades over soil, gentle and natural, close-up, outdoors, dry.` |
| save | `TrackType: SFX, paper pages clipped together with a small wooden clip, then glass rods rubbed with a wet fingertip, a soft woody clip, followed by four short low singing tones rising one after another, gentle and reassuring, wood, paper and glass, warm low clear tones, small wooden room, light short reverb.` |
| goal | `TrackType: SFX, glass rods rubbed with wet fingertips, then a small bronze bell in the distance, a quick rising sequence of warm singing tones, then one distant bell strike ringing out and fading, joyful but calm, glass and cast bronze, warm low tones, not shrill, outdoors, open air, gentle natural reverb.` |
