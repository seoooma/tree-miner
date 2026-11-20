class_name Player
extends CharacterBody3D
## プレイヤー。移動・木の自動伐採・丸太の拾得・運搬・機械の乗り降り。
## 近くの木を自動で切り（積荷が満杯でも切れる）、落ちた丸太は近くを歩くと拾う。
## 売却ポイント等の上に立つと積荷が自動で受け渡される。

signal carry_changed(count: int, capacity: int)

## HUD のバーチャルスティックから入力される（-1..1）
var joystick_vector := Vector2.ZERO
var stack: CarryStack
## 乗っている機械（null なら徒歩）
var vehicle: Machine = null

var _chop_timer := 0.0
var _visual: Node3D
var _rig: CharacterRig


func _ready() -> void:
	add_to_group("player")
	add_to_group("carriers")
	add_to_group("plank_carriers")
	collision_layer = 2
	collision_mask = 1

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.6
	shape.shape = capsule
	shape.position.y = 0.8
	add_child(shape)

	_visual = Node3D.new()
	add_child(_visual)
	_build_body()

	stack = CarryStack.new()
	stack.capacity_source = func() -> int: return roundi(GameState.value("capacity"))
	stack.position = Vector3(0, 0.55, -0.4)
	_visual.add_child(stack)
	stack.changed.connect(_emit_carry)
	GameState.upgrade_changed.connect(func(_id: String, _level: int) -> void: _emit_carry())
	_emit_carry.call_deferred()


func _build_body() -> void:
	_rig = CharacterRig.new(1.15)
	_rig.set_hat(Color("#f2b632"))
	_visual.add_child(_rig)


## スティック＋キーボードの移動入力（-1..1）。乗車中は機械がこれを読む。
func move_input() -> Vector2:
	var input := _keyboard_vector() + joystick_vector
	return input.normalized() if input.length() > 1.0 else input


func _physics_process(delta: float) -> void:
	if vehicle:
		global_position = vehicle.seat_position()
		_visual.rotation.y = vehicle.rotation.y
		_rig.set_moving(false)
		Audio.set_loop("walk", false)
		var driving := vehicle.velocity.length() > 0.1
		Audio.set_loop("engine", vehicle.fuel > 0.0, -6.0 if driving else -13.0, 1.15 if driving else 0.8)
		return
	Audio.set_loop("engine", false)
	var input := move_input()
	var dir := Vector3(input.x, 0.0, input.y)
	velocity = dir * GameState.value("move_speed")
	move_and_slide()
	position.y = 0.0
	var moving := dir.length() > 0.05 and get_real_velocity().length() > 0.3
	if dir.length() > 0.05:
		_visual.rotation.y = lerp_angle(_visual.rotation.y, atan2(dir.x, dir.z), minf(1.0, delta * 12.0))
	_rig.set_moving(moving, GameState.value("move_speed") / 5.0)
	Audio.set_loop("walk", moving, -12.0, GameState.value("move_speed") / 5.0)
	_update_chop(delta)
	LogDrop.collect_near(self, stack, float(GameData.player.get("pickup_radius", 1.8)))


func _keyboard_vector() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		v.y += 1.0
	return v.normalized()


# ---- 伐採 ----

func _update_chop(delta: float) -> void:
	_chop_timer = maxf(0.0, _chop_timer - delta)
	if _chop_timer > 0.0:
		return
	var tree := _find_tree()
	if tree == null:
		return
	_chop_timer = float(GameData.player.get("chop_interval", 0.45))
	_swing()
	tree.hit(GameState.value("axe_power"), global_position)


func _find_tree() -> ChoppableTree:
	var best: ChoppableTree = null
	var best_dist := INF
	var reach := float(GameData.player.get("chop_range", 1.3))
	for node in get_tree().get_nodes_in_group("trees"):
		var tree := node as ChoppableTree
		if not tree.alive or not GameState.is_area_unlocked(tree.area_index):
			continue
		var d := Fx.xz_distance(global_position, tree.global_position)
		if d <= reach + tree.radius and d < best_dist:
			best = tree
			best_dist = d
	return best


func _swing() -> void:
	_rig.swing()


# ---- 機械 ----

## 近くにある乗れる機械（無ければ null）
func nearby_machine() -> Machine:
	if vehicle:
		return null
	var best: Machine = null
	var best_dist := float(GameData.player.get("board_range", 3.0))
	for node in get_tree().get_nodes_in_group("machines"):
		var m := node as Machine
		var d := Fx.xz_distance(global_position, m.global_position)
		if d <= best_dist:
			best = m
			best_dist = d
	return best


func board(machine: Machine) -> void:
	if vehicle or machine == null or machine.driver != null:
		return
	vehicle = machine
	machine.driver = self
	_visual.visible = false
	Audio.play("board", -6.0)
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	remove_from_group("carriers")
	remove_from_group("plank_carriers")


func exit_vehicle() -> void:
	if vehicle == null:
		return
	var machine := vehicle
	vehicle = null
	machine.driver = null
	_visual.visible = true
	Audio.play("board", -8.0, 1.2)
	global_position = machine.exit_position()
	collision_layer = 2
	collision_mask = 1
	add_to_group("carriers")
	add_to_group("plank_carriers")


# ---- 運搬（売却ポイント等から呼ばれる）----

func capacity() -> int:
	return stack.capacity()


func _emit_carry() -> void:
	carry_changed.emit(stack.size(), stack.capacity())
