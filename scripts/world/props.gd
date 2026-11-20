class_name Props
## 建物や小物の見た目パーツ（屋根・板壁・丸太の山・木箱・看板など）。どれも当たり判定なしの見た目だけ。


## 切妻屋根（棟が X 方向）。底面が y=0、幅 width・奥行き depth・高さ height。
static func gable_roof(width: float, depth: float, height: float, color: Color) -> MeshInstance3D:
	var prism := CylinderMesh.new()
	prism.radial_segments = 3
	prism.rings = 1
	prism.top_radius = 1.0
	prism.bottom_radius = 1.0
	prism.height = 1.0
	# 三角柱の頂点が上を向くよう Y→Z の順に90度回し、断面（半径1の正三角形）を depth x height に合わせる
	var orient := Basis(Vector3.BACK, PI * 0.5) * Basis(Vector3.UP, PI * 0.5)
	var fit := Basis.from_scale(Vector3(width, height / 1.5, depth / 1.732))
	var mesh := Fx.merged("roof/%s/%.2f/%.2f/%.2f" % [color.to_html(), width, depth, height], [
		[prism, Transform3D(fit * orient, Vector3(0, height / 3.0, 0)), color],
	])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Mats.surface(color, "metal", 0.6)
	return mi


## 縦板張りの壁（前面に目地の線が入る）。
static func plank_wall(size: Vector3, color: Color) -> Node3D:
	var root := Node3D.new()
	root.add_child(Fx.box(size, color, Vector3(0, size.y * 0.5, 0), "wood"))
	var n := int(size.x / 0.32)
	for i in range(1, n):
		var x := -size.x * 0.5 + i * size.x / n
		root.add_child(Fx.box(Vector3(0.03, size.y * 0.96, 0.02), color.darkened(0.25), Vector3(x, size.y * 0.5, size.z * 0.5 + 0.01)))
		root.add_child(Fx.box(Vector3(0.03, size.y * 0.96, 0.02), color.darkened(0.25), Vector3(x, size.y * 0.5, -size.z * 0.5 - 0.01)))
	return root


## 丸太を三角に積んだ山。
static func log_pile(rows := 3, tree_id := "pine") -> Node3D:
	var root := Node3D.new()
	for r in rows:
		var count := rows - r
		for i in count:
			var piece := LogDrop.make_log_mesh(tree_id)
			piece.scale = Vector3(2.2, 1.6, 1.6)
			piece.rotation_degrees.y = 90.0
			piece.position = Vector3(0, 0.18 + r * 0.3, (i - (count - 1) * 0.5) * 0.36)
			root.add_child(piece)
	return root


static func crate(size := 0.7, color := Color("#c99a5b")) -> Node3D:
	var root := Node3D.new()
	root.add_child(Fx.box(Vector3.ONE * size, color, Vector3(0, size * 0.5, 0), "wood"))
	var edge := color.darkened(0.3)
	for y in [0.06, size - 0.06]:
		root.add_child(Fx.box(Vector3(size + 0.02, 0.08, size + 0.02), edge, Vector3(0, y, 0)))
	root.add_child(Fx.box(Vector3(0.08, size, 0.02), edge, Vector3(0, size * 0.5, size * 0.5 + 0.01)))
	return root


static func pallet_of_planks(color := Color("#e8c99a")) -> Node3D:
	var root := Node3D.new()
	root.add_child(Fx.box(Vector3(1.2, 0.12, 1.0), Color("#a8834f"), Vector3(0, 0.06, 0), "wood"))
	for layer in 4:
		for i in 3:
			root.add_child(Fx.box(Vector3(1.1, 0.1, 0.28), color.darkened(0.04 * ((i + layer) % 2)), Vector3(0, 0.17 + layer * 0.11, (i - 1) * 0.31), "wood"))
	return root


## 2本の柱で立つ看板。文字は Label3D（ビルボードではなく板に貼る）。
static func signboard(text: String, color := Color("#7a4a2a")) -> Node3D:
	var root := Node3D.new()
	for x in [-0.7, 0.7]:
		root.add_child(Fx.cylinder(0.06, 1.6, color.darkened(0.2), Vector3(x, 0.8, 0), -1.0, 6, false, "wood"))
	root.add_child(Fx.box(Vector3(1.8, 0.6, 0.08), color, Vector3(0, 1.45, 0), "wood"))
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.pixel_size = 0.004
	label.outline_size = 8
	label.outline_modulate = Color(0.15, 0.08, 0.03)
	label.position = Vector3(0, 1.45, 0.05)
	root.add_child(label)
	return root


## 低い植え込み。
static func bush(color := Color("#4f9a45")) -> Node3D:
	var root := Node3D.new()
	root.add_child(Fx.sphere(0.45, color, Vector3(0, 0.3, 0), 7, 4, true))
	root.add_child(Fx.sphere(0.32, color.lightened(0.08), Vector3(0.35, 0.22, 0.1), 7, 4, true))
	return root
