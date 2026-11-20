class_name Decor
## 地面の飾り（草・花・石・道・マップ外の森）。当たり判定は無く、MultiMesh でまとめて描画する。

const GRASS_MODEL := "res://assets/kenney/platformer/grass-small.glb"


static func build(parent: Node3D, area_ranges: Array[Vector2], width: float, base_depth: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 99
	var far: float = area_ranges[-1].y
	var half := width * 0.5

	# マップの外側まで続く地面
	var outer := PlaneMesh.new()
	outer.size = Vector2(width + 60, base_depth - far + 60)
	outer.material = Fx.material(Color("#5f9443"))
	var outer_mi := MeshInstance3D.new()
	outer_mi.mesh = outer
	outer_mi.position = Vector3(0, -0.02, (base_depth + far) * 0.5)
	parent.add_child(outer_mi)

	# 中央の道（拠点から奥のエリアへ）
	var road := PlaneMesh.new()
	road.size = Vector2(2.6, base_depth - far)
	road.material = Fx.material(Color("#c9a874"))
	var road_mi := MeshInstance3D.new()
	road_mi.mesh = road
	road_mi.position = Vector3(0, 0.006, (base_depth + far) * 0.5)
	parent.add_child(road_mi)

	# 草
	var grass_mesh := _first_mesh(Fx.model(GRASS_MODEL))
	if grass_mesh:
		var xforms: Array[Transform3D] = []
		for i in 900:
			var p := Vector3(rng.randf_range(-half, half), 0, rng.randf_range(far, 0.0))
			if absf(p.x) < 1.5:
				continue
			var s := rng.randf_range(0.7, 1.3)
			xforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), p))
		_multimesh(parent, grass_mesh, xforms)

	# 花
	var flower_colors := [Color("#ffffff"), Color("#ffd84a"), Color("#ff8fb1"), Color("#b58cff")]
	for c in flower_colors:
		var head := Fx.merged("flower/" + c.to_html(), [
			[_cyl(0.015, 0.22, 4), Transform3D(Basis(), Vector3(0, 0.11, 0)), Color("#3f8a3a")],
			[_sph(0.07, 5, 3), Transform3D(Basis(), Vector3(0, 0.24, 0)), c],
		])
		var xf: Array[Transform3D] = []
		for i in 70:
			var p := Vector3(rng.randf_range(-half, half), 0, rng.randf_range(far, 0))
			if absf(p.x) < 1.5:
				continue
			xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
		_multimesh(parent, head, xf)

	# 石
	var rock := Fx.merged("rock", [
		[_sph(0.35, 6, 3), Transform3D(Basis().scaled(Vector3(1.2, 0.6, 1.0)), Vector3(0, 0.1, 0)), Color("#9a9a92")],
		[_sph(0.2, 5, 3), Transform3D(Basis().scaled(Vector3(1.0, 0.7, 1.1)), Vector3(0.3, 0.05, 0.15)), Color("#86867e")],
	])
	var rock_xf: Array[Transform3D] = []
	for i in 70:
		var p := Vector3(rng.randf_range(-half, half), 0, rng.randf_range(far, base_depth))
		# 拠点の施設まわりと道は避ける
		if absf(p.x) < 2.0 or (p.z > 0.0 and absf(p.x) < 15.0):
			continue
		rock_xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.6, 1.4)), p))
	_multimesh(parent, rock, rock_xf)

	# マップの外側の森（飾り）
	var border: Dictionary = {}
	var z := base_depth + 6.0
	while z > far - 6.0:
		for side in [-1, 1]:
			for k in 3:
				var x: float = side * (half + 1.2 + k * 1.8 + rng.randf_range(0, 0.8))
				_add_border_tree(border, rng, Vector3(x, 0, z + rng.randf_range(-0.6, 0.6)))
		z -= 1.7
	var x2 := -half - 6.0
	while x2 < half + 6.0:
		for k in 3:
			_add_border_tree(border, rng, Vector3(x2 + rng.randf_range(-0.5, 0.5), 0, base_depth + 1.2 + k * 1.8))
			_add_border_tree(border, rng, Vector3(x2 + rng.randf_range(-0.5, 0.5), 0, far - 1.2 - k * 1.8))
		x2 += 1.7
	for key in border:
		_multimesh(parent, border[key][0], border[key][1])


static func _add_border_tree(border: Dictionary, rng: RandomNumberGenerator, pos: Vector3) -> void:
	var defs := ["pine", "pine", "sapling", "oak", "maple"]
	var def := GameData.tree_def(defs[rng.randi() % defs.size()])
	if def.is_empty():
		return
	var variant := rng.randi() % ChoppableTree.VARIANTS
	var key := "%s/%d" % [def["id"], variant]
	if not border.has(key):
		var xforms: Array[Transform3D] = []
		border[key] = [ChoppableTree._build_mesh(def, variant), xforms]
	(border[key][1] as Array[Transform3D]).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), pos))


static func _multimesh(parent: Node3D, mesh: Mesh, xforms: Array[Transform3D]) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	parent.add_child(mmi)


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
