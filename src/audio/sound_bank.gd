class_name SoundBank
extends Node
## 効果音を鳴らす窓口（設計は docs/sound-design.md）。音は tools/sfx/build_sfx.py で作った
## assets/audio/sfx/*.wav（すべて Stable Audio 3 の候補から採用した音。足音は 4 種）。
## 鳴らすたびに音程と音量を少し揺らし、同じ音の繰り返しで疲れないようにする。
## UI の音と世界の音は別のバスに分け、世界の音は位置から鳴らす（遠いと小さい）。

const SFX_DIR := "res://assets/audio/sfx/%s.wav"
const BUS_UI := AudioBuses.UI
const BUS_WORLD := AudioBuses.WORLD
const UI_VOICES: int = 8
const WORLD_VOICES: int = 12
## 同じ音をこの間隔（秒）より短く連打したら鳴らさない（ホバーの連続など）。
const MIN_INTERVAL: float = 0.035

## 音の名前 → 揺らし方。pitch は ± の割合、volume は ± dB。variants は足音のような差し替えで、
## 名前_1〜名前_N のファイルを順番に鳴らす（同じ音が続かない。足音は 4 種、2026-11-20 の本人の判断）。
const EVENTS: Dictionary[StringName, Dictionary] = {
	&"ui_hover": {"pitch": 0.03, "volume": 1.0},
	&"ui_select": {"pitch": 0.0, "volume": 0.5},
	&"ui_confirm": {"pitch": 0.0, "volume": 0.5},
	&"ui_cancel": {"pitch": 0.0, "volume": 0.5},
	&"ui_open": {"pitch": 0.03, "volume": 1.0},
	&"ui_close": {"pitch": 0.03, "volume": 1.0},
	&"ui_pick": {"pitch": 0.05, "volume": 1.0},
	&"ui_drop": {"pitch": 0.04, "volume": 1.0},
	&"ui_error": {"pitch": 0.02, "volume": 0.5},
	# 全員に関わるお知らせ（全員リセットの投票の開始・時間切れ）。UI のバスで鳴らす
	&"ui_notice": {"pitch": 0.0, "volume": 0.5},
	&"radial_open": {"pitch": 0.03, "volume": 1.0},
	&"lend": {"pitch": 0.02, "volume": 1.0},
	&"lend_range": {"pitch": 0.02, "volume": 1.0},
	&"recall": {"pitch": 0.02, "volume": 1.0},
	&"prohibit": {"pitch": 0.03, "volume": 1.0},
	&"receive_wood": {"pitch": 0.04, "volume": 1.0},
	&"receive_stone": {"pitch": 0.04, "volume": 1.0},
	&"receive_grass": {"pitch": 0.04, "volume": 1.0},
	&"receive_creature": {"pitch": 0.04, "volume": 1.0},
	&"block_jump": {"pitch": 0.06, "volume": 1.5},
	&"block_land": {"pitch": 0.06, "volume": 1.5},
	&"block_step": {"pitch": 0.05, "volume": 1.5},
	&"bell": {"pitch": 0.02, "volume": 0.5},
	&"player_jump": {"pitch": 0.05, "volume": 1.5},
	&"player_land": {"pitch": 0.05, "volume": 1.5},
	&"dash": {"pitch": 0.05, "volume": 1.5},
	&"footstep": {"pitch": 0.08, "volume": 2.0, "variants": 4},
	&"save": {"pitch": 0.0, "volume": 0.0},
	&"goal": {"pitch": 0.0, "volume": 0.0},
}
## ホットバーを選んだ音は、枠の番号で音程を変える（ハ長調の五音。1→9 で上がる）。
const SLOT_SEMITONES: Array[int] = [0, 2, 4, 7, 9, 12, 14, 16, 19]

## テスト用: 最後に鳴らした音の名前。
var last_event: StringName = &""
## テスト用: 最後に鳴らした差し替えの番号（差し替えの無い音は 0）。
var last_variant: int = 0

var _streams: Dictionary[String, AudioStream] = {}
var _ui_players: Array[AudioStreamPlayer] = []
var _world_players: Array[AudioStreamPlayer3D] = []
var _last_played: Dictionary[StringName, int] = {}
## 差し替えのある音で、次に鳴らす番号（1 から）。
var _next_variant: Dictionary[StringName, int] = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # 一時停止中もメニューの音を鳴らす
	ensure_buses()
	for i in UI_VOICES:
		var player := AudioStreamPlayer.new()
		player.bus = BUS_UI
		add_child(player)
		_ui_players.append(player)
	for i in WORLD_VOICES:
		var player := AudioStreamPlayer3D.new()
		player.bus = BUS_WORLD
		player.unit_size = 6.0
		player.max_distance = 40.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(player)
		_world_players.append(player)


## UI・世界の2つのバスを用意する（無ければ作る）。世界の音を少し大きく、UI を控えめにする。
## どちらも「効果音の音量」の SFX バスを通る（並びは AudioBuses）。
static func ensure_buses() -> void:
	AudioBuses.ensure()


## UI の音（位置なし）。pitch_semitones で音程をずらす（ホットバーの番号など）。
func play_ui(event: StringName, pitch_semitones: int = 0) -> bool:
	if not _known(event) or _too_soon(event):
		return false
	var stream := _stream_for(event, _take_variant(event))
	if stream == null:
		return false
	var player := _free_ui_player()
	player.stream = stream
	_apply_variation(player, event, pitch_semitones)
	_start(player)
	last_event = event
	return true


## 世界の音（位置あり）。名前の後ろに「@半音」を付けると音程をずらす（例: lend@7。法則の音の能力ごとの音程）。
func play_at(event: StringName, at: Vector3) -> bool:
	var semitones := 0
	var event_name := String(event)
	if event_name.contains("@"):
		semitones = int(event_name.get_slice("@", 1))
		event = StringName(event_name.get_slice("@", 0))
	if not _known(event) or _too_soon(event) or not is_inside_tree():
		return false
	var stream := _stream_for(event, _take_variant(event))
	if stream == null:
		return false
	var player := _free_world_player()
	player.stream = stream
	player.global_position = at
	_apply_variation(player, event, semitones)
	_start(player)
	last_event = event
	return true


## 再生を始める。ヘッドレス（CI・テスト）では音の出口がない（Dummy ドライバー）うえ、再生中に
## 終了すると音声サーバーが再生を手放さず「resources still in use at exit」になるため、
## 鳴らす判断（どの音か・間引き・揺らぎ）までにして実際の再生はしない（2026-11-19 に確認）。
func _start(player: Node) -> void:
	if DisplayServer.get_name() == "headless":
		return
	player.call(&"play")


func play_slot_select(slot: int) -> bool:
	return play_ui(&"ui_select", SLOT_SEMITONES[clampi(slot, 0, SLOT_SEMITONES.size() - 1)])


## 音のファイルがそろっているか（差し替えのある音は全部の番号）。鳴らす順番は進めない。
func has_event(event: StringName) -> bool:
	if not EVENTS.has(event):
		return false
	var count := variant_count(event)
	if count <= 0:
		return _stream_for(event, 0) != null
	for variant in range(1, count + 1):
		if _stream_for(event, variant) == null:
			return false
	return true


## 差し替えの数（無ければ 0）。
func variant_count(event: StringName) -> int:
	return int(EVENTS[event].get("variants", 0)) if EVENTS.has(event) else 0


## 次に鳴らす差し替えの番号を返し、順番を1つ進める（差し替えが無ければ 0）。
func _take_variant(event: StringName) -> int:
	var count := variant_count(event)
	if count <= 0:
		last_variant = 0
		return 0
	var variant: int = _next_variant.get(event, 1)
	_next_variant[event] = variant % count + 1
	last_variant = variant
	return variant


func _known(event: StringName) -> bool:
	if EVENTS.has(event):
		return true
	push_warning("unknown sound event: %s" % event)
	return false


## variant が 1 以上なら「名前_番号」のファイル、0 なら「名前」のファイル。
func _stream_for(event: StringName, variant: int) -> AudioStream:
	var file := String(event) if variant <= 0 else "%s_%d" % [event, variant]
	if not _streams.has(file):
		_streams[file] = load(SFX_DIR % file) as AudioStream
	return _streams[file]


func _too_soon(event: StringName) -> bool:
	var now := Time.get_ticks_msec()
	var last: int = _last_played.get(event, -100000)
	if now - last < int(MIN_INTERVAL * 1000.0):
		return true
	_last_played[event] = now
	return false


func _apply_variation(player: Node, event: StringName, semitones: int) -> void:
	var spec := EVENTS[event]
	var pitch := pow(2.0, semitones / 12.0)
	var p := float(spec.get("pitch", 0.0))
	pitch *= 1.0 + _rng.randf_range(-p, p)
	var v := float(spec.get("volume", 0.0))
	var volume := _rng.randf_range(-v, v)
	player.set("pitch_scale", pitch)
	player.set("volume_db", volume)


func _free_ui_player() -> AudioStreamPlayer:
	for player in _ui_players:
		if not player.playing:
			return player
	return _ui_players[0]  # 全部鳴っていたら、いちばん古い枠を使い回す


func _free_world_player() -> AudioStreamPlayer3D:
	for player in _world_players:
		if not player.playing:
			return player
	return _world_players[0]
