# art（3Dモデルの原本）

このフォルダは Godot から除外している（`.gdignore`）。ゲームが読むのは `assets/models/*.glb` だけ。

| パス | 内容 |
|---|---|
| `scripts/build_assets.py` | すべてのモデルを生成する Blender の Python スクリプト（正本） |
| `scripts/render_previews.py` | 原本を1枚ずつ描画して確認用の PNG を作る（Cycles・CPU） |
| `source/*.blend` | Blender の原本（スクリプトが書き出す。手で直したら、スクリプトにも反映する） |

## 作り直す

```bash
blender -b --factory-startup --python art/scripts/build_assets.py              # 全部
blender -b --factory-startup --python art/scripts/build_assets.py -- block     # 一部（名前は BUILDERS を参照）
blender -b --factory-startup --python art/scripts/render_previews.py -- /tmp/previews
```

- 使った Blender: **4.5.16 LTS**（公式配布、SHA-256 を検証）。LTS のサポート期間が提出期限より長い版を選んだ。
- 書き出し: glTF バイナリ（`.glb`）、Y-up、モディファイアを適用。カメラ・ライトは含めない。
- 再現性: 乱数は固定シード。形と頂点は毎回同じになるが、三角形の並び順（インデックス）が実行ごとに変わることがあり、`.glb` のバイナリは完全には一致しない（2026-11-18 確認）。

## 約束ごと

- 1 Blender 単位 = 1 m = 1 ブロック。Z が上。
- 地形とブロックは 1x1x1 で、中心が原点。当たり判定はゲーム側の箱で、モデルは見た目だけ。
- キャラクターの正面は Blender の +Y（Godot の前方 -Z になる）。足元が原点。手足・頭は別オブジェクトで、原点を関節に置く（`Body` `Head` `ArmL` `ArmR` `LegL` `LegR`）。ゲームのコードがこの名前で探して振る。
- ブロックの色は、マテリアル名 `Panel` をゲーム側で色違いの複製に置き換えて変える。名前を変えるときは `ModelLibrary.tint_material` の呼び出しも直す。
- 目標の目印は、`Crystal` という名前のノードをゲーム側で回す。

## 現在のモデル（2026-11-18、試作用）

| ファイル | 用途 |
|---|---|
| `traveler` | プレイヤー（仮）。フード付きの小柄な旅人。世界観が未定なので装飾は控えめ |
| `ability_block` | 能力を受け取るブロック。枠＋色を変えるパネル＋四隅の鋲 |
| `grass_cell` / `rock_cell` / `sandstone_cell` | 地形の1セル（草・岩・砂岩） |
| `island_base` | 浮かぶ島の底（ゲーム側で島の大きさに拡大） |
| `tree_round` / `tree_tall` / `grass_tuft` / `flower` / `pebbles` | 置物 |
| `checkpoint_pad` / `goal_beacon` | チェックポイントの台、到達目標の目印 |

すべて生成スクリプトで作った自作のモデルで、外部素材・3D生成AI（Tripo など）は使っていない。Tripo を使うときは、出力の利用規約と、コンテストの AI 利用ガイドラインに沿って `docs/ai-usage.md` に記録する。
