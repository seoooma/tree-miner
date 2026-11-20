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
	_apply_workwear(model)
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
	_axe_pivot.add_child(make_axe())
	_hat_root = Node3D.new()
	_hat_root.position = Vector3(0, 1.08 * model_scale, 0)
	add_child(_hat_root)


## Kenney のキャラクターを作業着の配色（白シャツ・デニムのオーバーオール・茶色のブーツ）に塗り替える。
func _apply_workwear(model: Node3D) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var src := m.mesh.surface_get_material(0) as BaseMaterial3D
		var texture: Texture2D = src.albedo_texture if src else null
		if texture == null:
			continue
		match str(m.name):
			"torso":
				m.material_override = Mats.worker(texture, 0)
			"arm-left", "arm-right":
				m.material_override = Mats.worker(texture, 1)
			"leg-left", "leg-right":
				m.material_override = Mats.worker(texture, 2)
			"antenna":
				m.visible = false


## 斧の見た目（柄が +Z 方向）。強化画面のサムネイルでも使う。
static func make_axe() -> Node3D:
	var root := Node3D.new()
	root.add_child(_part(Fx.box(Vector3(0.06, 0.06, 0.62), Color.WHITE, Vector3(0, 0, 0.25)), Mats.surface(Color("#8a5a33"), "wood")))
	root.add_child(_part(Fx.box(Vector3(0.04, 0.24, 0.18), Color.WHITE, Vector3(0, 0.08, 0.52)), Mats.surface(Color("#9aa0a6"), "metal")))
	root.add_child(_part(Fx.box(Vector3(0.045, 0.06, 0.08), Color.WHITE, Vector3(0, 0.2, 0.52)), Mats.surface(Color("#d8dce0"), "metal")))
	return root


static func _part(mi: MeshInstance3D, mat: Material) -> MeshInstance3D:
	mi.material_override = mat
	return mi


## ヘルメット（黄色の作業用ヘルメット。ツヤあり）の色を設定する。
func set_hat(color: Color) -> void:
	for c in _hat_root.get_children():
		c.queue_free()
	var mat := Mats.surface(color, "paint", 0.32)
	_hat_root.add_child(_part(Fx.cylinder(0.31, 0.04, Color.WHITE, Vector3(0, -0.01, 0.05), -1.0, 16), Mats.surface(color.darkened(0.12), "paint", 0.4)))
	_hat_root.add_child(_part(Fx.sphere(0.25, Color.WHITE, Vector3(0, 0.0, 0), 16, 8), mat))
	_hat_root.add_child(_part(Fx.box(Vector3(0.05, 0.05, 0.5), Color.WHITE, Vector3(0, 0.24, 0)), mat))


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
