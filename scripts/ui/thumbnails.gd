class_name Thumbnails
extends Node
## 強化画面のカードに出す小さな画像。ゲーム内のモデル（斧・丸太・作業員・製材所）を
## 起動時に一度だけ画面外の SubViewport で描いて、そのテクスチャを使う。

const SIZE := 192

var _textures: Dictionary = {}


## id ("axe_power" など) のサムネイル。まだ無ければ作る。
func texture_for(id: String) -> Texture2D:
	if not _textures.has(id):
		_textures[id] = _render(id)
	return _textures[id]


func _render(id: String) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#b8c4d4")
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -140, 0)
	sun.light_color = Color("#ffe6c4")
	sun.light_energy = 1.3
	vp.add_child(sun)

	var cam := Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	var subject := Node3D.new()
	vp.add_child(subject)
	var look := Vector3.ZERO
	var dist := 3.0
	match id:
		"axe_power":
			var axe := CharacterRig.make_axe()
			axe.rotation_degrees = Vector3(-60, 90, 0)
			axe.scale = Vector3.ONE * 2.2
			axe.position = Vector3(-0.2, -0.6, 0)
			subject.add_child(axe)
			look = Vector3(0, 0, 0)
			dist = 3.4
		"capacity":
			var pile := Props.log_pile(3, "pine")
			pile.rotation_degrees.y = 75.0
			subject.add_child(pile)
			look = Vector3(0, 0.4, 0)
			dist = 4.6
		"move_speed":
			var rig := CharacterRig.new(1.0)
			rig.set_hat(Color("#f2c230"))
			rig.rotation_degrees.y = 35.0
			subject.add_child(rig)
			rig.set_moving(true)
			look = Vector3(0, 0.6, 0)
			dist = 3.4
		"sawmill":
			var house := Node3D.new()
			Sawmill.build_house(house)
			house.rotation_degrees.y = 200.0
			subject.add_child(house)
			look = Vector3(0, 1.2, 0)
			dist = 11.0
		_:
			for i in 2:
				var rig := CharacterRig.new(1.0)
				rig.set_hat(Color("#f2c230"))
				rig.position = Vector3(-0.5 + i * 0.9, 0, -0.3 * i)
				rig.rotation_degrees.y = 20.0 - i * 30.0
				subject.add_child(rig)
			look = Vector3(0, 0.6, 0)
			dist = 4.4
	var dir := Vector3(0.55, 0.5, 1.0).normalized()
	cam.look_at_from_position(look + dir * dist, look, Vector3.UP)
	return vp.get_texture()
