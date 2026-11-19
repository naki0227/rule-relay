class_name GameRoot
extends Node
## メインシーンの入口。島（ルールと物理）・HUD・入力を組み立てる。
## テストは PrototypeIsland だけを木に追加し、HUD と入力なしで操作する。


func _ready() -> void:
	var island := PrototypeIsland.new()
	island.name = "Island"
	add_child(island)
	var sounds := SoundBank.new()
	sounds.name = "Sounds"
	add_child(sounds)
	island.sound_requested.connect(
		func(event: StringName, at: Vector3, positional: bool) -> void:
			if positional:
				sounds.play_at(event, at)
			else:
				sounds.play_ui(event)
	)
	var hud := Hud.new()
	hud.name = "Hud"
	hud.world = island
	hud.sounds = sounds
	add_child(hud)
	var input := PlayerInput.new()
	input.name = "PlayerInput"
	input.world = island
	input.hud = hud
	add_child(input)
