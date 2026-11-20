# art（3Dモデルの原本）

このフォルダは Godot から除外している（`.gdignore`）。ゲームが読むのは `assets/models/*.glb` だけ。

| パス | 内容 |
|---|---|
| `scripts/palette.py` | 共有の色（パレット）と丸い形の部品（回転体・カプセル・輪・角丸の箱）。色はここだけで決める |
| `scripts/build_assets.py` | 地形のセル・能力のブロック・木・草花などを生成する（共通の関数もここ） |
| `scripts/build_cast.py` | プレイヤー（4色）・願いを持つ生き物・その子ども（kit） |
| `scripts/build_markers.py` | ゴールの旗と四隅の灯り・チェックポイントの台・入口の門・器のメダル（能力／禁止）・装備（ジャンプブーツ・クライミンググローブ）・ダッシュの羽根 |
| `scripts/build_hub_props.py` | 広場の置物（街灯・柵・鉢植え・ベンチ） |
| `scripts/build_contraptions.py` | 発射台と鐘（テクスチャを焼き込む） |
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
blender -b --factory-startup --python art/scripts/build_icons.py               # アイコン
blender -b --factory-startup --python art/scripts/render_previews.py -- /tmp/previews traveler goal_flag
```

ゲームの中での見え方は `tools/capture_models.gd`（lavapipe＋xvfb、`lineup` / `hub` / `nest`）で撮って確かめる。
書き出した後は `godot --headless --import` で取り込み、警告が出ないことを確かめる。

- 使った Blender: **4.5.16 LTS**（公式配布、SHA-256 を検証）。LTS のサポート期間が提出期限より長い版を選んだ。
- 書き出し: glTF バイナリ（`.glb`）、Y-up、モディファイアを適用。カメラ・ライトは含めない。
- 再現性: 乱数は固定シード。形と頂点は毎回同じになるが、三角形の並び順（インデックス）が実行ごとに変わることがあり、`.glb` のバイナリは完全には一致しない（2026-11-18 確認）。

## 約束ごと

- 1 Blender 単位 = 1 m = 1 ブロック。Z が上。
- 地形とブロックは 1x1x1 で、中心が原点。当たり判定はゲーム側の箱で、モデルは見た目だけ。
- キャラクターの正面は Blender の +Y（Godot の前方 -Z になる）。足元が原点。手足・頭は別オブジェクトで、原点を関節に置く（`Body` `Head` `ArmL` `ArmR` `LegL` `LegR`）。ゲームのコードがこの名前で探して振る。
- ブロックの色は、マテリアル名 `Panel` をゲーム側で色違いの複製に置き換えて変える。名前を変えるときは `ModelLibrary.tint_material` の呼び出しも直す。
- プレイヤーの色違いは、マテリアル名 `Accent`（布）と `AccentDeep`（縁・裏地）を `ArtPalette.tint_player` が差し替える。4色の値は `palette.py` の `PLAYER_COLORS` と `src/game/art_palette.gd` で同じにする。
- ゴールの旗は、布の `Flag` という子オブジェクトをゲーム側（`GoalMarker`）が竿を軸に揺らす。
- 器のメダルは正面が ±Y。記号はモデルに刻まず、ゲームが `glyph_*.png` を面に重ねる（記号を増やしてもモデルは1つ）。
- 色を変える（世界観が決まって塗り直す）ときは `palette.py` を直して全スクリプトを実行し直す。形は変えない。

## 現在のモデル（2026-11-20）

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
| `hub_lamp` / `hub_fence` / `hub_planter` / `hub_bench` | build_hub_props | 広場の飾り（`HubDressing`。当たり判定なし） |
| `ability_block` | build_assets | 能力を受け取るブロック。枠＋色を変えるパネル＋四隅の鋲 |
| `grass_cell` / `rock_cell` / `sandstone_cell` | build_assets | 地形の1セル（草・岩・砂岩） |
| `island_base` | build_assets | 浮かぶ島の底（ゲーム側で島の大きさに拡大） |
| `tree_round` / `tree_tall` / `grass_tuft` / `flower` / `pebbles` | build_assets | 置物 |
| `launcher` / `bell` | build_contraptions | 発射台と鐘（テクスチャを焼き込む） |
| `item_icons.blend` → `assets/icons/` | build_icons | 器のアイコン。金のメダル＝能力、灰色＋赤い輪と斜線＝禁止。記号は矢印（W/A/S/D）・二重の山形（ジャンプ）・矢印と流れる線（ダッシュ）など |

2026-11-20 に `goal_beacon`（石の柱と回る結晶）をやめ、`goal_flag` に置き換えた。

すべて生成スクリプトで作った自作のモデルで、外部素材・3D生成AI（Tripo など）は使っていない。Tripo を使うときは、出力の利用規約と、コンテストの AI 利用ガイドラインに沿って `docs/ai-usage.md` に記録する。
