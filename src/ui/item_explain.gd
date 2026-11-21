class_name ItemExplain
extends RefCounted
## 持ち物の画面の詳しい説明の文（行動の意味と、いまの状態で何が起きているか）。InventoryPanel から切り出した。


## 器ごとの説明: 行動の意味と、いまの状態で何が起きているか（短く）。
static func explain(entry: InventoryQuery.Entry) -> String:
	var t := entry.token
	var action := ""
	match t.action:
		RuleAction.Kind.FORWARD:
			action = "前へ進む力。ブロックに渡すと北へ1マス動く。"
		RuleAction.Kind.LEFT:
			action = "左へ進む力。ブロックに渡すと西へ1マス動く。"
		RuleAction.Kind.BACK:
			action = "後ろへ進む力。ブロックに渡すと南へ1マス動く。"
		RuleAction.Kind.RIGHT:
			action = "右へ進む力。ブロックに渡すと東へ1マス動く。"
		RuleAction.Kind.JUMP:
			action = "跳ぶ力。ブロックに渡すと、そのブロックが跳ねる。"
		RuleAction.Kind.THROW:
			action = (
				"投げて遠くへ渡す力（%s で切り替え）。手放すと「触る」の距離だけになるが、%s の回収は残る。"
				% [InputMode.key(&"toggle_reach"), InputMode.key(&"interact")]
			)
		RuleAction.Kind.HIGH_JUMP:
			action = "いつもより高く跳ぶ力（約2ブロック）。装備しているときだけ自分に効く。"
		RuleAction.Kind.DASH:
			var moves := PackedStringArray(
				[
					InputMode.key(&"move_forward"),
					InputMode.key(&"move_left"),
					InputMode.key(&"move_right"),
				]
			)
			action = (
				"%s を押しながら %s で、その向きへまっすぐ3マス突進する力（後ろへは無し）。途中の穴も抜ける。"
				% ["/".join(moves), InputMode.key(&"dash")]
			)
		RuleAction.Kind.CLIMB:
			action = "壁を登る力。装備しているときだけ自分に効く。ブロックに渡すと、隣でいちばん高い所の高さまで登ってつかまる。"
		RuleAction.Kind.HEAVY:
			action = "重くなる力。ホットバーにある間、風に流されず、水には沈み、重さの板を1人で押し下げる。ブロックや生き物に渡しても同じ。"
		RuleAction.Kind.FLOAT:
			action = "浮く力。ホットバーにある間、ゆっくり落ち（2個で2倍ゆっくり）、水に浮かぶ。ブロックに渡すと水に浮いて筏になる。重いと打ち消し合う。"
		RuleAction.Kind.SWIM:
			action = "泳ぐ力。ホットバーにある間、水に浮かんで進める（2個で2倍速く、流れに逆らえる）。持っていないと水に沈む。"
	if t.is_prohibition:
		var lent_note := "\n\nいまは貸し出し中なので、自分には効いていない。" if not t.is_in_vessel() else ""
		return (
			("「%s」を自分から始められなくする禁止。ホットバーでも、かばんでも、持っている限り自分に効く。" % RuleAction.label(t.action))
			+ lent_note
		)
	if entry.is_equipment:
		return action + "\n\n" + equipment_text(entry)
	match entry.state:
		InventoryQuery.State.ACTIVE:
			return action + "\n\nホットバーにあるので、自分に効いている。"
		InventoryQuery.State.STORED:
			return action + "\n\nかばんの中では自分に効かない。ホットバーに置くと効く。"
		InventoryQuery.State.LENT:
			return (
				action + "\n\n貸し出し中。回収するまで自分は使えない。相手に近づいて %s で回収できる。" % InputMode.key(&"interact")
			)
	return action


## 装備品のいまの状態（docs/adr/0018）: つけているときだけ効く。渡すと中の能力だけが移り、入れ物は残る。
static func equipment_text(entry: InventoryQuery.Entry) -> String:
	var interact := InputMode.key(&"interact")
	if not entry.token.is_in_vessel():
		var worn := entry.location == RuleVessel.Location.EQUIPPED
		var note := "つけていても、戻るまでは効かない。" if worn else ""
		return "中の能力を貸し出し中で、入れ物は空。%s相手に近づいて %s で回収すると、この入れ物に戻る。" % [note, interact]
	match entry.state:
		InventoryQuery.State.EQUIPPED:
			return "身につけているので、自分に効いている。つけたままでは渡せない（外してホットバーに置くと、中の能力だけを渡せる）。"
		_:
			if entry.location == RuleVessel.Location.HOTBAR:
				return "ホットバーでは効かない（つけると効く）。ここから渡すと、中の能力だけが移り、入れ物はこの枠に残る。"
			return "かばんの中では効かない。「そうびする」でつけると効く。ホットバーに置けば、中の能力だけを渡せる。"
