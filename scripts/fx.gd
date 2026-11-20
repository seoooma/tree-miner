class_name Fx
## 見た目まわりのヘルパー群。
## - メッシュ・マテリアルは同じ形・色ならキャッシュして使い回す（木が数百本あるため）
## - フラットシェーディングのローポリメッシュ、glb モデルの読み込み、パーティクル演出

static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}
static var _scenes: Dictionary = {}


## 頭上に数字などを浮かび上がらせる。
static func popup(context: Node, world_pos: Vector3, text: String, color := Color.WHITE, size := 64) -> void:
	var scene := context.get_tree().current_scene
	if scene == null:
		return
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = size
	label.pixel_size = 0.006
	label.outline_size = 18
	label.outline_modulate = Color(0.1, 0.07, 0.03, 0.9)
	label.modulate = color
	scene.add_child(label)
	label.global_position = world_pos + Vector3(0, 1.8, 0)
	label.scale = Vector3.ONE * 0.4
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:y", label.position.y + 1.0, 0.8).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.35).set_delay(0.5)
	tween.chain().tween_callback(label.queue_free)


# ---- マテリアル・メッシュ ----

## 単色＋細かいムラのマテリアル。kind: "paint" / "wood"（木目）/ "metal"（塗装金属）
static func material(color: Color, roughness := 0.85, kind := "paint") -> StandardMaterial3D:
	return Mats.surface(color, kind, roughness)


## メッシュを面ごとの法線（フラットシェーディング）に変換する。ローポリ感を出すため。
static func flat(mesh: Mesh) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.create_from(mesh, 0)
	st.deindex()
	st.generate_normals()
	var out := st.commit()
	out.surface_set_material(0, mesh.surface_get_material(0))
	return out


## 頂点カラーで色を付けるマテリアル（複数パーツを1つのメッシュにまとめるとき用）
static func vertex_color_material() -> StandardMaterial3D:
	if not _materials.has("__vc"):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.9
		_materials["__vc"] = m
	return _materials["__vc"]


## 複数のプリミティブを1つのフラットシェーディングメッシュにまとめる（描画負荷を下げるため）。
## parts: [[PrimitiveMesh, Transform3D, Color], ...]
static func merged(key: String, parts: Array) -> Mesh:
	return _cached(key, func() -> Mesh:
		var verts := PackedVector3Array()
		var colors := PackedColorArray()
		for part in parts:
			var prim: Mesh = part[0]
			var xf: Transform3D = part[1]
			var color: Color = part[2]
			var arrays := prim.surface_get_arrays(0)
			var pv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				for v in pv:
					verts.append(xf * v)
					colors.append(color)
			else:
				for i in idx:
					verts.append(xf * pv[i])
					colors.append(color)
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_COLOR] = colors
		var raw := ArrayMesh.new()
		raw.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var st := SurfaceTool.new()
		st.create_from(raw, 0)
		st.generate_normals()
		var out := st.commit()
		out.surface_set_material(0, vertex_color_material())
		return out)


static func _cached(key: String, make: Callable) -> Mesh:
	if not _meshes.has(key):
		_meshes[key] = make.call()
	return _meshes[key]


static func _instance(mesh: Mesh, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	return mi


static func box(size: Vector3, color: Color, pos := Vector3.ZERO, kind := "paint") -> MeshInstance3D:
	var mesh := _cached("box%s%s%s" % [size, color.to_html(), kind], func() -> Mesh:
		var m := BoxMesh.new()
		m.size = size
		m.material = material(color, 0.85, kind)
		return m)
	return _instance(mesh, pos)


static func cylinder(radius: float, height: float, color: Color, pos := Vector3.ZERO, top_radius := -1.0, segments := 12, is_flat := false, kind := "paint") -> MeshInstance3D:
	var top := radius if top_radius < 0.0 else top_radius
	var key := "cyl%.3f/%.3f/%.3f/%d/%s/%s/%s" % [radius, height, top, segments, color.to_html(), is_flat, kind]
	var mesh := _cached(key, func() -> Mesh:
		var m := CylinderMesh.new()
		m.bottom_radius = radius
		m.top_radius = top
		m.height = height
		m.radial_segments = segments
		m.rings = 1
		m.material = material(color, 0.85, kind)
		return flat(m) if is_flat else m)
	return _instance(mesh, pos)


static func sphere(radius: float, color: Color, pos := Vector3.ZERO, segments := 12, rings := 6, is_flat := false) -> MeshInstance3D:
	var key := "sph%.3f/%d/%d/%s/%s" % [radius, segments, rings, color.to_html(), is_flat]
	var mesh := _cached(key, func() -> Mesh:
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius * 2.0
		m.radial_segments = segments
		m.rings = rings
		m.material = material(color)
		return flat(m) if is_flat else m)
	return _instance(mesh, pos)


## 地面に置く丸い床マーカー（売却ポイントなど）。縁取り付き。
static func pad(radius: float, color: Color) -> Node3D:
	var root := Node3D.new()
	root.add_child(cylinder(radius + 0.08, 0.05, color.darkened(0.35), Vector3(0, 0.025, 0), -1.0, 40))
	root.add_child(cylinder(radius, 0.07, color, Vector3(0, 0.035, 0), -1.0, 40))
	return root


static func label3d(text: String, pos: Vector3, size := 48) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = pos
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = size
	label.pixel_size = 0.006
	label.outline_size = 14
	label.outline_modulate = Color(0.1, 0.07, 0.03, 0.85)
	label.no_depth_test = true
	return label


## glb などのモデルを読み込んでインスタンス化する。
static func model(path: String) -> Node3D:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	var scene: PackedScene = _scenes[path]
	return scene.instantiate() as Node3D


# ---- 演出 ----

## 小さな破片を飛び散らせる（木くず・葉っぱ・砂ぼこり・紙吹雪など）。
static func burst(context: Node, world_pos: Vector3, colors: Array, amount := 10, speed := 3.0, size := 0.09, lifetime := 0.7, gravity := -9.0) -> void:
	var scene := context.get_tree().current_scene
	if scene == null:
		return
	for color in colors:
		var p := CPUParticles3D.new()
		p.one_shot = true
		p.emitting = false
		p.amount = maxi(1, amount / colors.size())
		p.lifetime = lifetime
		p.explosiveness = 0.95
		p.direction = Vector3.UP
		p.spread = 70.0
		p.initial_velocity_min = speed * 0.5
		p.initial_velocity_max = speed
		p.gravity = Vector3(0, gravity, 0)
		p.angular_velocity_min = -360.0
		p.angular_velocity_max = 360.0
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.2
		var curve := Curve.new()
		curve.add_point(Vector2(0, 1))
		curve.add_point(Vector2(0.7, 0.9))
		curve.add_point(Vector2(1, 0))
		p.scale_amount_curve = curve
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * size
		mesh.material = material(color)
		p.mesh = mesh
		scene.add_child(p)
		p.global_position = world_pos
		p.emitting = true
		p.get_tree().create_timer(lifetime + 0.2).timeout.connect(p.queue_free)


## 受け渡しのとき、品物が放物線を描いて飛んでいく演出（見た目だけ）。node は新しく作った見た目のノード。
static func fly_item(context: Node, node: Node3D, from: Vector3, to: Vector3, duration := 0.28) -> void:
	var scene := context.get_tree().current_scene
	if scene == null:
		node.queue_free()
		return
	scene.add_child(node)
	node.global_position = from
	var tween := node.create_tween()
	tween.tween_method(func(t: float) -> void:
		if is_instance_valid(node):
			node.global_position = from.lerp(to, t) + Vector3(0, sin(t * PI) * 1.2, 0), 0.0, 1.0, duration)
	tween.tween_callback(node.queue_free)


## コインが跳ねて消える演出（売却時）。
static func coin_pop(context: Node, world_pos: Vector3) -> void:
	var scene := context.get_tree().current_scene
	if scene == null:
		return
	var coin := model("res://assets/kenney/platformer/coin.glb")
	scene.add_child(coin)
	coin.global_position = world_pos + Vector3(randf_range(-0.3, 0.3), 1.0, randf_range(-0.3, 0.3))
	coin.scale = Vector3.ONE * 0.55
	var tween := coin.create_tween().set_parallel()
	tween.tween_property(coin, "position:y", coin.position.y + 1.4, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(coin, "rotation:y", TAU * 2.0, 0.6)
	tween.tween_property(coin, "scale", Vector3.ZERO, 0.2).set_delay(0.45)
	tween.chain().tween_callback(coin.queue_free)


## カメラを軽く揺らす（木が倒れたときなど）。
static func shake(context: Node, strength := 0.12) -> void:
	var cam := context.get_viewport().get_camera_3d()
	if cam and cam.has_method("add_shake"):
		cam.add_shake(strength)


static func xz_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
