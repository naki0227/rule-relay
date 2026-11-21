class_name ItemIcons
extends RefCounted
## 器（能力・禁止）のアイコン。Blender で描画した assets/icons/*.png（art/scripts/build_icons.py）。
## 装備（ジャンプブーツ・クライミンググローブ）は、ゲームの 3D モデルから描いた装備の姿
## （assets/icons/equipment_*.png、art/scripts/build_equipment_icons.py。docs/adr/0018）。

static var _cache: Dictionary[String, Texture2D] = {}


static func for_token(t: RuleToken) -> Texture2D:
	var key := "%s_%s" % ["prohibition" if t.is_prohibition else "ability", _action_key(t.action)]
	if not _cache.has(key):
		_cache[key] = load("res://assets/icons/%s.png" % key) as Texture2D
	return _cache[key]


## 器のアイコン。装備なら装備の姿（中の能力が抜けていても同じ絵。空の見た目は ItemPainter が付ける）。
static func for_item(t: RuleToken, equipment: bool) -> Texture2D:
	if equipment and has_equipment_icon(t.action):
		var key := "equipment_%s" % _action_key(t.action)
		if not _cache.has(key):
			_cache[key] = load("res://assets/icons/%s.png" % key) as Texture2D
		return _cache[key]
	return for_token(t)


## 装備の姿のアイコンがある行動か（いまはジャンプブーツ＝高跳び・クライミンググローブ＝登る）。
static func has_equipment_icon(action: RuleAction.Kind) -> bool:
	return action == RuleAction.Kind.HIGH_JUMP or action == RuleAction.Kind.CLIMB


## 記号だけの白い絵（世界に落ちている器の3Dメダルの面に、色を付けて重ねる）。
static func glyph(action: RuleAction.Kind) -> Texture2D:
	var key := "glyph_%s" % _action_key(action)
	if not _cache.has(key):
		_cache[key] = load("res://assets/icons/%s.png" % key) as Texture2D
	return _cache[key]


static func _action_key(action: RuleAction.Kind) -> String:
	match action:
		RuleAction.Kind.FORWARD:
			return "forward"
		RuleAction.Kind.LEFT:
			return "left"
		RuleAction.Kind.BACK:
			return "back"
		RuleAction.Kind.RIGHT:
			return "right"
		RuleAction.Kind.THROW:
			return "throw"
		RuleAction.Kind.HIGH_JUMP:
			return "high_jump"
		RuleAction.Kind.CLIMB:
			return "climb"
		RuleAction.Kind.DASH:
			return "dash"
		RuleAction.Kind.HEAVY:
			return "heavy"
		RuleAction.Kind.FLOAT:
			return "float"
		RuleAction.Kind.SWIM:
			return "swim"
	return "jump"
