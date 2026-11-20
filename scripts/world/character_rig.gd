class_name CharacterRig
extends Node3D
## キャラクターの見た目（Quaternius の作業員モデル＋斧）と、待機／歩き／走り／斧を振るアニメの切り替え。
## プレイヤーと伐採員で共用する。モデルは +Z が正面。
## 服の色は作業着（黄色のヘルメット・白シャツ・デニムのオーバーオール・茶色のブーツ）に塗り替える。

const MODELS := ["res://assets/quaternius/worker_male.glb", "res://assets/quaternius/worker_female.glb"]
## 元のモデルは身長が約 3.3。model_scale 1.0 で身長が約 1.35 m になる倍率
const BASE_SCALE := 0.41
const LOOPS := ["Idle", "Walk", "Run"]

var _anim: AnimationPlayer
var _axe_pivot: Node3D
var _body: MeshInstance3D
var _moving := false
var _move_anim := "Idle"
var _swinging := 0.0


## variant: 0 = 男性、1 = 女性の作業員
func _init(model_scale := 1.15, variant := 0) -> void:
	var model := Fx.model(MODELS[clampi(variant, 0, MODELS.size() - 1)])
	model.scale = Vector3.ONE * model_scale * BASE_SCALE
	add_child(model)
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if meshes.size() > 0:
		_body = meshes[0]
		_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_apply_workwear(_body)
	var found := model.find_children("*", "AnimationPlayer", true, false)
	if found.size() > 0:
		_anim = found[0]
		for a in LOOPS:
			if _anim.has_animation(a):
				_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		_anim.play("Idle")
	# 斧は右手のボーンにくっつける（腕のアニメに合わせて動く）
	_axe_pivot = Node3D.new()
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.size() > 0:
		var att := BoneAttachment3D.new()
		att.bone_name = "Fist.R"
		skels[0].add_child(att)
		att.add_child(_axe_pivot)
		# 拳の中で柄を握り、刃が前を向くように。ボーンの空間はモデルの縮尺がかかっているので逆に戻す
		_axe_pivot.scale = Vector3.ONE / BASE_SCALE
		_axe_pivot.position = Vector3(0, 0.12, 0)
		_axe_pivot.rotation_degrees = Vector3(-90, 0, 0)
	else:
		add_child(_axe_pivot)
		_axe_pivot.position = Vector3(0.45, 0.6, 0.1)
	var axe := make_axe()
	axe.position = Vector3(0, 0, -0.18)
	_axe_pivot.add_child(axe)


## マテリアル名ごとに作業着の色を割り当てる（Skin は手足と顔。ひざ下は茶色のブーツ）
func _apply_workwear(mi: MeshInstance3D) -> void:
	for i in mi.mesh.get_surface_count():
		var src := mi.mesh.surface_get_material(i)
		var mat_name := src.resource_name if src else ""
		var mat: Material = null
		match mat_name:
			"Skin":
				mat = Mats.worker_skin()
			"Shirt":
				mat = Mats.cloth(Color("#eceae4"), 0.9)
			"Vest", "Pants":
				mat = Mats.cloth(Color("#3a5a8c"), 0.85, true)
			"Hat":
				mat = Mats.surface(Color("#f2c230"), "paint", 0.32)
			"Hair":
				mat = Mats.cloth(Color("#4a2f1c"), 0.7)
		if mat:
			mi.set_surface_override_material(i, mat)


## 斧の見た目（Kenney Survival Kit の斧。柄が +Z 方向、刃が +Y 側）。強化画面のサムネイルでも使う。
const AXE_MODEL := "res://assets/kenney/survival/tool-axe.glb"


static func make_axe() -> Node3D:
	var root := Node3D.new()
	var axe := Fx.model(AXE_MODEL)
	# 元のモデルは柄が +Y（長さ約 0.26）、刃が -X 側。柄を +Z・刃を +Y に向け、約 0.62 の長さにする
	axe.transform = Transform3D(Basis(Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)).scaled(Vector3.ONE * 2.4), Vector3.ZERO)
	root.add_child(axe)
	return root


static func _part(mi: MeshInstance3D, mat: Material) -> MeshInstance3D:
	mi.material_override = mat
	return mi


## ヘルメットの色を設定する（モデルのヘルメット部分の色を置き換える）。
func set_hat(color: Color) -> void:
	if _body == null:
		return
	for i in _body.mesh.get_surface_count():
		var src := _body.mesh.surface_get_material(i)
		if src and src.resource_name == "Hat":
			_body.set_surface_override_material(i, Mats.surface(color, "paint", 0.32))


func set_moving(moving: bool, speed_scale := 1.0) -> void:
	if _anim == null:
		return
	# 速いときは走り、ゆっくりのときは歩き
	var want := "Idle"
	if moving:
		want = "Run" if speed_scale >= 0.85 else "Walk"
	_anim.speed_scale = (speed_scale / (1.0 if want == "Run" else 0.7)) if moving else 1.0
	_moving = moving
	if _swinging > 0.0:
		_move_anim = want
		return
	if want == _move_anim and _anim.current_animation == want:
		return
	_move_anim = want
	_anim.play(want, 0.15)


## 斧を振る。止まっているときは全身の振り下ろしアニメ、歩きながらなら腕の斧だけ振る。
func swing() -> void:
	var tween := create_tween()
	tween.tween_property(_axe_pivot, "rotation_degrees:x", -150.0, 0.08)
	tween.tween_property(_axe_pivot, "rotation_degrees:x", -45.0, 0.08)
	tween.tween_property(_axe_pivot, "rotation_degrees:x", -90.0, 0.14)
	if _anim == null or _moving or not _anim.has_animation("SwordSlash"):
		return
	_swinging = 0.4
	_anim.play("SwordSlash", 0.06, 2.6)


func _process(delta: float) -> void:
	if _swinging <= 0.0:
		return
	_swinging -= delta
	if _swinging <= 0.0 and _anim:
		_anim.play(_move_anim, 0.12)
