class_name OptionalWorldPlan
extends RefCounted
## 寄り道のワールド（O1〜O3）の計画データ（純粋なデータ。CampaignPlan._optional が読む）。
## 本人の方針（2026-11-21）: 「クリアしなくても次のところへ行けるようなオプションのワールドに関しては
## ほんとに複雑に組み合わせて難しくしてほしい」。どのステージも難しい（★）。ステージの中身は OptionalWorlds*。
##
## 開き方（docs/campaign-plan.md「寄り道のワールドの開き方」）: opened_by のステージをクリアし、さらに広場の
## 秘密の入口（庭・小島）に誰かが入ると、その発見が進行に保存され（PlayerProgress.found_secrets）、
## 寄り道の 1 つ目のポータルが開く。あとは本編と同じく、前のステージをクリアすると次が開く。
## ポータルは入口の庭（小島）の中に並べる（本編のポータルより間隔が狭い。4 m 以上）。

const IDS: PackedStringArray = ["o1", "o2", "o3"]


static func title(id: String) -> String:
	match id:
		"o1":
			return "からくり工房"
		"o2":
			return "さかさ雲"
	return "ひみつの温室"


static func opened_by(id: String) -> String:
	match id:
		"o1":
			return StageCatalog.WINDY_ID
		"o2":
			return "w3_cloud_corridor"
	return StageCatalog.FORT_ID


## 寄り道のワールドの入口（秘密の場所の真ん中。1 つ目のポータルの位置）。
static func teaser(id: String) -> Vector3:
	return slots(id)[0][2] as Vector3


static func secret(id: String) -> String:
	match id:
		"o1":
			return "はじまりの草原の北東、鐘で開く扉の奥の庭（鐘を鳴らす・扉のブロックに W を渡す）"
		"o2":
			return "浮島の東の端から、幅 5 の空を越えた小島（跳んでから空中ダッシュ・ブーツ）"
	return "はじまりの草原の南西、札の門の奥の庭（門の札を回収して手放してから A を渡す）"


## [題, 新しい仕掛け・組み合わせ, ポータルの位置, 住む生き物] の並び（ステージの順）。
static func slots(id: String) -> Array:
	match id:
		"o1":
			return [
				["歯車の渡し", "ワープ×遠くの単発×重さの板×せり上がる橋", Vector3(19.5, 0.0, -12.5), "wish"],
				["時計じかけの回廊", "時の鐘×信号の数×扉×レバー", Vector3(17.5, 0.0, -16.5), "kit"],
				["重さくらべの秤", "重さの板×重い×発射台×ワープの連なり", Vector3(21.5, 0.0, -16.5), "lamb"],
				["札の歯車", "札×切り替えの扉×生き物の重さ", Vector3(17.5, 0.0, -20.5), "bunny"],
				["大からくり", "からくりの全部（板・扉・時の鐘・ワープ・発射台・生き物）", Vector3(21.5, 0.0, -20.5), "wish"],
			]
		"o2":
			return [
				["風見の段々", "風×浮く×持ち上げ台", Vector3(62.5, 0.0, -48.5), "bunny"],
				["雲の筏", "浮くブロック×風で運ぶ×重い×重さの板", Vector3(66.5, 0.0, -45.5), "lamb"],
				["落ちる島々", "浮くの滑空×高さ×脈打つ風×時の鐘", Vector3(66.5, 0.0, -51.5), "kit"],
				["さかさまの塔", "せり上がる扉×風×浮く×ダッシュ", Vector3(62.5, 0.0, -43.5), "wish"],
				["空の大渦", "さかさ雲の全部（風・浮く・重い・高さ・ワープ）", Vector3(62.5, 0.0, -53.5), "wish"],
			]
	return [
		["氷の温室", "氷×すべるブロック×重さの板×札", Vector3(-14.5, 0.0, 18.5), "bunny"],
		["水路の花壇", "水と流れ×浮く筏×泳ぐ×札", Vector3(-19.5, 0.0, 17.5), "lamb"],
		["札の苗床", "札の受け渡し×生き物の願い×扉", Vector3(-23.5, 0.0, 20.5), "kit"],
		["凍った池", "氷×水×重い×札", Vector3(-19.5, 0.0, 22.5), "bunny"],
		["大温室", "温室の全部（札・生き物・水・氷）", Vector3(-14.5, 0.0, 22.5), "wish"],
	]
