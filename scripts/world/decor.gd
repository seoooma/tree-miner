class_name Decor
## 地面の飾り（草・花・石・道・マップ外の森）。当たり判定は無く、MultiMesh でまとめて描画する。

const NATURE := "res://assets/kenney/nature/"

## 草・花・石を置かない縦の帯 Vector2(中心x, 半幅)。川（水面と土手）の上に草が生えないようにする
static var clear_bands: Array[Vector2] = []
## 草・花・石を置かない四角 Vector4(中心x, 中心z, 半幅x, 半幅z)。地面の枠（川の積み込み枠・エリア開放の支払い枠）の上に草が載らないようにする
static var clear_rects: Array[Vector4] = []


static func build(parent: Node3D, area_ranges: Array[Vector2], width: float, base_depth: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 99
	var far: float = area_ranges[-1].y
	var half := width * 0.5

	# マップの外側まで続く地面
	var outer := PlaneMesh.new()
	outer.size = Vector2(width + 60, base_depth - far + 60)
	outer.material = Mats.ground("outer")
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
	# 道は大きな半透明の板なので、並べ替えでエリア開放の枠などの印より手前に描かれないよう、いつも先に描く
	road_mi.sorting_offset = -100.0
	parent.add_child(road_mi)
	# 草と花（Kenney Nature Kit。色はパレットに合わせて塗り替える）
	var tufts: Array[Mesh] = []
	for n in ["grass_large", "grass_leafs", "grass_leafsLarge"]:
		tufts.append(Fx.model_merged("decor/" + n, NATURE + n + ".glb",
			func(_m: String, _b: Color) -> Color: return Color("#78b84a"),
			Transform3D(Basis.from_scale(Vector3.ONE * 1.3), Vector3.ZERO)))
	var chunks: Dictionary = {}
	for i in 1100:
		var p := Vector3(rng.randf_range(-half, half), 0, rng.randf_range(far, base_depth))
		if absf(p.x) < 1.5 or Mats.is_sand(p, 0.4) or _in_band(p):
			continue
		var s := rng.randf_range(0.7, 1.3)
		var key := "%d/%d" % [floori(p.z / 20.0), i % tufts.size()]
		if not chunks.has(key):
			var arr: Array[Transform3D] = []
			chunks[key] = arr
		(chunks[key] as Array[Transform3D]).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), p))
	for key in chunks:
		_multimesh(parent, tufts[int(key.split("/")[1])], chunks[key], Mats.foliage(), false)

	var flower_colors := [Color("#fff4e0"), Color("#ffd23f"), Color("#ff7a9c"), Color("#b18cff")]
	var flower_models := ["flower_yellowA", "flower_redA", "flower_purpleA", "flower_yellowB"]
	for fi in flower_colors.size():
		var petal: Color = flower_colors[fi]
		var head := Fx.model_merged("decor/flower/%d" % fi, NATURE + flower_models[fi] + ".glb",
			func(m: String, _b: Color) -> Color: return Color("#5c9a3a") if m.to_lower().contains("grass") or m.to_lower().contains("leaf") else petal,
			Transform3D(Basis.from_scale(Vector3.ONE * 1.6), Vector3.ZERO))
		var xf: Array[Transform3D] = []
		for i in 75:
			var p := Vector3(rng.randf_range(-half, half), 0, rng.randf_range(far, base_depth))
			if absf(p.x) < 1.5 or Mats.is_sand(p, 0.4) or _in_band(p):
				continue
			xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
		_multimesh(parent, head, xf, Mats.foliage(), false)

	# 石（Kenney Nature Kit の岩。上に草が載っている。色はパレットに合わせる）
	var rocks: Array[Mesh] = []
	for n in ["rock_largeA", "rock_largeB", "rock_smallC"]:
		rocks.append(Fx.model_merged("decor/" + n, NATURE + n + ".glb",
			func(m: String, _b: Color) -> Color: return Color("#86c053") if m.to_lower().contains("grass") else Color("#b9bec4"),
			Transform3D(Basis.from_scale(Vector3.ONE * 1.0), Vector3.ZERO)))
	var rock_xf: Array = []
	for r in rocks:
		var arr: Array[Transform3D] = []
		rock_xf.append(arr)
	for i in 70:
		var p := Vector3(rng.randf_range(-half, half), 0, rng.randf_range(far, base_depth))
		# 拠点の施設まわりと道は避ける
		if absf(p.x) < 2.0 or (p.z > 0.0 and absf(p.x) < 15.0) or rocks.is_empty() or _in_band(p, 0.6):
			continue
		(rock_xf[i % rocks.size()] as Array[Transform3D]).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.5)), p))
	for k in rocks.size():
		_multimesh(parent, rocks[k], rock_xf[k])

	# マップの外側の森（飾り）。左右の外側には生やさず、奥と手前の帯だけ
	var border: Dictionary = {}
	var x2 := -half + 0.8
	while x2 < half - 0.8:
		for k in 3:
			_add_border_tree(border, rng, Vector3(x2 + rng.randf_range(-0.5, 0.5), 0, base_depth + 2.6 + k * 1.8))
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


static func _in_band(p: Vector3, margin := 0.0) -> bool:
	for b in clear_bands:
		if absf(p.x - b.x) < b.y + margin:
			return true
	for r in clear_rects:
		if absf(p.x - r.x) < r.z + margin and absf(p.z - r.y) < r.w + margin:
			return true
	return false


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
