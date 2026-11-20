extends TestCase
## 相棒ボット: 部屋を作ってボットを呼ぶと、参加者として入ってきて、ついてきて、頼むと能力をくれる。
## ボットは別の通信と物理の世界で動く、ふつうの参加者（ホストから見ると仲間のアバター）。

const PROFILE := "zz_test_bot_host"
const JUMP := RuleAction.Kind.JUMP

var root: GameRoot


func before_each() -> void:
	ProgressStore.new().delete(PROFILE)
	root = GameRoot.new()
	root.name = "GameRoot"
	tree.root.add_child(root)
	await tree.process_frame
	root.start_host(PROFILE, 36000 + randi() % 2000, true)
	await _until(func() -> bool: return root.director.world.ledger.players().size() == 2)
	await _until(func() -> bool: return root.director.world.avatars.has(2))
	await wait_physics_frames(20)


func after_each() -> void:
	root.shutdown()
	root.queue_free()
	await tree.process_frame
	await tree.process_frame
	ProgressStore.new().delete(PROFILE)
	ProgressStore.new().delete("companion_bot")


func _until(condition: Callable) -> void:
	for i in 600:
		if condition.call():
			return
		await tree.physics_frame
	fail("timed out")


func _bot_avatar() -> PlayerAvatar:
	return root.director.world.avatars[2]


func test_bot_joins_as_a_teammate() -> void:
	assert_eq(root.director.world.ledger.ability_count(JUMP, 2), 1, "the bot got hub items")
	assert_ne(root.bot, null)


func test_bot_follows_the_leader() -> void:
	var me := root.director.world.player
	me.global_position = me.global_position + Vector3(-5.0, 0.0, -4.0)
	me.velocity = Vector3.ZERO
	await _until(
		func() -> bool: return _bot_avatar().global_position.distance_to(me.global_position) < 3.2
	)


func test_bot_gives_its_abilities_when_asked() -> void:
	root.handle_party_action(&"bot_give")
	await _until(func() -> bool: return root.director.world.ledger.ability_count(JUMP, 1) == 2)
	assert_eq(root.director.world.ledger.ability_count(JUMP, 2), 0)
	assert_eq(root.director.world.ledger.ability_count(RuleAction.Kind.FORWARD, 1), 2, "W x2 too")
