extends SceneTree
## 装備の入れ物（docs/adr/0018）のスクリーンショット（docs/images/ux/）。撮り方は capture_range_ux.gd と同じ
## （lavapipe ＋ xvfb で Forward+、HUD も入ったゲーム本体の画面）:
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver vulkan --resolution 1280x720 \
##     --script res://tools/capture_equipment_ux.gd -- <state> out.png
## state: full（ホットバーのブーツと、身につけたグローブ。中身が入っている）
##        / empty（ホットバーのブーツから、中の能力をブロックへ渡した後。ブーツは薄く、点線の輪が付く）
## 持ち物の画面を開き、ホットバーのブーツを選んだところを撮る（下のホットバー・左の装備欄・右の説明が入る）。


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	var state := args[0] if not args.is_empty() else "full"
	var out := args[1] if args.size() > 1 else "equipment.png"
	var game := (load("res://scenes/prototype_island.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	game.call(&"start_solo", "zz_capture")
	var director := game.get("director") as PartyDirector
	director.enter_stage("w1_push_path")
	for i in 20:
		await physics_frame
	var w := director.world
	var me := w.acting_id()
	var ledger := w.ledger
	var boots := ledger.place_in_world(
		RuleAction.Kind.HIGH_JUMP, false, Vector3.ZERO, RuleVessel.Part.FEET, "ジャンプブーツ"
	)
	ledger.pickup(boots.id, me)
	var gloves := ledger.place_in_world(
		RuleAction.Kind.CLIMB, false, Vector3.ZERO, RuleVessel.Part.HANDS, "クライミンググローブ"
	)
	ledger.pickup(gloves.id, me)
	ledger.equip(gloves.id)
	var slot := 7
	if ledger.hotbar_vessel(slot, me) != null:
		ledger.move_to_inventory(ledger.hotbar_vessel(slot, me).id)
	ledger.move_to_hotbar(boots.id, slot)
	if state == "empty":
		var block: RuleBlock = w.blocks.values()[0]
		ledger.lend(boots.id, PackedInt32Array([block.entity_id]), TriggerMode.Kind.NONE)
	w.select_slot(slot)
	for i in 10:
		await physics_frame
	var hud := game.get("_hud") as Hud
	hud.toggle_inventory()
	hud.inventory.select_vessel(boots.id)
	for i in 20:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	ProgressStore.new().delete("zz_capture")
	quit()
