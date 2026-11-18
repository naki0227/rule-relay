class_name GameRoot
extends Node
## メインシーンの入口。島（ルールと物理）・HUD・入力を組み立てる。
## テストは PrototypeIsland だけを木に追加し、HUD と入力なしで操作する。


func _ready() -> void:
	var island := PrototypeIsland.new()
	island.name = "Island"
	add_child(island)
	var hud := Hud.new()
	hud.name = "Hud"
	hud.world = island
	add_child(hud)
	var input := PlayerInput.new()
	input.name = "PlayerInput"
	input.world = island
	input.hud = hud
	add_child(input)
