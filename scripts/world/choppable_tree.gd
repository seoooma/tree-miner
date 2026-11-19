class_name ChoppableTree
extends StaticBody3D
## 切れる木。硬さ(hardness)ぶんダメージを受けると倒れ、一定時間で再生する。

signal felled(tree: ChoppableTree)

var tree_id := ""
var area_index := 0
var max_hp := 1.0
var hp := 1.0
var alive := true
var radius := 0.35
## 伐採員が同じ木に群がらないための予約
var claimed_by: Node = null

var _respawn_sec := 8.0
var _visual: Node3D
var _shape: CollisionShape3D
var _hp_label: Label3D


func setup(def: Dictionary, p_area_index: int) -> void:
	tree_id = str(def["id"])
	area_index = p_area_index
	max_hp = float(def.get("hardness", 1))
	hp = max_hp
	_respawn_sec = float(def.get("respawn_sec", 8.0))
	var s := float(def.get("scale", 1.0))
	radius = 0.3 * s
	collision_layer = 1
	collision_mask = 0
	add_to_group("trees")

	var trunk_color := Color(def.get("trunk_color", "#8a5a33"))
	var leaf_color := Color(def.get("leaf_color", "#4f9f4f"))

	# 切り株（倒れても残る）
	add_child(Fx.cylinder(radius * 1.1, 0.25, trunk_color.darkened(0.2), Vector3(0, 0.125, 0)))

	_visual = Node3D.new()
	add_child(_visual)
	var trunk_h := 1.3 * s
	_visual.add_child(Fx.cylinder(radius, trunk_h, trunk_color, Vector3(0, trunk_h * 0.5, 0), radius * 0.75))
	if def.get("shape", "sphere") == "cone":
		var cone_h := 2.0 * s
		_visual.add_child(Fx.cylinder(0.95 * s, cone_h, leaf_color, Vector3(0, trunk_h + cone_h * 0.4, 0), 0.0))
	else:
		_visual.add_child(Fx.sphere(0.95 * s, leaf_color, Vector3(0, trunk_h + 0.6 * s, 0)))

	_shape = CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 2.0
	_shape.shape = cyl
	_shape.position.y = 1.0
	add_child(_shape)

	_hp_label = Fx.label3d("", Vector3(0, trunk_h + 2.2 * s, 0), 40)
	_hp_label.visible = false
	add_child(_hp_label)


## ダメージを与える。倒れたら true。
func hit(damage: float) -> bool:
	if not alive:
		return false
	hp -= damage
	_shake()
	if hp <= 0.0:
		_fell()
		return true
	_hp_label.text = "%d / %d" % [ceili(hp), roundi(max_hp)]
	_hp_label.visible = true
	return false


func _shake() -> void:
	var tween := create_tween()
	tween.tween_property(_visual, "rotation_degrees:z", 6.0, 0.05)
	tween.tween_property(_visual, "rotation_degrees:z", -4.0, 0.07)
	tween.tween_property(_visual, "rotation_degrees:z", 0.0, 0.06)


func _fell() -> void:
	alive = false
	claimed_by = null
	_visual.visible = false
	_hp_label.visible = false
	_shape.set_deferred("disabled", true)
	felled.emit(self)
	get_tree().create_timer(_respawn_sec).timeout.connect(_respawn)


func _respawn() -> void:
	hp = max_hp
	alive = true
	_visual.visible = true
	_visual.scale = Vector3.ONE * 0.2
	_shape.set_deferred("disabled", false)
	create_tween().tween_property(_visual, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
