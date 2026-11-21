# art（3Dモデルの原本）

このフォルダは Godot から除外している（`.gdignore`）。ゲームが読むのは `assets/models/*.glb` だけ。

| パス | 内容 |
|---|---|
| `scripts/palette.py` | 共有の色（パレット）と丸い形の部品（回転体・カプセル・輪・角丸の箱）。色はここだけで決める |
| `scripts/build_assets.py` | 地形のセル・能力のブロック・木・草花などを生成する（共通の関数もここ） |
| `scripts/rig.py` | 動くものの骨格（Armature）とアニメーション（Action）を作って書き出す部品（`armature` / `bind` / `action` / `save_and_export_rigged`） |
| `scripts/build_cast.py` | プレイヤー（4色）・願いを持つ生き物・その子ども（kit）・広場の生き物 2 種（`critter_bunny`・`critter_lamb`）。どれも部品ごとに作り、骨格とアニメーション付き |
| `scripts/build_overworld.py` | 広場のワープの門（`portal_arch`、渦が回る）と、クリアで建つ建物 6 種（家・風車・噴水・畑・見晴らし台・屋台） |
| `scripts/build_markers.py` | ゴールの旗と四隅の灯り・チェックポイントの台・入口の門・器のメダル（能力／禁止）・装備（ジャンプブーツ・クライミンググローブ）・ダッシュの羽根 |
| `scripts/build_hub_props.py` | 広場の置物（街灯・柵・鉢植え・ベンチ） |
| `scripts/build_contraptions.py` | 発射台と鐘（テクスチャを焼き込む） |
| `scripts/build_nature.py` | 自然の仕掛けと新しい能力の拾える物: かざぐるま（`wind_fan`、骨格付き・羽根は `spin`）・風の木の葉・氷のセル・おもり（重い）・風船（浮く）・足ひれ（泳ぐ）（docs/adr/0015） |
| `scripts/build_switches.py` | スイッチの仕掛け（重さの板・スイッチの扉・レバー・ワープの石・時の鐘の砂時計）。どれも部品ごとに作り、骨格とアニメーション付き（`docs/adr/0014`） |
| `scripts/build_icons.py` | 能力・禁止の器のアイコンと、メダルの面に重ねる記号だけの白い絵（`glyph_*.png`）を `assets/icons/`（128px・透明背景）に書き出す |
| `scripts/render_previews.py` | 原本を1枚ずつ描画して確認用の PNG を作る（Cycles・CPU）。名前を並べるとそれだけ描く |
| `source/*.blend` | Blender の原本（スクリプトが書き出す。手で直したら、スクリプトにも反映する） |

## 作り直す

```bash
blender -b --factory-startup --python art/scripts/build_assets.py              # 全部
blender -b --factory-startup --python art/scripts/build_assets.py -- block     # 一部（名前は BUILDERS を参照）
blender -b --factory-startup --python art/scripts/build_cast.py                # プレイヤー・生き物
blender -b --factory-startup --python art/scripts/build_markers.py             # 目印・器・装備
blender -b --factory-startup --python art/scripts/build_hub_props.py           # 広場の置物
blender -b --factory-startup --python art/scripts/build_overworld.py           # ポータル・建物
blender -b --factory-startup --python art/scripts/build_nature.py             # 風・氷・水と重い・浮く・泳ぐ
blender -b --factory-startup --python art/scripts/build_switches.py            # スイッチの仕掛け
blender -b --factory-startup --python art/scripts/build_icons.py               # アイコン
blender -b --factory-startup --python art/scripts/render_previews.py -- /tmp/previews traveler goal_flag
```

ゲームの中での見え方は `tools/capture_models.gd`（lavapipe＋xvfb、`lineup` / `hub` / `nest`）と
`tools/capture_overworld.gd`（広場。`first` / `all` × `spawn` / `aerial` / `meadow` / `portal` / `puzzle`）で撮って確かめる。
書き出した後は `godot --headless --import` で取り込み、警告が出ないことを確かめる。

- 使った Blender: **4.5.16 LTS**（公式配布、SHA-256 を検証）。LTS のサポート期間が提出期限より長い版を選んだ。
- 書き出し: glTF バイナリ（`.glb`）、Y-up、モディファイアを適用。カメラ・ライトは含めない。
- 再現性: 乱数は固定シード。形と頂点は毎回同じになるが、三角形の並び順（インデックス）が実行ごとに変わることがあり、`.glb` のバイナリは完全には一致しない（2026-11-18 確認）。

## 約束ごと

- 1 Blender 単位 = 1 m = 1 ブロック。Z が上。
- 地形とブロックは 1x1x1 で、中心が原点。当たり判定はゲーム側の箱で、モデルは見た目だけ。
- キャラクターの正面は Blender の +Y（Godot の前方 -Z になる）。足元が原点。手足・頭は別オブジェクトで、原点を関節に置く（`Body` `Head` `ArmL` `ArmR` `LegL` `LegR`）。
- **動くものは骨格で動かす**（2026-11-21 本人の指示「生き物とかは部分ごとに作り Rig とかもいるやつは使いながらで」）。
  部品ごとのメッシュを 1 本の骨（`b_torso` など、関節から上向き）に重み 1.0 で結び、アクション（`idle` `walk` `happy`、
  プレイヤーは `jump` も）を NLA に積んで、glTF に「アクションごと」で書き出す（`rig.py`）。Godot では `Skeleton3D` と
  `AnimationPlayer` になり、`RigAnimator`（`src/game/rig_animator.gd`）が状態で切り替える。ループはゲーム側で付ける。
  部品の名前は残すので、`find_child("Body")` などはそのまま使える。当たり判定はゲーム側の箱・カプセルのまま。
- 回る部品（風車の羽根 `Sails` の `spin`、ポータルの渦 `Swirl` の `swirl`）はオブジェクトのアニメーションにする。
- ブロックの色は、マテリアル名 `Panel` をゲーム側で色違いの複製に置き換えて変える。名前を変えるときは `ModelLibrary.tint_material` の呼び出しも直す。
- プレイヤーの色違いは、マテリアル名 `Accent`（布）と `AccentDeep`（縁・裏地）を `ArtPalette.tint_player` が差し替える。4色の値は `palette.py` の `PLAYER_COLORS` と `src/game/art_palette.gd` で同じにする。
- ゴールの旗は、布の `Flag` という子オブジェクトをゲーム側（`GoalMarker`）が竿を軸に揺らす。
- 器のメダルは正面が ±Y。記号はモデルに刻まず、ゲームが `glyph_*.png` を面に重ねる（記号を増やしてもモデルは1つ）。
- 色を変える（世界観が決まって塗り直す）ときは `palette.py` を直して全スクリプトを実行し直す。形は変えない。

## 現在のモデル（2026-11-21）

| ファイル | 生成 | 用途・ゲームでの使い道 |
|---|---|---|
| `traveler` | build_cast | プレイヤー。フードと丸い上着、背中の小さな荷物、頭の房と縫い目。1つのモデルを4色で使う（`PlayerAvatar`・持ち物の画面） |
| `creature_wish` | build_cast | 願いを持つ生き物。丸いからだ・小さな羽・頭の開いた芽（`Creature`） |
| `creature_kit` | build_cast | 巣へ運ぶ子ども（`kit`）。小さく、芽がまだつぼみ（`CreatureSpec.look`） |
| `goal_flag` / `goal_corner` | build_markers | ゴール。夕日色の旗に「集まる」印（真ん中の丸を4つの丸が囲む）、範囲の四隅に灯りの杭（`GoalMarker`） |
| `checkpoint_pad` | build_markers | チェックポイント。丸い台に若葉の光る輪と四つ葉、奥に小さな灯り |
| `entrance_gate` | build_markers | 広場の入口と帰り道。空色の輪の台、木の丸い門、何も書いていない吊り札（文字はゲームが浮かべる） |
| `vessel_medal` / `ban_medal` | build_markers | 世界に落ちている器。能力＝はちみつ色、禁止＝灰の地に赤い輪と斜線（`WorldItem`） |
| `jump_boots` / `climbing_gloves` / `dash_feather` | build_markers | 拾える装備とダッシュ（`WorldItem`） |
| `hub_lamp` / `hub_fence` / `hub_planter` / `hub_bench` | build_hub_props | 広場の飾り（`OverworldScenery`。当たり判定なし） |
| `critter_bunny` / `critter_lamb` | build_cast | 広場に住む生き物（耳の長い生き物・もこもこの生き物）。骨格付き（`OverworldResident`） |
| `portal_arch` | build_overworld | 広場のワープの門。渦（`Swirl`）が回り、クリアの印（`ClearedMark`）を出し入れする（`OverworldPortal`） |
| `ow_house` / `ow_windmill` / `ow_fountain` / `ow_garden` / `ow_lookout` / `ow_stall` | build_overworld | クリアで広場に建つ建物（見た目だけ。風車は羽根が回る） |
| `ability_block` | build_assets | 能力を受け取るブロック。枠＋色を変えるパネル＋四隅の鋲 |
| `grass_cell` / `rock_cell` / `sandstone_cell` | build_assets | 地形の1セル（草・岩・砂岩） |
| `island_base` | build_assets | 浮かぶ島の底（ゲーム側で島の大きさに拡大） |
| `tree_round` / `tree_tall` / `grass_tuft` / `flower` / `pebbles` | build_assets | 置物 |
| `launcher` / `bell` | build_contraptions | 発射台と鐘（テクスチャを焼き込む） |
| `wind_fan` | build_nature | 風上に立つかざぐるま（石の台・木の柱・風見の尾・4 色の花びら）。骨 `b_root`・`b_rotor`、羽根は `spin`（`WindVisual`） |
| `wind_leaf` | build_nature | 風に流れる木の葉（`CPUParticles3D` の形） |
| `ice_cell` | build_nature | 氷の地形のセルを動くブロックにしたときの形（霜の板と光る筋） |
| `heavy_weight` / `float_balloon` / `swim_fins` | build_nature | 拾える「重い」（取っ手の付いた石のおもり）・「浮く」（空色の風船）・「泳ぐ」（足ひれ）（`WorldItem`） |
| `pressure_plate` | build_switches | 重さの板。石の縁と木の天板（花の印）。天板（`Top`）が骨で沈む `press`（`PressurePlate`） |
| `switch_door` | build_switches | スイッチの扉（幅 1・高さ 2）。木の板・石の帯・空色の印。扉板（`Gate`）が床へ沈む `open`（`SwitchDoor`） |
| `switch_lever` | build_switches | レバー。苔の付いた石の台と木の柄。柄（`Handle`）が倒れる `flip`（`SwitchLever`） |
| `warp_stone` | build_switches | ワープの石。平たい石の空色の輪と、浮かぶ結晶（`Crystal`）がゆれる `hover`・光って跳ねる `warp`（`WarpStone`） |
| `bell_timer` | build_switches | 時の鐘の脇の砂時計。ガラス（`Glass`）が返る `flip`（`TimedBell`） |
| `item_icons.blend` → `assets/icons/` | build_icons | 器のアイコン。金のメダル＝能力、灰色＋赤い輪と斜線＝禁止。記号は矢印（W/A/S/D）・二重の山形（ジャンプ）・矢印と流れる線（ダッシュ）など |

2026-11-20 に `goal_beacon`（石の柱と回る結晶）をやめ、`goal_flag` に置き換えた。

すべて生成スクリプトで作った自作のモデルで、外部素材・3D生成AI（Tripo など）は使っていない。Tripo を使うときは、出力の利用規約と、コンテストの AI 利用ガイドラインに沿って `docs/ai-usage.md` に記録する。
