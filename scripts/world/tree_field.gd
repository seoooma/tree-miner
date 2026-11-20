class_name TreeField
extends Node3D
## 木の見た目をまとめて描く（MultiMesh）。木は数百本あるので、1本ずつ描くとスマホのブラウザでは重すぎる。
## ChoppableTree は自分の見た目の Transform をここに書き込むだけで、描画はエリア×種類ごとに1回で済む。
## 葉の色は1本ごとに少しずつ変える（MultiMesh の custom data）。

## key ("area/mesh") -> {"mesh": Mesh, "trees": Array[ChoppableTree]}
var _groups: Dictionary = {}
var _built := false


func register(tree: ChoppableTree, mesh: Mesh, mesh_key: String) -> void:
	var key := "%d/%s" % [tree.area_index, mesh_key]
	if not _groups.has(key):
		_groups[key] = {"mesh": mesh, "trees": []}
	(_groups[key]["trees"] as Array).append(tree)
	if _built:
		push_warning("TreeField: build 後に木が追加された")


## すべての木を登録し終えたら呼ぶ。
func build() -> void:
	_built = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for key in _groups:
		var g: Dictionary = _groups[key]
		var trees: Array = g["trees"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = g["mesh"]
		mm.instance_count = trees.size()
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = Mats.tree(true)
		add_child(mmi)
		for i in trees.size():
			var tree: ChoppableTree = trees[i]
			# 葉の色ムラ（明るさと、黄み／青みを少し）
			var v := rng.randf_range(0.82, 1.12)
			var warm := rng.randf_range(-0.06, 0.08)
			mm.set_instance_color(i, Color(v * (1.0 + warm), v, v * (1.0 - warm * 1.5), 1.0))
			tree.bind_instance(mm, i)


## マップ外周の飾りの木など、切れない木を MultiMesh で並べるときにも同じ色ムラを付ける。
static func random_tint(rng: RandomNumberGenerator) -> Color:
	var v := rng.randf_range(0.8, 1.1)
	var warm := rng.randf_range(-0.06, 0.08)
	return Color(v * (1.0 + warm), v, v * (1.0 - warm * 1.5), 1.0)
