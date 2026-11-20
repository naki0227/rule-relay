class_name CompanionBot
extends Node
## 相棒ボット: 部屋に参加者として入り、簡単な決まりで動く仲間（Claude 本人ではない。試遊・1人での協力用）。
## ふつうの参加者と同じく、自分の画面（別の物理世界）で自分のアバターを動かし、操作はホストへの依頼になる。
## 決まり:
## - ふだんは先導役（ホストのプレイヤー）についていく（G で「待って」と「ついてきて」を切り替え）
## - H: 持っている能力を全部、先導役に渡す（近づいてから）
## - R: 先導役のいちばん近くの、能力が付いたブロックへ行って F で回収し、それを先導役に渡す
## - 段差に当たったら、跳べれば跳ぶ。死亡観戦中は何もしない
## 相棒ボットは仕様にない試遊用の機能（本人の確認待ち。docs/adr/0010）。

enum Order { FOLLOW, WAIT, GIVE, RECALL }

const FOLLOW_DISTANCE: float = 2.2
const ARRIVE_DISTANCE: float = 1.6

var director: PartyDirector
var leader_id: int = RuleLedger.PLAYER_ID
var order: Order = Order.FOLLOW

var _give_cooldown: float = 0.0
var _recall_target: int = -1
var _stuck: float = 0.0


func _physics_process(delta: float) -> void:
	var w := director.world if director != null else null
	if w == null or w.player == null or director.is_spectating() or w.player.player_id == leader_id:
		return
	_give_cooldown = maxf(0.0, _give_cooldown - delta)
	var leader := w.avatar_of(leader_id)
	if leader == null:
		_stop()
		return
	match order:
		Order.FOLLOW:
			_walk_to(leader.global_position, FOLLOW_DISTANCE, delta)
		Order.WAIT:
			_stop()
		Order.GIVE:
			if _walk_to(leader.global_position, ARRIVE_DISTANCE, delta):
				_give_everything(leader)
		Order.RECALL:
			_do_recall(leader, delta)


## 先導役からの頼みごと（ホストの PC のキー入力から呼ぶ）。
func toggle_follow() -> String:
	order = Order.WAIT if order == Order.FOLLOW else Order.FOLLOW
	return "相棒: " + ("ここで待ちます" if order == Order.WAIT else "ついていきます")


func ask_give() -> String:
	order = Order.GIVE
	return "相棒: 持っている能力を渡しに行きます"


func ask_recall() -> String:
	var w := director.world
	var leader := w.avatar_of(leader_id)
	_recall_target = -1 if leader == null else _nearest_lent_block(leader.global_position)
	if _recall_target == -1:
		return "相棒: 回収できるブロックが近くにありません"
	order = Order.RECALL
	return "相棒: ブロックの能力を回収してきます"


func _do_recall(leader: PlayerAvatar, delta: float) -> void:
	var w := director.world
	if not w.blocks.has(_recall_target) or w.ledger.tokens_on(_recall_target).is_empty():
		order = Order.GIVE
		return
	var block := w.blocks[_recall_target]
	if _walk_to(block.global_position, ARRIVE_DISTANCE, delta):
		w.interact(block)
		_give_cooldown = 0.5
		order = Order.GIVE
	elif leader == null:
		_stop()


## 持っている能力（自分の器の中のもの・受け取ったもの）を1つずつ渡す。無くなったらついていく。
func _give_everything(leader: PlayerAvatar) -> void:
	if _give_cooldown > 0.0:
		return
	var w := director.world
	var me := w.player.player_id
	for slot in RuleLedger.HOTBAR_SIZE:
		if WorldQueries.giveable_token(w.ledger, me, slot) != -1:
			w.select_slot(slot)
			w.lend_to(leader, false)
			_give_cooldown = 0.25
			return
	order = Order.FOLLOW


func _nearest_lent_block(at: Vector3) -> int:
	var w := director.world
	var best := -1
	var best_distance := 12.0
	for id in w.blocks:
		var has_lent := false
		for t in w.ledger.tokens_on(id):
			has_lent = has_lent or t.lender_id != -1
		var d := w.blocks[id].global_position.distance_to(at)
		if has_lent and d < best_distance:
			best = id
			best_distance = d
	return best


## target へ歩く。着いたら（stop 以内）true。段差に当たったら跳べれば跳ぶ。
func _walk_to(target: Vector3, stop: float, delta: float) -> bool:
	var body := director.world.player
	var flat := Vector3(target.x - body.global_position.x, 0.0, target.z - body.global_position.z)
	if flat.length() <= stop:
		_stop()
		return true
	body.view_yaw = atan2(-flat.x, -flat.z)
	body.move_intent = Vector2(0.0, 1.0)
	var moving := Vector2(body.velocity.x, body.velocity.z).length() > 0.5
	_stuck = 0.0 if moving else _stuck + delta
	if body.is_on_floor() and (body.is_on_wall() or _stuck > 0.4):
		director.world.press_action(RuleAction.Kind.JUMP)
		_stuck = 0.0
	return false


func _stop() -> void:
	if director.world != null and director.world.player != null:
		director.world.player.move_intent = Vector2.ZERO
