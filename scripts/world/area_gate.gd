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
var _zone: Zone


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
	fence.add_child(Fx.box(Vector3(width, 0.12, 0.08), Color("#b8946a"), Vector3(0, 0.5, 0), "wood"))
	fence.add_child(Fx.box(Vector3(width, 0.12, 0.08), Color("#b8946a"), Vector3(0, 0.95, 0), "wood"))
	var x := -width * 0.5
	while x <= width * 0.5 + 0.01:
		fence.add_child(Fx.cylinder(0.09, 1.25, Color("#8a6a4a"), Vector3(x, 0.62, 0), 0.07, 6, true, "wood"))
		x += 1.6
	# 鎖と南京錠（開放待ちの目印）
	fence.add_child(Fx.box(Vector3(0.3, 0.36, 0.14), Color("#e0b030"), Vector3(0, 0.72, 0.1)))
	fence.add_child(Fx.cylinder(0.1, 0.06, Color("#8c939a"), Vector3(0, 0.95, 0.1), -1.0, 10))

	_pad_root = Node3D.new()
	_pad_root.position = PAD_OFFSET
	add_child(_pad_root)
	_zone = Zone.new(Vector2(PAD_RADIUS * 2.4, PAD_RADIUS * 2.0), Color(0.95, 0.65, 0.3, 0.18))
	_pad_root.add_child(_zone)

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
	_zone.set_text("%s を開放" % area_name, "¥%d" % GameState.gate_remaining(area_index))


func _process(delta: float) -> void:
	if not _is_next():
		return
	var cost := float(GameData.areas[area_index].get("unlock_cost", 0))
	var chunk := maxi(1, ceili(cost / PAY_STEPS))
	for carrier in carriers_near(global_position + PAD_OFFSET, PAD_RADIUS, "player"):
		if GameState.money > 0 and tick(carrier, "pay", delta, 0.03):
			GameState.pay_toward_area(area_index, chunk)
			if is_queued_for_deletion():
				Audio.play("unlock", 0.0)
				Fx.burst(get_parent(), global_position + Vector3(0, 1.0, 0), [Color("#ffd84a"), Color("#ff6b6b"), Color("#6bc4ff"), Color("#8fe07a")], 48, 7.0, 0.12, 1.4)
				return
			_update_label()
