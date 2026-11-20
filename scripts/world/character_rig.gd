class_name CharacterRig
extends Node3D
## キャラクターの見た目（Kenney のキャラクターモデル＋斧＋帽子）と、歩き／待機アニメの切り替え。
## プレイヤーと伐採員で共用する。モデルは +Z が正面。

const MODEL := "res://assets/kenney/platformer/character.glb"

var _anim: AnimationPlayer
var _axe_pivot: Node3D
var _hat_root: Node3D
var _moving := false


func _init(model_scale := 1.15) -> void:
	var model := Fx.model(MODEL)
	model.scale = Vector3.ONE * model_scale
	add_child(model)
	var found := model.find_children("*", "AnimationPlayer", true, false)
	if found.size() > 0:
		_anim = found[0]
		_anim.play("idle")
	# 斧は右腕にくっつける（腕のアニメに合わせて動く）
	var arm := model.find_child("arm-right", true, false) as Node3D
	_axe_pivot = Node3D.new()
	if arm:
		arm.add_child(_axe_pivot)
		_axe_pivot.position = Vector3(-0.05, -0.1, 0.12)
	else:
		add_child(_axe_pivot)
		_axe_pivot.position = Vector3(0.45, 0.6, 0.1)
	_axe_pivot.add_child(Fx.box(Vector3(0.06, 0.06, 0.62), Color("#8a5a33"), Vector3(0, 0, 0.25)))
	_axe_pivot.add_child(Fx.box(Vector3(0.04, 0.24, 0.18), Color("#c8ccd0"), Vector3(0, 0.08, 0.52)))
	_axe_pivot.add_child(Fx.box(Vector3(0.045, 0.06, 0.08), Color("#e8e8ec"), Vector3(0, 0.2, 0.52)))
	_hat_root = Node3D.new()
	_hat_root.position = Vector3(0, 1.08 * model_scale, 0)
	add_child(_hat_root)


## 帽子（ヘルメット）の色を設定する。
func set_hat(color: Color) -> void:
	for c in _hat_root.get_children():
		c.queue_free()
	_hat_root.add_child(Fx.cylinder(0.3, 0.06, color.darkened(0.15), Vector3(0, 0.0, 0.04), -1.0, 10))
	_hat_root.add_child(Fx.sphere(0.24, color, Vector3(0, 0.02, 0), 10, 5))


func set_moving(moving: bool, speed_scale := 1.0) -> void:
	if _anim == null:
		return
	_anim.speed_scale = speed_scale if moving else 1.0
	if moving == _moving:
		return
	_moving = moving
	_anim.play("walk" if moving else "idle", 0.15)


func swing() -> void:
	var tween := create_tween()
	tween.tween_property(_axe_pivot, "rotation_degrees:x", -80.0, 0.08)
	tween.tween_property(_axe_pivot, "rotation_degrees:x", 45.0, 0.08)
	tween.tween_property(_axe_pivot, "rotation_degrees:x", 0.0, 0.14)
