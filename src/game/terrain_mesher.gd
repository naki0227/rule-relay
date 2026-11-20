class_name TerrainMesher
extends RefCounted
## 地形のセルから、「ブロックでできているのに角張って見えない」1つのメッシュをその場で作る。
## セルに能力を渡すとそのセルは動くブロックになって地形から抜けるので、Blender で作り置きせず
## 実行時に作り直す（2026-11-19 本人の判断: どのブロックにも渡せる）。
##
## 作り方:
## - 外に出ている面だけを作る（内側の継ぎ目は出ない）。下向きの面は作らない（島の土台で隠れる）
## - 外に出た角（凸）を半径 RADIUS で丸める。面の点 p を、角の近くだけ「角丸の箱」の表面へ写す
##   （中心 c = p − 法線×r を、近い辺の方向に r だけ内側へ寄せ、p' = c + r × 正規化(p − c)）。
##   となりの面も同じ式で同じ点に写るので、つなぎ目に隙間ができない。入り組んだ角（凹）は丸めない
## - 色は頂点の色。草のセルは上面と、上の縁から少し下まで草色。セルごとに色をわずかに変える

const RADIUS: float = 0.16
const GRASS_LIP: float = 0.24

const COLORS := {
	"grass": [Color("#84bd5f"), Color("#8dc567")],
	"dirt": [Color("#b88a5c"), Color("#c0936a")],
	"rock": [Color("#b3a48e"), Color("#c1b39c")],
	"sand": [Color("#e6c995"), Color("#eed4a6")],
}

const NORMALS: Array[Vector3i] = [
	Vector3i(1, 0, 0),
	Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0),
	Vector3i(0, 0, 1),
	Vector3i(0, 0, -1),
]


## cells: {Vector3i: 種類（grass / rock / sand）}
static func build(cells: Dictionary) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for cell: Vector3i in cells:
		for n in NORMALS:
			if cells.has(cell + n):
				continue
			_add_face(cells, cell, n, verts, normals, colors, indices)
	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true  # 色は sRGB で書いている（無いと白っぽく飛ぶ）
	material.roughness = 0.9
	mesh.surface_set_material(0, material)
	return mesh


static func _add_face(
	cells: Dictionary,
	cell: Vector3i,
	n: Vector3i,
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array
) -> void:
	# 面の上の2軸（正の向き）。x 向きの面は z と y、y 向きは x と z、z 向きは x と y
	var u := Vector3i(0, 0, 1) if n.x != 0 else Vector3i(1, 0, 0)
	var v := Vector3i(0, 0, 1) if n.y != 0 else Vector3i(0, 1, 0)
	var origin := Vector3(cell) + (Vector3(n) if n.x + n.y + n.z > 0 else Vector3.ZERO)
	var low_u := not cells.has(cell - u)
	var high_u := not cells.has(cell + u)
	var low_v := not cells.has(cell - v)
	var high_v := not cells.has(cell + v)
	var a_list := _samples(low_u, high_u)
	var b_list := _samples(low_v, high_v)
	var nf := Vector3(n)
	var base := verts.size()
	var kind := String(cells[cell])
	var light := _hash(cell) > 0.55
	var top := float(cell.y + 1)
	for b in b_list:
		for a in a_list:
			var p := origin + Vector3(u) * a + Vector3(v) * b
			var c := p - nf * RADIUS
			if low_u and a < RADIUS:
				c += Vector3(u) * (RADIUS - a)
			if high_u and a > 1.0 - RADIUS:
				c -= Vector3(u) * (a - (1.0 - RADIUS))
			if low_v and b < RADIUS:
				c += Vector3(v) * (RADIUS - b)
			if high_v and b > 1.0 - RADIUS:
				c -= Vector3(v) * (b - (1.0 - RADIUS))
			var out := (p - c).normalized()
			verts.append(c + out * RADIUS)
			normals.append(out)
			colors.append(_color(kind, light, n, p.y, top, out))
	var w := a_list.size()
	for j in b_list.size() - 1:
		for i in w - 1:
			var i0 := base + j * w + i
			var tri := [i0, i0 + 1, i0 + w + 1, i0, i0 + w + 1, i0 + w]
			var p0 := verts[tri[0]]
			var face_normal := (verts[tri[1]] - p0).cross(verts[tri[2]] - p0)
			if face_normal.dot(nf) > 0.0:  # Godot は時計回りが表
				tri = [i0, i0 + w + 1, i0 + 1, i0, i0 + w, i0 + w + 1]
			for k: int in tri:
				indices.append(k)


## 面の上の分割位置（0〜1）。丸める辺の側だけ細かくする。
static func _samples(low: bool, high: bool) -> PackedFloat32Array:
	var list := PackedFloat32Array([0.0])
	if low:
		list.append_array([RADIUS / 3.0, RADIUS * 2.0 / 3.0, RADIUS])
	if high:
		list.append_array([1.0 - RADIUS, 1.0 - RADIUS * 2.0 / 3.0, 1.0 - RADIUS / 3.0])
	list.append(1.0)
	return list


static func _color(
	kind: String, light: bool, n: Vector3i, y: float, top: float, out: Vector3
) -> Color:
	var index := 1 if light else 0
	if kind == "grass":
		var grassy := n.y > 0 or out.y > 0.45 or y > top - GRASS_LIP
		return (COLORS["grass"] if grassy else COLORS["dirt"])[index]
	if kind == "sand":
		return COLORS["sand"][index]
	return COLORS["rock"][index]


static func _hash(cell: Vector3i) -> float:
	var h := sin(cell.x * 12.9898 + cell.y * 4.1414 + cell.z * 78.233) * 43758.5453
	return h - floorf(h)
