class_name LogDrop
extends Node3D
## 木を倒したときに地面に落ちる丸太。運搬者（プレイヤー・運搬役の伐採員・運搬車）が近づくと吸い寄せられて拾われる。

const SPAWN_SEC := 0.35

var tree_id := ""
var collected := false
## 運搬役の伐採員が同じ丸太を取り合わないための予約
var claimed_by: Node = null

var _age := 0.0


## 倒れた木の周りに丸太をばらまく。
static func spawn_from_tree(tree: Node3D, p_tree_id: String) -> void:
	var parent := tree.get_parent()
	if parent == null:
		return
	var max_on_map := int(GameData.drops.get("max_on_map", 300))
	var count := randi_range(int(GameData.drops.get("min", 2)), int(GameData.drops.get("max", 4)))
	count = mini(count, max_on_map - tree.get_tree().get_nodes_in_group("drops").size())
	var scatter := float(GameData.drops.get("scatter", 1.6))
	for i in count:
		var drop := LogDrop.new()
		drop.tree_id = p_tree_id
		parent.add_child(drop)
		drop.global_position = tree.global_position + Vector3(0, 1.0, 0)
		var angle := randf() * TAU
		var dist := randf_range(0.6, scatter)
		drop._land(tree.global_position + Vector3(cos(angle) * dist, 0.1, sin(angle) * dist))


## 運搬者の近くにある丸太を、空きがある分だけ拾う。拾った数を返す。
static func collect_near(carrier: Node3D, stack: CarryStack, radius: float) -> int:
	var picked := 0
	for node in carrier.get_tree().get_nodes_in_group("drops"):
		if stack.is_full():
			break
		var drop := node as LogDrop
		if drop.collected or drop._age < SPAWN_SEC:
			continue
		if Fx.xz_distance(drop.global_position, carrier.global_position) > radius:
			continue
		stack.add({"kind": "log", "tree": drop.tree_id})
		drop._fly_to(carrier)
		picked += 1
	return picked


func _ready() -> void:
	add_to_group("drops")
	var def := GameData.tree_def(tree_id)
	var mesh := Fx.cylinder(0.11, 0.7, Color(def.get("trunk_color", "#8a5a33")))
	mesh.rotation_degrees = Vector3(0, randf() * 180.0, 90)
	add_child(mesh)


func _process(delta: float) -> void:
	_age += delta


func _land(target: Vector3) -> void:
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "global_position:x", target.x, SPAWN_SEC)
	tween.tween_property(self, "global_position:z", target.z, SPAWN_SEC)
	var up := create_tween()
	up.tween_property(self, "global_position:y", 1.6, SPAWN_SEC * 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	up.tween_property(self, "global_position:y", target.y, SPAWN_SEC * 0.6).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


func _fly_to(carrier: Node3D) -> void:
	collected = true
	remove_from_group("drops")
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "global_position", carrier.global_position + Vector3(0, 1.0, 0), 0.15)
	tween.tween_property(self, "scale", Vector3.ONE * 0.4, 0.15)
	tween.chain().tween_callback(queue_free)
