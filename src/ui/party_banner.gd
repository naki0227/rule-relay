class_name PartyBanner
extends Control
## 画面上部の小さな札: いまの場所・仲間の数・観戦中・全員リセットの投票（残り秒数）・クリア。
## 協力中にゴールにまだ来ていない人がいれば、2行目に名前を出す（試遊 G5。情報だけ）。
## 文字だけで伝え、色だけに頼らない（企画書 8）。

var director: PartyDirector

var _label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(-360, 14)
	_label.size = Vector2(720, 72)
	_label.add_theme_font_override("font", UiTheme.font(700))
	_label.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	_label.add_theme_color_override("font_color", UiTheme.INK)
	_label.add_theme_color_override("font_outline_color", UiTheme.CREAM)
	_label.add_theme_constant_override("outline_size", 8)
	add_child(_label)


func _process(_delta: float) -> void:
	_label.text = "" if director == null else describe(director)


## 札の文（テスト用にも使う）。
static func describe(d: PartyDirector) -> String:
	if d.world == null:
		return ""
	var parts := PackedStringArray([d.world.def.display_name])
	var count := d.world.ledger.players().size()
	if count > 1:
		parts.append("%d 人" % count)
	if d.in_stage():
		var state := d.lifecycle.state_of(d.local_id())
		if state == PartyLifecycle.State.DEAD_SPECTATING:
			parts.append("観戦中（仲間が台座で %s を押すと復活）" % InputMode.key(&"interact"))
		elif state == PartyLifecycle.State.WAITING_SPECTATOR:
			parts.append("観戦中（次の全員リセットで合流）")
		if d.lifecycle.is_vote_open():
			(
				parts
				. append(
					(
						"全員リセットの投票 %d / %d（%s 長押しで賛成・残り %d 秒）"
						% [
							d.lifecycle.yes_vote_count(),
							d.lifecycle.required_votes(),
							InputMode.key(&"vote_reset"),
							ceili(d.lifecycle.vote_seconds_left()),
						]
					)
				)
			)
		else:
			parts.append("%s 長押し: 全員リセットの投票" % InputMode.key(&"vote_reset"))
	if d.last_clear_text != "" and d.in_stage():
		parts.append(d.last_clear_text)
	var text := "　".join(parts)
	var missing := d.goal_missing_text()
	return text if missing == "" else text + "\n" + missing
