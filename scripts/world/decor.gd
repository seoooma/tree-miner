class_name Decor
## 地面の飾り（草・花・石・道・マップ外の森）。当たり判定は無く、MultiMesh でまとめて描画する。

const GRASS_MODEL := "res://assets/kenney/platformer/grass-small.glb"
const ROCK_MODELS := ["res://assets/kenney/survival/rock-a.glb", "res://assets/kenney/survival/rock-c.glb"]


static func build(parent: Node3D, area_ranges: Array[Vector2], width: float, base_depth: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 99
	var far: float = area_ranges[-1].y
	var half := width * 0.5

	# マップの外側まで続く地面
	var outer := PlaneMesh.new()
	outer.size = Vector2(width + 60, base_depth - far + 60)
	outer.material = Mats.ground("grass", Color("#b8c8a0"))
	var outer_mi := MeshInstance3D.new()
	outer_mi.mesh = outer
	outer_mi.position = Vector3(0, -0.02, (base_depth + far) * 0.5)
	parent.add_child(outer_mi)

	# 中央の道（拠点から奥のエリアへ）。端は草地になじませる
	var road := PlaneMesh.new()
	road.size = Vector2(3.4, -far + 2.0)
	road.material = Mats.strip("road", 0)
	var road_mi := MeshInstance3D.new()
	road_mi.mesh = road
	road_mi.position = Vector3(0, 0.008, far * 0.5 + 1.0)
	road_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(road_mi)
	# 作業場（土）と草地の境目をぼかす帯
	var seam := PlaneMesh.new()
	seam.size = Vector2(width, 2.4)
	seam.material = Mats.strip("yard", 1)
	var seam_mi := MeshInstance3D.new()
	seam_mi.mesh = seam
	seam_mi.position = Vector3(0, 0.004, -1.2 + 0.001)
	seam_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(seam_mi)

	# 草
	var grass_mesh := _first_mesh(Fx.model(GRASS_MODEL))
	if grass_mesh:
		var chunks: Dictionary = {}
		for i in 900:
			var p := Vector3(rng.randf_range(-half, half), 0, rng.randf_range(far, 0.0))
			if absf(p.x) < 1.5:
				continue
			var s := rng.randf_range(0.7, 1.3)
			var c := floori(p.z / 20.0)
			if not chunks.has(c):
				var arr: Array[Transform3D] = []
				chunks[c] = arr
			(chunks[c] as Array[Transform3D]).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), p))
		var grass_mat := StandardMaterial3D.new()
		grass_mat.albedo_color = Color("#5d8a3c")
		grass_mat.roughness = 0.9
		for c in chunks:
			_multimesh(parent, grass_mesh, chunks[c], grass_mat, false)

	# 花
	var flower_colors := [Color("#e8e4d8"), Color("#e0c050"), Color("#d88a9c"), Color("#9c86c8")]
	for c in flower_colors:
		var head := Fx.merged("flower/" + c.to_html(), [
			[_cyl(0.015, 0.22, 4), Transform3D(Basis(), Vector3(0, 0.11, 0)), Color("#4a6e34")],
			[_sph(0.07, 5, 3), Transform3D(Basis(), Vector3(0, 0.24, 0)), c],
		])
		var xf: Array[Transform3D] = []
		for i in 70:
			var p := Vector3(rng.randf_range(-half, half), 0, rng.randf_range(far, 0))
			if absf(p.x) < 1.5:
				continue
			xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
		_multimesh(parent, head, xf, null, false)

	# 石（Kenney Survival Kit の岩を2種類）
	var rocks: Array[Mesh] = []
	for path in ROCK_MODELS:
		var m := _first_mesh(Fx.model(path))
		if m:
			rocks.append(m)
	var rock_xf: Array = []
	for r in rocks:
		var arr: Array[Transform3D] = []
		rock_xf.append(arr)
	for i in 70:
		var p := Vector3(rng.randf_range(-half, half), 0, rng.randf_range(far, base_depth))
		# 拠点の施設まわりと道は避ける
		if absf(p.x) < 2.0 or (p.z > 0.0 and absf(p.x) < 15.0) or rocks.is_empty():
			continue
		(rock_xf[i % rocks.size()] as Array[Transform3D]).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.5)), p))
	for k in rocks.size():
		_multimesh(parent, rocks[k], rock_xf[k], Mats.surface(Color("#a8a296"), "paint", 0.9))

	# マップの外側の森（飾り）。左右の外側には生やさず、奥と手前の帯だけ
	var border: Dictionary = {}
	var x2 := -half + 0.8
	while x2 < half - 0.8:
		for k in 3:
			_add_border_tree(border, rng, Vector3(x2 + rng.randf_range(-0.5, 0.5), 0, base_depth + 1.2 + k * 1.8))
			_add_border_tree(border, rng, Vector3(x2 + rng.randf_range(-0.5, 0.5), 0, far - 1.2 - k * 1.8))
		x2 += 1.7
	for key in border:
		var mmi := _multimesh(parent, border[key][0], border[key][1], Mats.tree(true), false)
		var mm := mmi.multimesh
		var xfs: Array[Transform3D] = border[key][1]
		mm.instance_count = 0
		mm.use_colors = true
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
			mm.set_instance_color(i, TreeField.random_tint(rng))


static func _add_border_tree(border: Dictionary, rng: RandomNumberGenerator, pos: Vector3) -> void:
	var defs := ["pine", "pine", "sapling", "oak", "maple"]
	var def := GameData.tree_def(defs[rng.randi() % defs.size()])
	if def.is_empty():
		return
	var variant := rng.randi() % ChoppableTree.VARIANTS
	# 20m ごとに分けて、画面外の塊は描かないようにする（視錐台カリング）
	var key := "%s/%d/%d" % [def["id"], variant, floori(pos.z / 20.0)]
	if not border.has(key):
		var xforms: Array[Transform3D] = []
		border[key] = [ChoppableTree._build_mesh(def, variant), xforms]
	(border[key][1] as Array[Transform3D]).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), pos))


static func _multimesh(parent: Node3D, mesh: Mesh, xforms: Array[Transform3D], mat: Material = null, shadows := true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi


static func _first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		return (node as MeshInstance3D).mesh
	for child in node.get_children():
		var m := _first_mesh(child)
		if m:
			return m
	return null


static func _cyl(r: float, h: float, seg: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


static func _sph(r: float, seg: int, rings: int) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = rings
	return s
