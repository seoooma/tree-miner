class_name Fx
## 演出・プレースホルダ用の小さなヘルパー群。


## 頭上に数字などを浮かび上がらせる。
static func popup(context: Node, world_pos: Vector3, text: String, color := Color.WHITE) -> void:
	var scene := context.get_tree().current_scene
	if scene == null:
		return
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 64
	label.pixel_size = 0.01
	label.outline_size = 16
	label.modulate = color
	scene.add_child(label)
	label.global_position = world_pos + Vector3(0, 2.2, 0)
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y + 1.4, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)


static func material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	return m


static func box(size: Vector3, color: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material(color)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	return mi


static func cylinder(radius: float, height: float, color: Color, pos := Vector3.ZERO, top_radius := -1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.material = material(color)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	return mi


static func sphere(radius: float, color: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.material = material(color)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	return mi


## 地面に置く丸い床マーカー（売却ポイントなど）。
static func pad(radius: float, color: Color) -> MeshInstance3D:
	var mi := cylinder(radius, 0.06, color, Vector3(0, 0.03, 0))
	(mi.mesh as CylinderMesh).radial_segments = 32
	return mi


static func label3d(text: String, pos: Vector3, size := 48) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = pos
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = size
	label.pixel_size = 0.01
	label.outline_size = 12
	label.no_depth_test = true
	return label


static func xz_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
