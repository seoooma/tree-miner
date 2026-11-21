class_name LogDrop
extends Node3D
## 木を倒したときに地面に落ちる丸太。運搬者（プレイヤー・運搬役の伐採員・運搬車）が近づくと吸い寄せられて拾われる。

const SPAWN_SEC := 0.35
## 丸太の長さ。地面・背中・山・荷台・コンベアのどこでも同じ大きさで見せる（場所ごとに拡大しない）
const LOG_LENGTH := 0.9

var tree_id := ""
var collected := false
## 運搬役の伐採員が同じ丸太を取り合わないための予約
var claimed_by: Node = null

var _age := 0.0


## 倒れた木の周りに丸太をばらまく。dir を渡すと倒れた方向（幹の上）に多めに落ちる。
static func spawn_from_tree(tree: Node3D, p_tree_id: String, dir := Vector3.ZERO) -> void:
	var parent := tree.get_parent()
	if parent == null:
		return
	var max_on_map := int(GameData.drops.get("max_on_map", 300))
	var count := randi_range(int(GameData.drops.get("min", 2)), int(GameData.drops.get("max", 4)))
	count = mini(count, max_on_map - tree.get_tree().get_nodes_in_group("drops").size())
	var scatter := float(GameData.drops.get("scatter", 1.6))
	for i in count:
		var drop := LogDrop.new()
		drop.tree_id = p_tree_id
		parent.add_child(drop)
		var target: Vector3
		if dir != Vector3.ZERO:
			var along := randf_range(0.7, scatter + 0.6)
			var side := dir.cross(Vector3.UP) * randf_range(-0.6, 0.6)
			target = tree.global_position + dir * along + side
		else:
			var angle := randf() * TAU
			var dist := randf_range(0.6, scatter)
			target = tree.global_position + Vector3(cos(angle) * dist, 0, sin(angle) * dist)
		target.y = 0.1
		drop.global_position = target + Vector3(0, 1.0, 0) - dir * 0.5
		drop._land(target)


## 運搬者の近くにある丸太を、空きがある分だけ拾う。拾った数を返す。
static func collect_near(carrier: Node3D, stack: CarryStack, radius: float) -> int:
	var picked := 0
	for node in carrier.get_tree().get_nodes_in_group("drops"):
		if stack.is_full():
			break
		var drop := node as LogDrop
		if drop.collected or drop._age < SPAWN_SEC:
			continue
		if Fx.xz_distance(drop.global_position, carrier.global_position) > radius:
			continue
		stack.add({"kind": "log", "tree": drop.tree_id})
		drop._fly_to(carrier)
		picked += 1
	if picked > 0 and carrier.is_in_group("player") or picked > 0 and carrier is Machine:
		Audio.play("pickup", -6.0, 1.0 + 0.05 * stack.size() / maxf(1.0, stack.capacity()) * 6.0)
	return picked


func _ready() -> void:
	add_to_group("drops")
	add_child(LogDrop.make_log_mesh(tree_id, randf() * 180.0))


## 丸太の見た目（樹皮の円柱＋両端の木口）。積荷の表示でも使う。
## 木の種類がわかるように、木口の色を種類ごとに変え、等級の色（balance.json の grade_color）を
## 真ん中の細い帯と木口の中心の小さな印に塗る（材木置き場の色付けと同じ）。樹皮は立ち木の幹と同じ色。
static func make_log_mesh(p_tree_id: String, yaw_deg := 0.0) -> Node3D:
	var def := GameData.tree_def(p_tree_id)
	var bark := ChoppableTree.bark_color(def) if not def.is_empty() else Color(0.55, 0.36, 0.2, 0.0)
	var end_c := end_color(def)
	var grade := grade_color(def)
	var along := Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO)
	var mesh := _log_mesh("log/" + p_tree_id, [
		[_cyl(0.11, LOG_LENGTH, 10), along, bark],
		# 木口は樹皮と同じ長さの面に薄く貼る（端が角張った円柱に見えるように）
		[_cyl(0.092, LOG_LENGTH + 0.006, 10), along, Color(end_c.r, end_c.g, end_c.b, 0.5)],
		# 年輪（木口の内側の少し濃い輪）
		[_cyl(0.064, LOG_LENGTH + 0.009, 10), along, Color(end_c.darkened(0.14).r, end_c.darkened(0.14).g, end_c.darkened(0.14).b, 0.5)],
		[_cyl(0.05, LOG_LENGTH + 0.01, 10), along, Color(end_c.r, end_c.g, end_c.b, 0.5)],
		[_cyl(0.026, LOG_LENGTH + 0.012, 6), along, Color(grade.r, grade.g, grade.b, 0.5)],
		[_cyl(0.114, 0.05, 10), along, Color(grade.r, grade.g, grade.b, 0.0)],
	])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Mats.tree(false)
	mi.rotation_degrees.y = yaw_deg
	return mi


## 木口（切り口・板の色）
static func end_color(def: Dictionary) -> Color:
	return Color(def.get("end_color", "#e8c890"))


## 等級の色（丸太の帯・板の端に塗る）
static func grade_color(def: Dictionary) -> Color:
	return Color(def.get("grade_color", "#ffffff"))


## 丸太のメッシュ（Fx.merged と同じ頂点カラーの合成）。法線は、側面は円柱の外向き、木口は軸の向きにして、
## 端の角を丸くぼかさずにくっきり見せる（法線を平均すると角が丸く見えて丸太らしくない）。
static func _log_mesh(key: String, parts: Array) -> Mesh:
	return Fx._cached(key, func() -> Mesh:
		var verts := PackedVector3Array()
		var colors := PackedColorArray()
		for part in parts:
			var prim: Mesh = part[0]
			var xf: Transform3D = part[1]
			var arrays := prim.surface_get_arrays(0)
			var pv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for i in (idx if not idx.is_empty() else range(pv.size())):
				verts.append(xf * pv[i])
				colors.append(part[2])
		var normals := PackedVector3Array()
		normals.resize(verts.size())
		for t in range(0, verts.size(), 3):
			var face := (verts[t + 2] - verts[t]).cross(verts[t + 1] - verts[t]).normalized()
			for k in 3:
				var v := verts[t + k]
				if absf(face.x) > 0.9:
					normals[t + k] = Vector3(signf(v.x), 0, 0)
				else:
					normals[t + k] = Vector3(0, v.y, v.z).normalized()
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = normals
		arr[Mesh.ARRAY_COLOR] = colors
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m)


static func _cyl(r: float, h: float, seg: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


func _process(delta: float) -> void:
	_age += delta


func _land(target: Vector3) -> void:
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "global_position:x", target.x, SPAWN_SEC)
	tween.tween_property(self, "global_position:z", target.z, SPAWN_SEC)
	# ポンと飛び出して、地面で2回小さく跳ねる
	var up := create_tween()
	up.tween_property(self, "global_position:y", 1.6, SPAWN_SEC * 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	up.tween_property(self, "global_position:y", target.y, SPAWN_SEC * 0.6).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	up.tween_callback(func() -> void: Vfx.dust(self, global_position, Color("#d9cdb0"), 2, 0.4, 0.8, true, 0.6))
	up.tween_property(self, "global_position:y", target.y + 0.35, 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	up.tween_property(self, "global_position:y", target.y, 0.12).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	up.tween_property(self, "global_position:y", target.y + 0.1, 0.07).set_ease(Tween.EASE_OUT)
	up.tween_property(self, "global_position:y", target.y, 0.07).set_ease(Tween.EASE_IN)
	var spin := create_tween()
	spin.tween_property(self, "rotation:y", rotation.y + randf_range(-2.5, 2.5), SPAWN_SEC + 0.3).set_ease(Tween.EASE_OUT)


func _fly_to(carrier: Node3D) -> void:
	collected = true
	remove_from_group("drops")
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "global_position", carrier.global_position + Vector3(0, 1.0, 0), 0.15)
	tween.tween_property(self, "scale", Vector3.ONE * 0.4, 0.15)
	tween.chain().tween_callback(queue_free)
