class_name CarryStack
extends Node3D
## 背負っている丸太・板の管理と、背中に積み上がる見た目。
## プレイヤーと伐採員の両方で使う。
## item は {"kind": "log" | "plank", "tree": 木のID} の辞書。

signal changed

const ITEM_HEIGHT := 0.2
## 見た目に積む最大数（それ以上は数だけ増える）
const MAX_VISIBLE := 25

var items: Array[Dictionary] = []
## 容量を返す関数（強化で変わるため Callable で受け取る）
var capacity_source: Callable = func() -> int: return 5


func capacity() -> int:
	return int(capacity_source.call())


func size() -> int:
	return items.size()


func is_full() -> bool:
	return items.size() >= capacity()


func is_empty() -> bool:
	return items.is_empty()


func count(kind: String) -> int:
	var n := 0
	for item in items:
		if item["kind"] == kind:
			n += 1
	return n


func add(item: Dictionary) -> bool:
	if is_full():
		return false
	items.append(item)
	_rebuild()
	return true


## 指定した種類のアイテムを上から1つ取り出す。無ければ空の辞書。
func take(kind: String) -> Dictionary:
	for i in range(items.size() - 1, -1, -1):
		if items[i]["kind"] == kind:
			var item := items[i]
			items.remove_at(i)
			_rebuild()
			return item
	return {}


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	for i in mini(items.size(), MAX_VISIBLE):
		add_child(_make_visual(items[i], i))
	changed.emit()


func _make_visual(item: Dictionary, index: int) -> MeshInstance3D:
	var def := GameData.tree_def(item["tree"])
	var y := index * ITEM_HEIGHT + ITEM_HEIGHT * 0.5
	if item["kind"] == "plank":
		var plank_color := Color(def.get("trunk_color", "#a77a4f")).lightened(0.45)
		return Fx.box(Vector3(0.62, ITEM_HEIGHT * 0.8, 0.3), plank_color, Vector3(0, y, 0))
	var log_mesh := Fx.cylinder(0.09, 0.6, Color(def.get("trunk_color", "#8a5a33")), Vector3(0, y, 0))
	log_mesh.rotation_degrees.z = 90.0
	return log_mesh
