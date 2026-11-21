class_name CarryStack
extends Node3D
## 背負っている丸太・板の管理と、背中に積み上がる見た目。
## プレイヤーと伐採員の両方で使う。
## item は {"kind": "log" | "plank", "tree": 木のID} または {"kind": "fuel"} の辞書。

signal changed

const ITEM_HEIGHT := 0.22

var items: Array[Dictionary] = []
## 見た目の並べ方（運搬車の荷台などで横に並べる）
var columns := 1
var rows := 1
var item_spacing := Vector2(0.0, 0.0)  # (x方向, z方向)
## 1列に積む段数の上限。超えた分は overflow_step だけずらした隣の列に積む（背中の山が高くなりすぎないように）。
## 0 なら上限なし。見た目はいつも持っている数と同じだけ積む
var max_layers := 0
var overflow_step := Vector3(0, 0, -0.24)

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
	for i in items.size():
		add_child(_make_visual(items[i], i))
	changed.emit()


func _make_visual(item: Dictionary, index: int) -> Node3D:
	var per_layer := columns * rows
	var layer := floori(index / float(per_layer))
	var group := 0
	if max_layers > 0:
		group = floori(layer / float(max_layers))
		layer -= group * max_layers
	var cell := index % per_layer
	var col := cell % columns
	var row := floori(cell / float(columns))
	var pos := Vector3(
		(col - (columns - 1) * 0.5) * item_spacing.x,
		layer * ITEM_HEIGHT + ITEM_HEIGHT * 0.5,
		(row - (rows - 1) * 0.5) * item_spacing.y) + overflow_step * group
	if item["kind"] == "fuel":
		return Fx.box(Vector3(0.36, ITEM_HEIGHT * 0.9, 0.26), Color("#d83a2e"), pos)
	if item["kind"] == "plank":
		var plank := Sawmill._plank_mesh(item.get("tree", ""))
		plank.position = pos
		plank.scale = Vector3(0.75, 1.0, 1.0)
		return plank
	var log_mesh := LogDrop.make_log_mesh(item.get("tree", ""))
	log_mesh.position = pos
	return log_mesh
