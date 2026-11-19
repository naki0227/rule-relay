class_name ItemIcons
extends RefCounted
## 器（能力・禁止）のアイコン。Blender で描画した assets/icons/*.png（art/scripts/build_icons.py）。

static var _cache: Dictionary[String, Texture2D] = {}


static func for_token(t: RuleToken) -> Texture2D:
	var key := "%s_%s" % ["prohibition" if t.is_prohibition else "ability", _action_key(t.action)]
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
	return "jump"
