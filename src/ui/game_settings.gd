class_name GameSettings
extends RefCounted
## 遊ぶ人ごと（PC ごと）の設定: 文字の大きさ、視点の速さ（マウス・パッド）、キー割り当て。
## `user://settings.cfg`（ConfigFile）に保存し、起動時に読んで反映する。秘密の情報は入れない。
## 記録の名前（プロファイル）には依存しない（同じ PC の同じ人の手に合わせる設定なので）。

const DEFAULT_PATH: String = "user://settings.cfg"
const VERSION: int = 1

## 文字の大きさ（画面全体の UI の拡大率）。canvas_items の拡大縮小に掛ける。
const SCALES: PackedFloat32Array = [0.9, 1.0, 1.15, 1.3]
const SCALE_NAMES: PackedStringArray = ["小さめ", "ふつう", "大きめ", "とても大きい"]
const DEFAULT_SCALE_STEP: int = 1

## 視点の速さの倍率（1.0 が初期値。マウスは CameraRig.SENSITIVITY、パッドは
## PlayerInput.PAD_LOOK_SPEED に掛ける）。
const SENSITIVITY_MIN: float = 0.3
const SENSITIVITY_MAX: float = 3.0

## 起動時に読んだ設定（GameRoot が読み込む）。テストでは差し替えてよい。
static var current: GameSettings

var path: String = DEFAULT_PATH
var scale_step: int = DEFAULT_SCALE_STEP
var mouse_sensitivity: float = 1.0
var pad_sensitivity: float = 1.0
var bindings: KeyBindings = KeyBindings.new()


func _init(p_path: String = DEFAULT_PATH) -> void:
	path = p_path


## いまの設定（まだ読んでいなければ初期値）。
static func get_current() -> GameSettings:
	if current == null:
		current = GameSettings.new()
	return current


## 起動時: 保存した設定を読んで、画面と入力へ反映する。
static func load_and_apply(tree: SceneTree, p_path: String = DEFAULT_PATH) -> GameSettings:
	current = GameSettings.new(p_path)
	current.load_file()
	current.apply(tree)
	return current


func ui_scale() -> float:
	return SCALES[scale_step]


func set_scale_step(step: int) -> void:
	scale_step = clampi(step, 0, SCALES.size() - 1)


func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(value, SENSITIVITY_MIN, SENSITIVITY_MAX)


func set_pad_sensitivity(value: float) -> void:
	pad_sensitivity = clampf(value, SENSITIVITY_MIN, SENSITIVITY_MAX)


func reset_to_defaults() -> void:
	scale_step = DEFAULT_SCALE_STEP
	mouse_sensitivity = 1.0
	pad_sensitivity = 1.0
	bindings.reset_to_defaults()


## 画面の拡大率と Input Map を反映する。
func apply(tree: SceneTree) -> void:
	if tree != null and tree.root != null:
		tree.root.content_scale_factor = ui_scale()
	bindings.apply()


## 一時ファイルに書いてから置きかえる（途中で落ちても前の設定が残る）。
func save_file() -> Error:
	var config := ConfigFile.new()
	config.set_value("meta", "version", VERSION)
	config.set_value("display", "scale_step", scale_step)
	config.set_value("look", "mouse", mouse_sensitivity)
	config.set_value("look", "pad", pad_sensitivity)
	bindings.save_to(config, "input")
	var made := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if made != OK:
		return made
	var temp := path + ".tmp"
	var error := config.save(temp)
	if error != OK:
		DirAccess.remove_absolute(temp)
		return error
	return DirAccess.rename_absolute(temp, path)


## 読めない・壊れている・新しすぎる版なら初期値のまま（止まらない）。
func load_file() -> Error:
	reset_to_defaults()
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var config := ConfigFile.new()
	var error := config.load(path)
	if error != OK:
		return error
	if int(_number(config.get_value("meta", "version", VERSION), VERSION)) > VERSION:
		return ERR_FILE_UNRECOGNIZED
	set_scale_step(
		int(
			_number(
				config.get_value("display", "scale_step", DEFAULT_SCALE_STEP), DEFAULT_SCALE_STEP
			)
		)
	)
	set_mouse_sensitivity(_number(config.get_value("look", "mouse", 1.0), 1.0))
	set_pad_sensitivity(_number(config.get_value("look", "pad", 1.0), 1.0))
	bindings.load_from(config, "input")
	return OK


static func _number(value: Variant, fallback: float) -> float:
	if value is int or value is float:
		return float(value)
	return fallback
