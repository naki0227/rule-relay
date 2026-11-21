class_name NatureBuilder
extends RefCounted
## StageDef.nature（風・水）と地形の氷を、世界の NatureField と見た目に組み立てる（docs/adr/0015）。
## どの画面（ホスト・参加者・ひとり）も同じ定義から同じ物を作るので、置き方は通信で送らない。


## build_terrain の後に呼ぶ（氷の見た目は地形のセルを見る）。
static func build(w: GameWorld, layout: NatureLayout) -> void:
	w.nature.layout = layout
	w.nature.terrain = w.terrain
	for spec in layout.winds:
		var wind := WindVisual.new()
		wind.setup(spec, w.nature)
		w.add_child(wind)
	for spec in layout.waters:
		var water := WaterVisual.new()
		water.setup(spec)
		w.add_child(water)
	if w.terrain != null and w.terrain.cells.values().has("ice"):
		var frost := IceFrost.new()
		frost.terrain = w.terrain
		w.add_child(frost)
