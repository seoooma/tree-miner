class_name ItemPile
extends Node3D
## 置き場に積んだ丸太・板の山。数の分だけ1つずつ積む（見た目の上限なし。表示の数と山の数がいつも同じ）。
## 同じ種類の見た目は MultiMesh でまとめて描くので、数百個でも軽い。
##
## 並べ方: 1段に cols x rows 個（cols は step.x、rows は step.z の間隔）、段は layer_h ずつ上へ。
## 奇数段は stagger だけずらして、俵積みのように互い違いにする。

var cols := 4
var rows := 1
var step := Vector3(0.23, 0.0, 0.32)
var layer_h := 0.2
var base_y := 0.12
var stagger := Vector3.ZERO
## 段ごとに少しだけ回す角度（板を互い違いに見せる）
var layer_twist_deg := 0.0
## 木のID → 1個分の見た目（MeshInstance3D。mesh・material_override・向き・拡大を使う）
var make_item: Callable

var _mmis: Dictionary = {}  # 木のID -> MultiMeshInstance3D
var _protos: Dictionary = {}  # 木のID -> Transform3D（1個分の向き・拡大）
var _count := 0


func _init(p_make_item: Callable = Callable()) -> void:
	make_item = p_make_item


## index 番目の置き場所（このノードから見た位置）
func slot(index: int) -> Vector3:
	var per_layer := maxi(1, cols * rows)
	var layer := floori(index / float(per_layer))
	var cell := index % per_layer
	var col := cell % cols
	var row := floori(cell / float(cols))
	var p := Vector3((col - (cols - 1) * 0.5) * step.x, base_y + layer * layer_h, (row - (rows - 1) * 0.5) * step.z)
	if layer % 2 == 1:
		p += stagger
	return p


## 次に置く1個の場所（飛んでくる演出の行き先）
func top_global() -> Vector3:
	return to_global(slot(_count))


## 並びの通りに積み直す。ids は下から順。
func show_items(ids: Array) -> void:
	_count = ids.size()
	var per_id: Dictionary = {}
	for i in ids.size():
		var id := str(ids[i])
		if not per_id.has(id):
			per_id[id] = []
		var layer := floori(i / float(maxi(1, cols * rows)))
		var twist := deg_to_rad(layer_twist_deg if layer % 2 == 0 else -layer_twist_deg)
		(per_id[id] as Array).append(Transform3D(Basis(Vector3.UP, twist), slot(i)))
	for id in _mmis:
		if not per_id.has(id):
			(_mmis[id] as MultiMeshInstance3D).multimesh.instance_count = 0
	for id in per_id:
		var mmi := _mmi_for(id)
		var xfs: Array = per_id[id]
		var mm := mmi.multimesh
		mm.instance_count = xfs.size()
		var proto: Transform3D = _protos[id]
		for k in xfs.size():
			mm.set_instance_transform(k, (xfs[k] as Transform3D) * proto)


func _mmi_for(id: String) -> MultiMeshInstance3D:
	if _mmis.has(id):
		return _mmis[id]
	var proto: MeshInstance3D = make_item.call(id)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = proto.mesh
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = proto.material_override
	add_child(mmi)
	_mmis[id] = mmi
	_protos[id] = proto.transform
	proto.free()
	return mmi


## 山に積んで見せている数（テスト用）
func shown_count() -> int:
	var n := 0
	for id in _mmis:
		n += (_mmis[id] as MultiMeshInstance3D).multimesh.instance_count
	return n
