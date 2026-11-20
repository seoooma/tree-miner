class_name Machine
extends CharacterBody3D
## プレイヤーが乗って運転する機械。
## - harvester（伐採機）: 近くの木を高速で切り倒す
## - hauler（運搬車）: 落ちている丸太を大量に拾い、製材所の投入口に横付けすると降ろす
## 燃料は「動作秒数」。走っている間・伐採している間だけ減り、乗っているだけでは減らない。
## 燃料が 0 になると動けない。燃料缶を持って近づくと補給される。
## 性能はランク（data/balance.json の machines）で決まり、購入パッドで上位ランクを買うとその場で強化される。

const FUEL_KIND := "fuel"

var kind := "harvester"
var rank := 1
var fuel := 0.0
var driver: Player = null
## 運搬車の荷台（伐採機は null）
var stack: CarryStack

var _visual: Node3D
var _fuel_label: Label3D
var _saw: Node3D
var _chop_timer := 0.0
var _refuel_timer := 0.0


func _ready() -> void:
	add_to_group("machines")
	collision_layer = 1
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 1.2, 2.4)
	shape.shape = box
	shape.position.y = 0.6
	add_child(shape)

	_visual = Node3D.new()
	add_child(_visual)
	_fuel_label = Fx.label3d("", Vector3(0, 2.8, 0), 40)
	add_child(_fuel_label)

	if kind == "hauler":
		add_to_group("carriers")
		add_to_group("plank_carriers")
		set_meta("pad_reach", 1.4)
		stack = CarryStack.new()
		stack.capacity_source = func() -> int: return int(spec().get("capacity", 20))
		stack.columns = 3
		stack.rows = 2
		stack.item_spacing = Vector2(0.36, 0.7)
		stack.max_visible = 60
		stack.position = Vector3(0, 0.75, -0.35)
		stack.rotation_degrees.y = 90.0
		add_child(stack)
	_build_visual()


func spec() -> Dictionary:
	return GameData.machine_rank(kind, rank)


func fuel_max() -> float:
	return float(spec().get("fuel_max", 60))


func display_name() -> String:
	return str(spec().get("name", GameData.machine_name(kind)))


## 上位ランクを購入したとき。燃料は満タンにする。
func set_rank(new_rank: int) -> void:
	rank = new_rank
	fuel = fuel_max()
	_build_visual()


func seat_position() -> Vector3:
	return global_position + global_transform.basis * Vector3(0, 1.3, 0.1)


func exit_position() -> Vector3:
	var p := global_position + global_transform.basis * Vector3(1.8, 0, 0)
	p.y = 0.0
	return p


func _build_visual() -> void:
	for child in _visual.get_children():
		child.queue_free()
	var color := Color(spec().get("color", "#e8b030"))
	# 履帯／タイヤ
	_visual.add_child(Fx.box(Vector3(0.35, 0.45, 2.3), Color("#2b2b2b"), Vector3(-0.7, 0.22, 0)))
	_visual.add_child(Fx.box(Vector3(0.35, 0.45, 2.3), Color("#2b2b2b"), Vector3(0.7, 0.22, 0)))
	_visual.add_child(Fx.box(Vector3(1.2, 0.35, 2.2), color.darkened(0.2), Vector3(0, 0.55, 0)))
	if kind == "harvester":
		_visual.add_child(Fx.box(Vector3(1.0, 0.8, 0.9), color, Vector3(0, 1.05, -0.4)))
		_visual.add_child(Fx.box(Vector3(0.9, 0.5, 0.7), Color("#9fd0e8"), Vector3(0, 1.5, -0.4)))
		_visual.add_child(Fx.box(Vector3(0.2, 0.2, 1.2), color.darkened(0.3), Vector3(0.3, 0.9, 1.0)))
		_saw = Node3D.new()
		_saw.position = Vector3(0.3, 0.7, 1.65)
		_visual.add_child(_saw)
		var blade := Fx.cylinder(0.45, 0.06, Color("#d0d4d8"))
		blade.rotation_degrees.z = 90.0
		_saw.add_child(blade)
	else:
		_visual.add_child(Fx.box(Vector3(1.2, 0.9, 0.7), color, Vector3(0, 1.1, 0.75)))
		_visual.add_child(Fx.box(Vector3(1.0, 0.4, 0.5), Color("#9fd0e8"), Vector3(0, 1.4, 0.85)))
		_visual.add_child(Fx.box(Vector3(1.3, 0.1, 1.5), color.darkened(0.35), Vector3(0, 0.75, -0.35)))
	# ランク表示の帯
	for i in rank:
		_visual.add_child(Fx.box(Vector3(0.12, 0.06, 0.3), Color.WHITE, Vector3(-0.5 + i * 0.2, 0.74, 1.05 if kind == "harvester" else 0.3)))


func _physics_process(delta: float) -> void:
	var working := false
	var input := driver.move_input() if driver else Vector2.ZERO
	var has_fuel := fuel > 0.0

	if driver and has_fuel and input.length() > 0.05:
		var dir := Vector3(input.x, 0.0, input.y)
		velocity = dir * float(spec().get("speed", 6.0))
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), minf(1.0, delta * 6.0))
		working = true
	else:
		velocity = Vector3.ZERO
	move_and_slide()
	position.y = 0.0

	if driver and has_fuel:
		if kind == "harvester":
			working = _update_harvest(delta) or working
		elif kind == "hauler":
			LogDrop.collect_near(self, stack, float(spec().get("pickup_radius", 2.5)))

	if working:
		fuel = maxf(0.0, fuel - delta)
	if _saw:
		_saw.rotation_degrees.x += delta * (900.0 if driver and has_fuel else 0.0)

	_refuel_from_player(delta)
	_update_label()
	_save_state()


## 伐採機: 範囲内の木を切る。切っていれば true。
func _update_harvest(delta: float) -> bool:
	var tree := _find_tree()
	if tree == null:
		return false
	_chop_timer -= delta
	if _chop_timer <= 0.0:
		_chop_timer = float(spec().get("chop_interval", 0.35))
		tree.hit(float(spec().get("chop_power", 3)))
	return true


func _find_tree() -> ChoppableTree:
	var best: ChoppableTree = null
	var best_dist := INF
	var reach := float(spec().get("chop_range", 2.0))
	for node in get_tree().get_nodes_in_group("trees"):
		var tree := node as ChoppableTree
		if not tree.alive or not GameState.is_area_unlocked(tree.area_index):
			continue
		var d := Fx.xz_distance(global_position, tree.global_position) - tree.radius
		if d <= reach and d < best_dist:
			best = tree
			best_dist = d
	return best


## 燃料缶を持ったプレイヤー（徒歩）が近くにいれば補給する。
func _refuel_from_player(delta: float) -> void:
	_refuel_timer -= delta
	if _refuel_timer > 0.0:
		return
	var per_can := float(GameData.fuel.get("per_can", 20))
	for node in get_tree().get_nodes_in_group("player"):
		var p := node as Player
		if p.vehicle != null or p.stack.count(FUEL_KIND) == 0:
			continue
		if Fx.xz_distance(p.global_position, global_position) > float(GameData.player.get("board_range", 3.0)):
			continue
		if fuel >= fuel_max() - 0.01:
			continue
		p.stack.take(FUEL_KIND)
		fuel = minf(fuel_max(), fuel + per_can)
		_refuel_timer = 0.2
		Fx.popup(self, global_position, "燃料 +%d" % roundi(per_can), Color("#ff9a7a"))


func _update_label() -> void:
	var text := "%s\n燃料 %d/%d" % [display_name(), ceili(fuel), roundi(fuel_max())]
	if fuel <= 0.0:
		text += "\n燃料切れ"
	if stack:
		text += "\n積荷 %d/%d" % [stack.size(), stack.capacity()]
	_fuel_label.text = text
	_fuel_label.modulate = Color("#ff8a7a") if fuel <= 0.0 else Color.WHITE


func _save_state() -> void:
	GameState.machine_state[kind] = {
		"fuel": fuel,
		"x": global_position.x,
		"z": global_position.z,
		"ry": rotation.y,
	}
