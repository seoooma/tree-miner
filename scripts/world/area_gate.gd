class_name AreaGate
extends Station
## エリアの境界にある柵。手前の支払いパッドに立つと少しずつ支払い、払い終わると柵が消えて次のエリアが開く。

const PAD_OFFSET := Vector3(0, 0, 2.6)
const PAD_RADIUS := 1.4
## 何回の支払いで満額になるか（小さいほど速く払える）
const PAY_STEPS := 60.0

var area_index := 1
var width := 40.0

var _pad_root: Node3D
var _label: Label3D


func _ready() -> void:
	var fence := StaticBody3D.new()
	fence.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, 2.0, 0.4)
	shape.shape = box
	shape.position.y = 1.0
	fence.add_child(shape)
	add_child(fence)
	fence.add_child(Fx.box(Vector3(width, 0.15, 0.12), Color("#d9b27c"), Vector3(0, 0.55, 0)))
	fence.add_child(Fx.box(Vector3(width, 0.15, 0.12), Color("#d9b27c"), Vector3(0, 1.05, 0)))
	var x := -width * 0.5
	while x <= width * 0.5 + 0.01:
		fence.add_child(Fx.box(Vector3(0.18, 1.3, 0.18), Color("#9c7348"), Vector3(x, 0.65, 0)))
		x += 2.0

	_pad_root = Node3D.new()
	_pad_root.position = PAD_OFFSET
	add_child(_pad_root)
	_pad_root.add_child(Fx.pad(PAD_RADIUS, Color("#f0a84b")))
	_label = Fx.label3d("", Vector3(0, 1.6, 0), 48)
	_pad_root.add_child(_label)

	GameState.area_unlocked.connect(func(_i: int) -> void: _refresh())
	_refresh()


func _is_next() -> bool:
	return area_index == GameState.unlocked_area_count


func _refresh() -> void:
	if GameState.is_area_unlocked(area_index):
		queue_free()
		return
	_pad_root.visible = _is_next()
	_update_label()


func _update_label() -> void:
	var area_name := str(GameData.areas[area_index].get("name", ""))
	_label.text = "%s を開放\n¥%d" % [area_name, GameState.gate_remaining(area_index)]


func _process(delta: float) -> void:
	if not _is_next():
		return
	var cost := float(GameData.areas[area_index].get("unlock_cost", 0))
	var chunk := maxi(1, ceili(cost / PAY_STEPS))
	for carrier in carriers_near(global_position + PAD_OFFSET, PAD_RADIUS, true):
		if GameState.money > 0 and tick(carrier, "pay", delta, 0.03):
			GameState.pay_toward_area(area_index, chunk)
			if is_queued_for_deletion():
				return
			_update_label()
