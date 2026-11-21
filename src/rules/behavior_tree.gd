class_name BehaviorTree
extends RefCounted
## 小さなビヘイビアツリー（生き物のふるまい。CreatureBrain が組み立てる。ADR 0019）。
## 節は「成功したか」だけを返す。選ぶ節（Selector）は子を順に試して最初に成功したところで止まり、
## 続ける節（Sequence）は子を順に試して1つでも失敗したら止まる。葉（Leaf）は呼び出し側の関数を呼ぶ。
## 状態は持たず、毎回の判断で同じ入力なら同じ葉を通る（乱数は呼び出し側が種付きで持つ）。


## 節。
class BTNode:
	extends RefCounted
	var name: String = ""

	func tick(_context: Object) -> bool:
		return false


## 子を順に試し、最初に成功した子で止まる（どれも失敗なら失敗）。
class Selector:
	extends BTNode
	var children: Array[BTNode] = []

	func _init(p_name: String, p_children: Array[BTNode]) -> void:
		name = p_name
		children = p_children

	func tick(context: Object) -> bool:
		for child in children:
			if child.tick(context):
				return true
		return false


## 子を順に試し、1つでも失敗したら止まる（全部成功なら成功）。
class Sequence:
	extends BTNode
	var children: Array[BTNode] = []

	func _init(p_name: String, p_children: Array[BTNode]) -> void:
		name = p_name
		children = p_children

	func tick(context: Object) -> bool:
		for child in children:
			if not child.tick(context):
				return false
		return true


## 葉: fn(context) -> bool を呼ぶ（条件も行動も葉で書く）。
class Leaf:
	extends BTNode
	var fn: Callable

	func _init(p_name: String, p_fn: Callable) -> void:
		name = p_name
		fn = p_fn

	func tick(context: Object) -> bool:
		return bool(fn.call(context))


static func selector(p_name: String, children: Array[BTNode]) -> Selector:
	return Selector.new(p_name, children)


static func sequence(p_name: String, children: Array[BTNode]) -> Sequence:
	return Sequence.new(p_name, children)


static func leaf(p_name: String, fn: Callable) -> Leaf:
	return Leaf.new(p_name, fn)
