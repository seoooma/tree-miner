class_name Lumberjack
extends Node3D
## 伐採員（NPC）。役割は2つで、強化パネルから切り替えられる。
## - chop（伐採）: 開放済みエリアの木を切り倒し、丸太を地面に落とす
## - haul（運搬）: 地面の丸太を拾い、製材所の投入口へ運ぶ
## プレースホルダとして障害物は無視して直線移動する。

enum State { IDLE, TO_TREE, CHOP, TO_DROP, TO_SAWMILL, UNLOAD }

var index := 0
var role := "chop"
var sawmill: Sawmill
var stack: CarryStack
var state := State.IDLE

var _target_tree: ChoppableTree
var _target_drop: LogDrop
var _chop_timer := 0.0
var _visual: Node3D
var _hat: MeshInstance3D
var _role_label: Label3D


func _ready() -> void:
	add_to_group("carriers")
	_visual = Node3D.new()
	add_child(_visual)
	_visual.add_child(Fx.cylinder(0.28, 0.9, Color("#c0503a"), Vector3(0, 0.55, 0), 0.24))
	_visual.add_child(Fx.sphere(0.22, Color("#f2c9a0"), Vector3(0, 1.22, 0)))
	stack = CarryStack.new()
	stack.capacity_source = func() -> int: return int(GameData.lumberjack.get("capacity", 4))
	stack.position = Vector3(0, 0.65, -0.36)
	_visual.add_child(stack)
	_role_label = Fx.label3d("", Vector3(0, 2.0, 0), 32)
	add_child(_role_label)
	set_role(role)


func set_role(new_role: String) -> void:
	_release_targets()
	role = new_role
	state = State.IDLE
	if _hat:
		_hat.queue_free()
	# 帽子の色で役割を見分ける（緑 = 伐採、青 = 運搬）
	var hat_color := Color("#3a8a4a") if role == "chop" else Color("#3a6fd0")
	_hat = Fx.cylinder(0.26, 0.1, hat_color, Vector3(0, 1.4, 0), 0.18)
	_visual.add_child(_hat)
	_role_label.text = "伐採" if role == "chop" else "運搬"


func _process(delta: float) -> void:
	if role == "chop":
		_process_chop(delta)
	else:
		_process_haul(delta)


# ---- 伐採役 ----

func _process_chop(delta: float) -> void:
	# 運搬役から切り替わった直後で丸太を持っていれば、先に製材所へ届ける
	if not stack.is_empty():
		if _move_to(sawmill.input_position(), 0.5, delta):
			state = State.UNLOAD
		return
	if state == State.UNLOAD or state == State.TO_SAWMILL or state == State.TO_DROP:
		state = State.IDLE
	match state:
		State.IDLE:
			_target_tree = _find_tree()
			if _target_tree:
				_target_tree.claimed_by = self
				state = State.TO_TREE
		State.TO_TREE:
			if not _tree_valid():
				_release_targets()
				state = State.IDLE
			elif _move_to(_target_tree.global_position, 0.7 + _target_tree.radius, delta):
				state = State.CHOP
		State.CHOP:
			if not _tree_valid():
				_release_targets()
				state = State.IDLE
				return
			_chop_timer -= delta
			if _chop_timer <= 0.0:
				_chop_timer = float(GameData.lumberjack.get("chop_interval", 0.6))
				if _target_tree.hit(float(GameData.lumberjack.get("axe_power", 1.0))):
					_release_targets()
					state = State.IDLE


func _tree_valid() -> bool:
	return is_instance_valid(_target_tree) and _target_tree.alive and _target_tree.claimed_by == self


func _find_tree() -> ChoppableTree:
	var best: ChoppableTree = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("trees"):
		var tree := node as ChoppableTree
		if not tree.alive or tree.claimed_by != null or not GameState.is_area_unlocked(tree.area_index):
			continue
		var d := Fx.xz_distance(global_position, tree.global_position)
		if d < best_dist:
			best = tree
			best_dist = d
	return best


# ---- 運搬役 ----

func _process_haul(delta: float) -> void:
	LogDrop.collect_near(self, stack, float(GameData.lumberjack.get("pickup_radius", 1.5)))
	match state:
		State.IDLE, State.TO_TREE, State.CHOP:
			if stack.is_full():
				state = State.TO_SAWMILL
				return
			_target_drop = _find_drop()
			if _target_drop:
				_target_drop.claimed_by = self
				state = State.TO_DROP
			elif not stack.is_empty():
				state = State.TO_SAWMILL
		State.TO_DROP:
			if stack.is_full():
				_release_targets()
				state = State.TO_SAWMILL
			elif not _drop_valid():
				_release_targets()
				state = State.IDLE
			else:
				_move_to(_target_drop.global_position, 0.3, delta)
		State.TO_SAWMILL:
			if _move_to(sawmill.input_position(), 0.5, delta):
				state = State.UNLOAD
		State.UNLOAD:
			# 製材所が投入口にいる運搬者から丸太を受け取っていく
			if stack.count("log") == 0:
				state = State.IDLE


func _drop_valid() -> bool:
	return is_instance_valid(_target_drop) and not _target_drop.collected and _target_drop.claimed_by == self


func _find_drop() -> LogDrop:
	var best: LogDrop = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("drops"):
		var drop := node as LogDrop
		if drop.collected or (drop.claimed_by != null and is_instance_valid(drop.claimed_by)):
			continue
		var d := Fx.xz_distance(global_position, drop.global_position)
		if d < best_dist:
			best = drop
			best_dist = d
	return best


# ---- 共通 ----

func _release_targets() -> void:
	if is_instance_valid(_target_tree) and _target_tree.claimed_by == self:
		_target_tree.claimed_by = null
	if is_instance_valid(_target_drop) and _target_drop.claimed_by == self:
		_target_drop.claimed_by = null
	_target_tree = null
	_target_drop = null


## 目的地へ向かう。到着していれば true。
func _move_to(target: Vector3, arrive_dist: float, delta: float) -> bool:
	var to := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	var dist := to.length()
	if dist <= arrive_dist:
		return true
	var step := minf(dist, float(GameData.lumberjack.get("move_speed", 3.2)) * delta)
	global_position += to / dist * step
	_visual.rotation.y = lerp_angle(_visual.rotation.y, atan2(to.x, to.z), minf(1.0, delta * 10.0))
	return false
