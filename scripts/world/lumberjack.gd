class_name Lumberjack
extends Node3D
## 伐採員（NPC）。開放済みエリアの木を切り、製材所の投入口へ丸太を運ぶ。
## プレースホルダとして障害物は無視して直線移動する。

enum State { FIND_TREE, TO_TREE, CHOP, TO_SAWMILL, UNLOAD }

var sawmill: Sawmill
var stack: CarryStack
var state := State.FIND_TREE

var _target: ChoppableTree
var _chop_timer := 0.0
var _visual: Node3D


func _ready() -> void:
	add_to_group("carriers")
	_visual = Node3D.new()
	add_child(_visual)
	_visual.add_child(Fx.cylinder(0.28, 0.9, Color("#c0503a"), Vector3(0, 0.55, 0), 0.24))
	_visual.add_child(Fx.sphere(0.22, Color("#f2c9a0"), Vector3(0, 1.22, 0)))
	_visual.add_child(Fx.cylinder(0.26, 0.1, Color("#3a8a4a"), Vector3(0, 1.4, 0), 0.18))
	stack = CarryStack.new()
	stack.capacity_source = func() -> int: return int(GameData.lumberjack.get("capacity", 3))
	stack.position = Vector3(0, 0.65, -0.36)
	_visual.add_child(stack)


func _process(delta: float) -> void:
	match state:
		State.FIND_TREE:
			_target = _find_tree()
			if _target:
				_target.claimed_by = self
				state = State.TO_TREE
			elif not stack.is_empty():
				state = State.TO_SAWMILL
		State.TO_TREE:
			if not _target_valid():
				_release_target()
				state = State.FIND_TREE
			elif _move_to(_target.global_position, 0.7 + _target.radius, delta):
				state = State.CHOP
		State.CHOP:
			if not _target_valid():
				_release_target()
				state = State.TO_SAWMILL if stack.is_full() else State.FIND_TREE
				return
			_chop_timer -= delta
			if _chop_timer <= 0.0:
				_chop_timer = float(GameData.lumberjack.get("chop_interval", 0.6))
				if _target.hit(float(GameData.lumberjack.get("axe_power", 1.0))):
					stack.add({"kind": "log", "tree": _target.tree_id})
					_release_target()
					state = State.TO_SAWMILL if stack.is_full() else State.FIND_TREE
		State.TO_SAWMILL:
			if _move_to(sawmill.input_position(), 0.5, delta):
				state = State.UNLOAD
		State.UNLOAD:
			# 製材所が投入口にいる運搬者から丸太を受け取っていく
			if stack.count("log") == 0:
				state = State.FIND_TREE


func _target_valid() -> bool:
	return is_instance_valid(_target) and _target.alive and _target.claimed_by == self


func _release_target() -> void:
	if is_instance_valid(_target) and _target.claimed_by == self:
		_target.claimed_by = null
	_target = null


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
