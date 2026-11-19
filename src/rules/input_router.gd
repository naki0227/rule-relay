class_name InputRouter
extends RefCounted
## 行動キー（W/A/S/D/Space）を押したときの宛先を決める。UI・物理から分離した純粋な判定。
## - 自分がその能力を使えるなら、自分が行動する
## - その行動の単発トークンを貸し出していれば、付与先が1回だけ行動を試みる
## 能力トークンは一意なので、同じトークンで自分と付与先が二重に発動することはない。
## 同じ行動の単発が複数出ている場合はすべて起動する（未決事項に対する仮の方針）。


class Route:
	extends RefCounted
	var player_acts: bool = false
	var single_shot_token_ids: PackedInt32Array = PackedInt32Array()


static func route_press(ledger: RuleLedger, action: RuleAction.Kind) -> Route:
	var route := Route.new()
	route.player_acts = ledger.player_can(action)
	for t in ledger.pending_single_shots(action):
		route.single_shot_token_ids.append(t.id)
	return route
