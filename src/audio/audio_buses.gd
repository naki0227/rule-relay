class_name AudioBuses
extends RefCounted
## 音のバスの並び（設計は docs/sound-design.md）。エディターのバス配置ファイルは使わず、
## 起動時にここで作る（効果音の SoundBank と同じ方式。無ければ作り、あれば触らない）。
##   Master ← SFX（効果音の音量） ← UI（−2dB）・World（0dB）
##   Master ← Music（BGM の音量）
## 設定の「BGM の音量」は Music、「効果音の音量」は SFX のバスの音量にする。

const MUSIC := &"Music"
const SFX := &"SFX"
const UI := &"UI"
const WORLD := &"World"

## [名前, 基準の音量 dB, 送り先]。送り先は自分より前（番号が小さい）バスにする（Godot は後ろから順に混ぜる）。
const LAYOUT: Array[Array] = [
	[SFX, 0.0, &"Master"],
	[UI, -2.0, SFX],
	[WORLD, 0.0, SFX],
	[MUSIC, 0.0, &"Master"],
]


## 足りないバスを作り、送り先をそろえる。何度呼んでもよい。
static func ensure() -> void:
	for spec: Array in LAYOUT:
		var bus_name := StringName(spec[0])
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_volume_db(index, float(spec[1]))
	# SFX は UI・World より前に置く（後ろにあると、UI・World から送った音が混ざらない）
	var sfx := AudioServer.get_bus_index(SFX)
	var first_child := mini(AudioServer.get_bus_index(UI), AudioServer.get_bus_index(WORLD))
	if sfx > first_child:
		AudioServer.move_bus(sfx, first_child)
	for spec: Array in LAYOUT:
		var index := AudioServer.get_bus_index(StringName(spec[0]))
		AudioServer.set_bus_send(index, StringName(spec[2]))


## 音量（0〜100%）をバスへ。0% は消音にする。
static func set_volume_percent(bus_name: StringName, percent: int) -> void:
	ensure()
	var index := AudioServer.get_bus_index(bus_name)
	var p := clampi(percent, 0, 100)
	AudioServer.set_bus_mute(index, p == 0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(float(p), 1.0) / 100.0))
