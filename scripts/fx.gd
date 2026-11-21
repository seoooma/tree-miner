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


## 球や円錐の表面をなめらかなノイズででこぼこにする（木の葉のかたまりを自然な形にする）。
## 頂点の位置だけで決まるので、継ぎ目で同じ位置にある頂点は同じだけ動き、すき間はできない。
## droop を付けると、外側に張り出した所ほど少し下に垂れる（針葉樹の枝先）。
static func lumpy(mesh: Mesh, amount: float, seed_value: float, droop := 0.0) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var out := PackedVector3Array()
	out.resize(verts.size())
	for i in verts.size():
		var v := verts[i]
		var d := v.normalized() if v.length() > 0.0001 else Vector3.UP
		var n := sin(d.x * 3.1 + seed_value) * 0.5 + sin(d.y * 4.3 + d.z * 2.2 + seed_value * 1.7) * 0.35 \
			+ sin(d.z * 5.7 - d.x * 3.3 + seed_value * 2.9) * 0.25
		var radial := Vector3(v.x, 0, v.z)
		var w := v + radial * n * amount + Vector3(0, v.y, 0) * n * amount * 0.5
		if droop != 0.0:
			w.y -= radial.length() * droop * (0.6 + 0.4 * n)
		out[i] = w
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = out
	if arrays[Mesh.ARRAY_INDEX] != null:
		arr[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return result


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
		if is_flat:
			return flat(m)
		return m)
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
		if is_flat:
			return flat(m)
		return m)
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
## 色が3色以上で勢いがあるもの（購入・開放のお祝い）は、ひらひら舞う紙吹雪にする。
static func burst(context: Node, world_pos: Vector3, colors: Array, amount := 10, speed := 3.0, size := 0.09, lifetime := 0.7, gravity := -9.0) -> void:
	var confetti := colors.size() >= 3 and speed >= 5.0
	Vfx.burst(context, world_pos, colors, amount, speed, size, lifetime + (0.6 if confetti else 0.0), gravity * (0.45 if confetti else 1.0), confetti)
	if confetti:
		Vfx.sparkles(context, world_pos + Vector3(0, 0.4, 0), Color("#fff0b0"), 10, 4.0)
		Vfx.flash(context, world_pos, Color("#fff2c0"), 2.6)


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


## コインが跳ねて消える演出（売却時）。回りながら跳ね上がり、てっぺんでキラッと光って消える。
static func coin_pop(context: Node, world_pos: Vector3) -> void:
	var scene := context.get_tree().current_scene
	if scene == null:
		return
	var coin := model("res://assets/kenney/platformer/coin.glb")
	scene.add_child(coin)
	var start := world_pos + Vector3(randf_range(-0.3, 0.3), 0.9, randf_range(-0.3, 0.3))
	coin.global_position = start
	coin.scale = Vector3.ONE * 0.2
	var peak := start + Vector3(0, 1.5, 0)
	var tween := coin.create_tween().set_parallel()
	tween.tween_property(coin, "scale", Vector3.ONE * 0.6, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(coin, "global_position", peak, 0.42).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(coin, "rotation:y", TAU * 2.5, 0.6).set_ease(Tween.EASE_OUT)
	tween.tween_property(coin, "scale", Vector3.ZERO, 0.16).set_delay(0.46).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(coin.queue_free)
	Vfx.flash(context, start, Color("#ffd75a"), 1.3)
	coin.get_tree().create_timer(0.4).timeout.connect(func() -> void:
		if is_instance_valid(coin):
			Vfx.sparkles(coin, peak, Color("#ffe38a"), 7, 2.2))


## カメラを軽く揺らす（木が倒れたときなど）。
static func shake(context: Node, strength := 0.12) -> void:
	var cam := context.get_viewport().get_camera_3d()
	if cam and cam.has_method("add_shake"):
		cam.add_shake(strength)


static func xz_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
