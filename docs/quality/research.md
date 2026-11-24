# 見た目と手応えの調査と、作ったもの（2026-11-24）

- 状態: 調査は完了。上位の改善は実装済み（ブランチ `claude/design-polish`）。Windows 実機の GPU での確認はまだ。
- 本人の依頼（原文）:「デザイン性の向上とか色々クオリティを高めるためにできることを実際のタイトルとかをみながら調査し、その上で作って欲しい」
- 書いた人: AI（Claude Code）。下の「作品から取り出した考え方」は、出典の記事・インタビュー・公式ページの内容を AI が要約したもの。作品そのものを遊んで確かめたわけではない。
- 守ったこと: 特定の作品のキャラクター・絵・名前・UI の配置・物語の仕掛けは写さない。取り出すのは一般的な考え方だけ（本人は過去に、特定の作品の仕掛けを借りる案を外している）。和紙・日本の文化の題材は使わない。文字の多い UI・ごちゃごちゃは避け、「説明より見せる」を優先する。

## 1. 調べた作品と、取り出した考え方

近い手触りの作品（箱庭・ブロックや立方体の 3D パズルと探検・ゆるい協力）と、手応え・読みやすさの定番の講演を選んだ。

| 作品・資料 | うまくやっていること（一般化した考え方） | 出典 |
|---|---|---|
| Captain Toad: Treasure Tracker（任天堂） | ステージを「箱の中の庭」（ジオラマ）として1つの小さな塊にまとめ、目標は1つ。カメラを回して見ることそのものが遊びの一部。主人公は跳べない制約から作られた | [Nintendo Life のインタビュー](https://www.nintendolife.com/news/2014/12/interview_captain_toad_treasure_trackers_developers_talk_over_origins_and_the_contents_of_toads_backpack)、[Wikipedia](https://en.wikipedia.org/wiki/Captain_Toad:_Treasure_Tracker) |
| LEGO Builder's Journey（Light Brick Studio） | ジオラマの各場面を「人工の昼光＋撮影スタジオ風の補助光」で照らし、露出を固定して色を管理しやすくした。被写界深度とブルームで「机の上の模型」に見せる。最初は本物のブロックで場面を試作した | [Light Brick の作品ページ](https://www.lightbrick.com/builders-journey)、[開発者でない人の HDRP 解説ブログ](https://amanthul.github.io/unity/unity%20hdrp/ray%20tracing/dlss/2021/10/18/unity-hdrp-lego.html)、[MCV/Develop](https://mcvuk.com/business-news/were-doing-something-different-something-new-with-a-very-well-known-medium-light-brick-studios-on-the-development-of-lego-builders-journey/) |
| Tiny Glade（Pounce Light） | 置くたびに形が自動で整い、触ること自体が気持ちいい（小さな反応の積み重ね）。光の跳ね返り（GI）で暖かく見せつつ、低い性能の PC でも 60fps を目標にした | [80.lv のインタビュー](https://80.lv/articles/exclusive-tiny-glade-developers-discuss-bevy-proceduralism-publishers-cozy-games)、[TechRadar](https://www.techradar.com/gaming/pc-gaming/cozy-castle-builder-tiny-glade-just-got-a-new-ultra-satisfying-trailer-releasing-in-2024) |
| Townscaper（Oskar Stålberg） | 四角いマスから有機的な町を作る（四角いのに四角く見せない）。性能の低い機械でもきれいに見える画風を作るのが一番の難題だった | [Game Developer: How Townscaper works](https://www.gamedeveloper.com/game-platforms/how-townscaper-works-a-story-four-games-in-the-making)、[PC Gamer](https://pcgamer.com/townscapers-developer-on-how-its-radically-casual-design-is-inspiring-a-new-wave-of-low-stress-builders-to-adapt-the-blueprint) |
| Monument Valley（ustwo games） | 平らな塗りだけだと「死んで」見えたので、焼き込んだ陰（AO）で塊感を出し、画面全体に薄いグラデーションと周辺減光を重ねて印刷物のように仕上げた。同じ色の形は読み違えられたので、わずかな色の差で「どこを歩けるか」を分けた。「どの1コマも飾れる絵に」 | [Game Developer: Making the impossible possible](https://www.gamedeveloper.com/design/making-the-impossible-possible-in-i-monument-valley-i-)、[Wallpaper](https://www.wallpaper.com/tech/monument-valley-at-10-the-story-of-the-most-meticulous-puzzle-game-ever-created) |
| A Short Hike（Adam Robinson-Yu） | 小さな箱庭で、物にやわらかい輪郭線を付けて少ない画素でも読みやすくした。色は実際の秋の景色の写真から取った。音楽は場所と行動（飛ぶ・船の速さ）で楽器が重なる | [PlayStation Blog](https://blog.playstation.com/2021/08/05/crafting-a-tiny-open-world-a-look-behind-the-scenes-at-the-creation-of-a-short-hike/)、[Wikipedia](https://en.wikipedia.org/wiki/A_Short_Hike) |
| Astro Bot（Team Asobi） | 遊びの芯（跳ぶこと）にすべてを混ぜ込み、ミニゲームの寄せ集めにしない。振動は「強さ」ではなく「表面ごとの違いが分かること」で作る | [PlayStation Blog](https://blog.playstation.com/2024/09/09/astro-bot-how-team-asobi-created-a-unified-vision-for-fun/)、[TechRadar のインタビュー](https://www.techradar.com/gaming/astro-bot-nicolas-doucet-interview)（振動の話は GDC 2025 の講演の二次情報で、講演そのものは見ていない） |
| Overcooked（Ghost Town Games） | ボタンを少なくし、指示を短く（切る・調理する・出す）。1つの画面を全員で見る協力では、誰が何をしているかが画面から読めることが大事。協力が「競争」にならない作り | [Nintendo UK のインタビュー](https://www.nintendo.co.uk/News/2017/April/Interview-Cooking-up-chaos-in-Overcooked-Special-Edition-on-Nintendo-Switch-1215687.html)、[Co-Optimus](https://co-optimus.com/interview/1838/page/1/indie-ana-co-op-and-the-overcooked-interview.html) |
| Dragon Quest Builders 2（スクウェア・エニックス） | 立方体のブロックの世界に、丸くて頭の大きい人物を置く組み合わせ（ブロックと「ちびキャラ」の混ざった画風）。ブロックの見た目が初期の作品のドット絵を思わせたことが出発点 | [MCV（制作の話）](https://mcvuk.com/?p=60543)、[Gamereactor のレビュー](https://www.gamereactor.eu/dragon-quest-builders-2-review/) |
| Unpacking（Witch Beam） | 物を置く音を、本物の物から録り、置く面（やわらかい・かたい）で変える。似た音をまとめて数を減らしつつ、毎回少しずつ違うようにした | [Audiokinetic のブログ](https://www.audiokinetic.com/en/blog/unpacking-the-fun-behind-the-foley)、[GDC Vault](https://gdcvault.com/play/1027728/-Unpacking-The-Fun-Behind) |
| 講演「Juice it or lose it」（Jonasson・Purho、GDC Europe 2012） | 同じ単純なゲームに、弾む動き・つぶれと伸び・粒・揺れ・音を1つずつ足すと、遊び心地が大きく変わることを見せた | [GDC Vault](https://gdcvault.com/play/1016487/Juice-It-or-Lose) |
| 講演「The Art of Screenshake」（Jan Willem Nijman、Vlambeer） | 動き・音・大きな反応・残るもの（煙）・一瞬の遅さ（スローモーション）で手応えを作る。ただし強すぎると疲れる | [Game Developer の要約](https://gamedeveloper.com/design/vlambeer-co-founder-shares-advice-on-building-better-action-games) |
| Game Accessibility Guidelines／Xbox Accessibility Guidelines | 大事な情報を色だけで伝えない（形・文字と組み合わせる）。読みやすい既定の文字の大きさ＋大きくできること。文字のコントラストは 4.5:1（大きい文字は 3:1） | [Game Accessibility Guidelines](https://gameaccessibilityguidelines.com/?p=21)、[XAG 103](https://devdocs.xbox.com/gaming/accessibility/xbox-accessibility-guidelines/103)、[XAG 102](https://devdocs.xbox.com/gaming/accessibility/xbox-accessibility-guidelines/102) |
| ミニチュア風の写真（tilt-shift／diorama effect） | 浅い被写界深度をまねて上下をぼかすと、本物の景色が模型に見える。上から見下ろす角度で効く。ぼかしすぎると作り物に見える | [Wikipedia: Miniature faking](https://en.wikipedia.org/wiki/Miniature_faking) |
| Godot の公式ドキュメント | Godot 4 では環境の重さ・質の設定はプロジェクト設定にある。環境光は空からより色からの方がわずかに軽い。霧の空気遠近はわずかに重い | [Environment and post-processing（4.6）](https://docs.godotengine.org/en/4.6/tutorials/3d/environment_and_post_processing.html) |

### 1.1 上位の考え方（このゲームに効く順）

1. **空と空気で「浮かぶ島の箱庭」を言い切る**（Monument Valley・LEGO Builder's Journey）。背景のグラデーションと遠くが空の色へ溶ける空気遠近は、どの画面にも効き、重さはほぼ無い。
2. **四角いのに四角く見せない、陰で塊を出す**（Townscaper・Monument Valley）。入り組んだ角や壁の足もとを少し暗くし、丸めた縁を少し明るくする。作るときに1回だけ計算する（焼き込み）ので、毎フレームの重さは無い。
3. **すべての操作に小さな反応を返す**（Juice it or lose it・Tiny Glade）。つぶれて戻る・粒・音を、遊びの芯の操作（渡す・取り戻す・着地・跳ぶ）にだけ付ける。強さは控えめにして、ゆるい雰囲気を壊さない（The Art of Screenshake の「やりすぎ」の注意。画面の揺れは使わない）。
4. **区切りの瞬間を大きく祝う、でも文字は増やさない**（Astro Bot の統一感・Overcooked の短い指示）。クリアは紙吹雪とカードの弾みで見せる。
5. **読みやすさは色と形の両方で、効果はルールの色を使わない**（アクセシビリティ・Monument Valley の色の差）。禁止の赤・貸出のはちみつ・選択の夕日は効果に使わない。
6. **重い効果は選べるようにする**（Tiny Glade・Townscaper の「低い性能でもきれいに」）。審査は普通の Windows PC。既定は軽く、重いものは画質の高だけ。
7. **ミニチュアのぼかしは控えめに、選べるように**（Miniature faking の「ぼかしすぎは作り物」）。遠くの巣の光が読めなくなるので、既定では切る。

## 2. いまの rule-relay との差（2026-11-24 の main。撮影は lavapipe）

変更前の画面: `docs/images/quality/before-*.png`、はじめての 10 分の通し: `docs/reports/first-ten-minutes/`。

| 考え方 | いまの状態 | 差 |
|---|---|---|
| 空と空気 | ステージでは空が白に近い灰色（`before-w1.png`・`before-w4.png`・`before-w6.png`）。カメラが少し下を向くと、地平線の色と霧で背景がほぼ真っ白になる。島の下も白く、「浮かぶ島」に見えない | 大きい。どの画面にも出る |
| 陰で塊を出す | 地形は角を丸めた1つのメッシュ。色はセルごとの2色の市松だけで、壁の足もと・入り組んだ角に陰が無い。高台の石の壁が平たい板に見える（`before-lend.png`） | 中くらい |
| 小さな反応 | 渡すと音と知らせは出るが、受け取った物は動かない。ブロックや自分の着地にも見た目の反応が無い。投げたメダルの当たりにだけ小さな輪がある（ADR 0017） | 大きい。遊びの芯の操作 |
| 区切りの瞬間 | クリアは小さなカードが降りるだけ（`before-clear.png`）。最終ステージだけお祝いがある | 中くらい |
| 生きている感じ | 広場には草花と住む生き物と動く建物があるが、草花は止まっている。ステージには動くものがほとんど無い | 中くらい |
| ステージの出入り | 島がぱっと切りかわる（組み立ての一瞬も見える） | 小〜中 |
| 重い効果の選択 | SSAO とにじみが全員に常に入っている。画質の設定は無い | 性能の心配（審査の PC） |
| 読みやすさ | 状態は色と形の両方で示している（UI の設計どおり）。文字の大きさは 4 段階 | 小さい（守れている） |

## 3. 改善の候補と優先順位

効果・作る手間・危険（遊びの読みやすさ・協力の同期・ほかの作業との衝突）・重さ（毎フレームの描画）で並べた。重さは lavapipe（CPU で描く Vulkan）の相対の値で、実機の GPU の値ではない（4 章）。

| 順 | 改善 | 効果 | 手間 | 危険 | 重さ | 判断 |
|---|---|---|---|---|---|---|
| 1 | 空のグラデーション・空気遠近・高さの霧・暖かい環境光・色の整え | 大 | 小 | 小（霧で遠くの巣の光が薄くなりすぎないか → 濃さを控えた） | ほぼ 0 | 作った |
| 2 | 遠い雲（島のまわりの輪） | 大（浮かぶ島に見える） | 小 | 小 | 小（描く回数 1 回） | 作った |
| 3 | 地形の頂点の陰と縁の明るさ・草の色のむら | 中 | 小 | 小 | 0（作るときだけ） | 作った |
| 4 | 渡す・取り戻す・着地・跳ぶの手応え（つぶれて戻る・輪・粒） | 大 | 中 | 中（当たり判定を動かさないこと → 見た目のノードだけを動かす。協力 → 音の合図から作る） | 小 | 作った |
| 5 | クリアの紙吹雪とカードの弾み | 中 | 小 | 小 | 小（一瞬だけ） | 作った |
| 6 | ステージの出入りの「丸く開く」幕 | 中 | 小 | 小（入力を止めない） | ほぼ 0 | 作った |
| 7 | 草花・木の葉のそよぎ（頂点シェーダー） | 中 | 小 | 小 | 小 | 作った |
| 8 | 舞う花びらと光の粒 | 小〜中 | 小 | 中（多いと散らかる → 少なく淡く、ルールの色を使わない） | 小 | 作った（中 36・高 90） |
| 9 | 画質の設定（低・中・高）と、ミニチュア風のぼかし | 必須（性能） | 小 | 小 | — | 作った |
| 10 | 輪郭線・トゥーン調の陰 | 中 | 中〜大 | 大（いまのやわらかい陰と合わない。全モデルの見直しが要る） | 中 | 見送り |
| 11 | SDFGI・ボリュームの霧 | 中 | 小 | 中 | 大（内蔵 GPU で重い） | 見送り |
| 12 | 小さな生き物（蝶・鳥）を広場に飛ばす | 中 | 中（新しいモデル） | 小 | 小 | 後で（Blender で作る） |
| 13 | 水面のきらめき・滝 | 中 | 中 | 小 | 小〜中 | 後で（WaterVisual の担当と相談） |
| 14 | 数字や文字の動き（ホットバーの数・知らせの出入り） | 小 | 小 | 小 | 0 | 後で |
| 15 | 新しい効果音（渡したときのきらめきの層・クリアの紙吹雪） | 中 | — | — | — | 下の「作ってほしい音」に挙げた（本人が Mac で作る） |

## 4. 作ったもの（実装）と重さ

詳しい決定は `docs/adr/0022-visual-direction-and-quality.md`。画面の設計は `docs/ui-design.md`。

| 作ったもの | ファイル | 画質 |
|---|---|---|
| 空・光・霧・色の整え（全部の島で共通） | `src/game/world_look.gd`（`PrototypeIsland.build_environment` から呼ぶ） | 全部（にじみは中から、SSAO は高だけ） |
| 遠い雲 | `src/game/world_look.gd` | 全部（切れる） |
| 舞う花びらと光の粒 | `src/game/world_look.gd` | 中 36・高 90 |
| 地形の頂点の陰・縁の明るさ・色のむら | `src/game/terrain_mesher.gd` | 全部（重さ 0） |
| 草花・木の葉のそよぎ | `src/game/foliage.gd`、`assets/shaders/foliage_sway.gdshader` | 中・高 |
| 手応え（つぶれて戻る・輪・粒・土ぼこり・紙吹雪） | `src/game/world_juice.gd` | つぶれは全部、粒は中・高 |
| クリアのカードの弾み | `src/ui/hud.gd` | 全部 |
| ステージの出入りの幕 | `src/ui/stage_transition.gd`、`assets/shaders/iris.gdshader` | 全部 |
| 画質の設定（せってい） | `src/ui/game_settings.gd`、`src/ui/settings_menu.gd`、`src/game/visual_quality.gd` | — |
| 撮影と測定の道具 | `tools/capture_quality.gd` | — |

### 4.1 重さの測り方と結果

`tools/capture_quality.gd -- measure`（lavapipe＋xvfb、480×270、各設定 12 枚の平均）。lavapipe は CPU で描くので、**値は効果どうしの比べ方にだけ使う**（実機の GPU のミリ秒ではない）。同じ場面・同じ視点で、効果を全部切った状態から1つずつ足した。

| 設定 | 広場 | 4 森の奥 | 遠征 | 7-6 頂の祭り |
|---|---|---|---|---|
| すべて切る | 471 | 141 | 130 | 328 |
| glow だけ | 497（+6%） | 167（+18%） | 171（+32%） | 333（+2%） |
| ssao だけ | 502（+7%） | 205（+45%） | 176（+36%） | 334（+2%） |
| soft_shadow だけ | 474（+1%） | 170（+21%） | 116（-10%） | 372（+14%） |
| clouds だけ | 467（-1%） | 161（+14%） | 122（-5%） | 347（+6%） |
| sway だけ | 498（+6%） | 136（-4%） | 144（+11%） | 354（+8%） |
| dof だけ | 464（-1%） | 186（+31%） | 189（+46%） | 390（+19%） |
| motes 90 だけ | 459（-3%） | 170（+20%） | 124（-4%） | 396（+21%） |
| 画質 低 | 491（+4%） | 164（+16%） | 137（+6%） | 316（-4%） |
| 画質 中 | 476（+1%） | 221（+57%） | 160（+24%） | 376（+15%） |
| 画質 高 | 543（+15%） | 244（+72%） | 213（+65%） | 393（+20%） |
| 画質 高＋ぼかし | 536（+14%） | 273（+93%） | 217（+67%） | 409（+25%） |

読み方:

- 表の値は 1 フレームの時間（ms、lavapipe）と、「すべて切る」からの増え方。lavapipe は CPU で描くので、広場（物が多い）は頂点の処理が重く、効果の差が埋もれる。**同じ設定でも ±10% ほどぶれる**（広場で「低」が「すべて切る」より遅いのはぶれ）。
- 効果ごとの重さ（ステージ 3 つの増え方の幅）: ぼかし（DOF）+19〜46%、SSAO +2〜45%、にじみ（glow）+2〜32%。影のぼかし・草花のそよぎ・雲・花びら 90 個は、多くがぶれの範囲（−10〜+21%）。
- 画質ごと: 低 −4〜+16%（ほぼぶれの範囲）、中 +1〜57%、高 +15〜72%。lavapipe ではにじみが重く出る（画面全体をソフトウェアでぼかすため）。実機の GPU ではにじみは軽い処理で、SSAO と DOF が重い側になる。
- 変更前は SSAO とにじみが**常に入っていた**（効果で言えば「にじみ＋SSAO」）。はじめの画質（中）は SSAO を切ったので、変更前より軽いか同じくらいになるはず（Windows 実機で確かめる）。
- 地形の頂点の陰・縁の明るさは、地形を作るときだけの計算で、毎フレームの重さは無い。

### 4.2 画面（前・後。lavapipe、1280×720、画質 中）

| 場面 | 前 | 後 |
|---|---|---|
| 広場 | `docs/images/quality/before-hub.png` | `docs/images/quality/after-hub.png` |
| W1（1-1 跳ぶ力を貸す） | `before-w1.png` | `after-w1.png` |
| W4（森の奥） | `before-w4.png` | `after-w4.png`（低 `after-w4-low.png`・高 `after-w4-high.png`） |
| W6（霧の段丘） | `before-w6.png` | `after-w6.png` |
| 渡した瞬間（0.07 秒後） | `before-lend.png` | `after-lend.png` |
| クリアの瞬間 | `before-clear.png` | `after-clear.png` |

撮り直し: `tools/capture_quality.gd -- shot <場面> <出力> [低|中|高]`。

## 5. 作ってほしい音（本人が Mac で作る。いまは既存の音を使っている）

| 番号 | 場面 | 欲しい音 | いまの代わり |
|---|---|---|---|
| Q1 | 能力を渡した瞬間の上に重ねる層 | ごく短い（0.2 秒）きらめき。低めの鉄琴かグロッケンを1音、こもらせない | `lend@n`（能力ごとの音程）＋材質の声 |
| Q2 | クリアの紙吹雪 | 紙が舞う「ふわっ」とした柔らかい音＋短い和音の終わり（0.8 秒） | `goal` |
| Q3 | ステージに入る幕が開くとき | やわらかい「すっ」という空気の音（0.4 秒）。高すぎない | なし |
| Q4 | 着地の土ぼこり（ブロック） | いまの `block_land` に、ごく小さな砂の「さっ」を重ねた版 | `block_land` |

## 6. まだのこと

- Windows 実機（内蔵 GPU と、普通の外付け GPU）で、画質ごとのフレーム時間を測る。lavapipe の値は相対だけ。
- 輪郭線・トゥーン調は見送った（いまのやわらかい陰と合わず、全モデルの見直しが要る）。
- 広場の小さな生き物（蝶・鳥）、水面のきらめき、知らせや数字の動き。
- 本人の目で、空の色・雲の量・花びらの量・ぼかしの強さを確かめる（色の好みは本人が決める）。
