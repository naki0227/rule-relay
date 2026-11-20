class_name ArtPalette
extends RefCounted
## 3D モデルの色の窓口。Blender 側の art/scripts/palette.py と同じ値・同じマテリアル名にそろえる。
## 世界観が決まって色を変えるときは、両方を直してモデルを書き出し直す（docs/art-direction.md）。

## プレイヤー1〜4の布の色（明るい色と、縁・裏地の濃い色）。明るさも少しずつ変えて、色だけに頼らない。
const PLAYER_COLORS: Array[Color] = [
	Color("#6fa8dc"),
	Color("#ec8a6a"),
	Color("#82b866"),
	Color("#b794d9"),
]
const PLAYER_COLORS_DEEP: Array[Color] = [
	Color("#4f86bd"),
	Color("#c96a4d"),
	Color("#5f9548"),
	Color("#9172b8"),
]
## ゲーム側で色を差し替えるマテリアルの名前（palette.py の ACCENT / ACCENT_DEEP）。
const ACCENT := "Accent"
const ACCENT_DEEP := "AccentDeep"
## 器のメダルの面に重ねる記号の色。
const GLYPH_ABILITY := Color("#7a4e16")
const GLYPH_BAN := Color("#55525a")


## プレイヤー ID（1 から）を色の番号 0〜3 にする。5人目以降は色を繰り返す。
static func player_index(player_id: int) -> int:
	return posmod(player_id - RuleLedger.PLAYER_ID, PLAYER_COLORS.size())


static func player_color(player_id: int) -> Color:
	return PLAYER_COLORS[player_index(player_id)]


## プレイヤーのモデル（traveler）の布をその人の色にする。
static func tint_player(model: Node, player_id: int) -> void:
	var index := player_index(player_id)
	ModelLibrary.tint_material(model, ACCENT, PLAYER_COLORS[index])
	ModelLibrary.tint_material(model, ACCENT_DEEP, PLAYER_COLORS_DEEP[index])
