class_name LedgerValidator
extends RefCounted
## RuleLedger の不変条件を検査する（テスト・デバッグ用）。空の配列なら正常。
## - トークンは「元の器の中」「付与先」「プレイヤーが器なしで持っている」「世界に落ちている」
##   「レベルに設置」のどれか1か所にだけある（複製しない）
## - 器はプレイヤーごとのホットバー（9枠）・通常インベントリ・装備欄、または世界（未回収）にある
## - プレイヤーは付与先（holder）にならない。プレイヤー間の受け渡しは carrier_id で表す


static func check(ledger: RuleLedger) -> PackedStringArray:
	var errors := PackedStringArray()
	_check_vessels(ledger, errors)
	_check_slots(ledger, errors)
	for t in ledger.all_tokens():
		_check_token(ledger, t, errors)
	return errors


static func _check_vessels(ledger: RuleLedger, errors: PackedStringArray) -> void:
	for v in ledger.all_vessels():
		var t := ledger.token(v.token_id)
		if t == null:
			errors.append("vessel %d has missing token %d" % [v.id, v.token_id])
		elif t.vessel_id != v.id:
			errors.append("token %d does not point back to vessel %d" % [t.id, v.id])
		var in_world := v.location == RuleVessel.Location.WORLD
		if in_world and v.owner_id != -1:
			errors.append("vessel %d is in the world but owned by %d" % [v.id, v.owner_id])
		if not in_world and not _is_player(ledger, v.owner_id):
			errors.append("vessel %d is carried by non-player %d" % [v.id, v.owner_id])
		if in_world and t != null and not t.is_in_vessel():
			errors.append("token %d left a vessel still in the world" % v.token_id)


static func _check_slots(ledger: RuleLedger, errors: PackedStringArray) -> void:
	var used_slots := {}
	var used_parts := {}
	for v in ledger.all_vessels():
		if v.location == RuleVessel.Location.HOTBAR:
			var key := Vector2i(v.owner_id, v.slot)
			if v.slot < 0 or v.slot >= RuleLedger.HOTBAR_SIZE:
				errors.append("vessel %d has invalid hotbar slot %d" % [v.id, v.slot])
			elif used_slots.has(key):
				errors.append("hotbar slot %d of player %d used twice" % [v.slot, v.owner_id])
			used_slots[key] = true
		elif v.location == RuleVessel.Location.EQUIPPED:
			var part_key := Vector2i(v.owner_id, v.part)
			if not v.is_equipment():
				errors.append("vessel %d is equipped but is not equipment" % v.id)
			elif used_parts.has(part_key):
				errors.append("part %d of player %d equipped twice" % [v.part, v.owner_id])
			used_parts[part_key] = true


static func _check_token(ledger: RuleLedger, t: RuleToken, errors: PackedStringArray) -> void:
	var places := 0
	places += 1 if t.is_lent() else 0
	places += 1 if t.carrier_id != -1 else 0
	places += 1 if t.dropped else 0
	if places > 1:
		errors.append("token %d is in %d places at once" % [t.id, places])
	if t.vessel_id == -1 and places == 0:
		errors.append("token %d is neither in a vessel nor placed" % t.id)
	if t.vessel_id != -1 and ledger.vessel(t.vessel_id) == null:
		errors.append("token %d points to missing vessel" % t.id)
	if t.carrier_id != -1:
		_check_carrier(ledger, t, errors)
	for holder in t.holder_ids:
		if not ledger.has_entity(holder):
			errors.append("token %d held by unknown entity %d" % [t.id, holder])
		elif ledger.entity_kind(holder) == EntityKind.Kind.PLAYER:
			errors.append("token %d lent to a player" % t.id)


static func _check_carrier(ledger: RuleLedger, t: RuleToken, errors: PackedStringArray) -> void:
	if not _is_player(ledger, t.carrier_id):
		errors.append("token %d carried by non-player %d" % [t.id, t.carrier_id])
	var v := ledger.vessel(t.vessel_id)
	if v != null and v.owner_id == t.carrier_id:
		errors.append("token %d is carried by its own vessel owner" % t.id)


static func _is_player(ledger: RuleLedger, id: int) -> bool:
	return ledger.has_entity(id) and ledger.entity_kind(id) == EntityKind.Kind.PLAYER
