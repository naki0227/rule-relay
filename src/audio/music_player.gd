class_name MusicPlayer
extends Node
## BGM を鳴らす係（設計は docs/sound-design.md の「BGM」）。場面（タイトル・ハブ・島）ごとに1曲を決め、
## 場面が変わったら約1.5秒で入れ替える（2つの再生枠を交互に使うクロスフェード）。
## 同じ曲をもう一度頼まれても頭から鳴らし直さない（島のやり直し・全員リセットでも曲は続く）。
## メニュー（Esc・せってい・持ち物）を開いている間は少し下げる（ダッキング）。
## 鳴らすのは Music バス。音量の設定はバスに掛かる（AudioBuses）。

const TITLE := &"title"
const HUB := &"hub"
const STAGE := &"stage"

## 場面 → 曲。**仮の選曲**（AI は音を聴けないため、本人が聴いて決めるまでの暫定）。
## 差し替えるときは、ここのファイル名だけを変える。候補は docs/sound-candidates-2026-11-20.md。
const TRACKS: Dictionary[StringName, String] = {
	TITLE: "res://assets/audio/music/title_1.ogg",  # B5
	HUB: "res://assets/audio/music/hub_1.ogg",  # B1
	STAGE: "res://assets/audio/music/think_1.ogg",  # B3
}
## 入れ替えにかける秒数。
const FADE_SECONDS: float = 1.5
## メニューを開いている間に下げる量（dB）と、下げ・戻しの速さ（dB/秒）。
const DUCK_DB: float = -6.0
const DUCK_SPEED: float = 12.0
## これより小さい音量の割合は無音として扱う。
const SILENT_GAIN: float = 0.001

## いまの場面と曲（曲が無ければ ""）。
var current_scene: StringName = &""
var current_track: String = ""
## テスト用: 曲を頭から鳴らし始めた回数。
var starts: int = 0
## メニューを開いているかを返す関数（GameRoot が Hud.is_menu_open をつなぐ）。無ければ下げない。
var duck_source: Callable

var _players: Array[AudioStreamPlayer] = []
var _gains: PackedFloat32Array = [0.0, 0.0]
var _active: int = 0
var _duck_db: float = 0.0
var _fade: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # 一時停止中（Esc のメニュー）も曲を止めない
	AudioBuses.ensure()
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = AudioBuses.MUSIC
		player.volume_db = linear_to_db(SILENT_GAIN)
		add_child(player)
		_players.append(player)


## 島の ID から場面を決める（ハブ以外の島はどれも「島」）。
static func scene_for_stage(stage_id: String) -> StringName:
	return HUB if stage_id == StageCatalog.HUB_ID else STAGE


static func track_for(scene: StringName) -> String:
	return TRACKS.get(scene, "")


## 場面の曲へ切り替える。曲を鳴らし始めたら true（同じ曲なら何もしないで false）。
func play_scene(scene: StringName) -> bool:
	current_scene = scene
	return play_track(track_for(scene))


## 曲を切り替える（"" なら消していく）。同じ曲が鳴っていれば続ける。
func play_track(path: String) -> bool:
	if path == current_track:
		return false
	current_track = path
	var outgoing := _active
	_active = 1 - _active
	var player := _players[_active]
	player.stream = load(path) as AudioStream if path != "" else null
	_gains[_active] = 0.0
	if player.stream != null:
		starts += 1
		_start(player)
	_crossfade(outgoing)
	return player.stream != null


## いま下げているか（テスト用）。
func is_ducked() -> bool:
	return _wants_duck()


func _process(delta: float) -> void:
	var target := DUCK_DB if _wants_duck() else 0.0
	_duck_db = move_toward(_duck_db, target, DUCK_SPEED * delta)
	for i in _players.size():
		_players[i].volume_db = linear_to_db(maxf(_gains[i], SILENT_GAIN)) + _duck_db


func _wants_duck() -> bool:
	return duck_source.is_valid() and bool(duck_source.call())


func _crossfade(outgoing: int) -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween().set_parallel()
	_fade.tween_method(_set_gain.bind(_active), _gains[_active], 1.0, FADE_SECONDS)
	_fade.tween_method(_set_gain.bind(outgoing), _gains[outgoing], 0.0, FADE_SECONDS)
	_fade.chain().tween_callback(_stop_quiet)


func _set_gain(value: float, index: int) -> void:
	_gains[index] = value


## 消え終わった枠を止める（鳴らしている側は止めない）。
func _stop_quiet() -> void:
	var quiet := _players[1 - _active]
	quiet.stop()
	quiet.stream = null


## 再生を始める。ヘッドレス（CI・テスト）では音の出口がなく、再生中に終了すると
## 「resources still in use at exit」になるので、SoundBank と同じく実際の再生はしない。
func _start(player: AudioStreamPlayer) -> void:
	if DisplayServer.get_name() == "headless":
		return
	player.play()
