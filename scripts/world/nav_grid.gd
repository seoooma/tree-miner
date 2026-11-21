class_name NavGrid
extends RefCounted
## プレイヤーの自動移動に使う、地面を細かいマス目に分けた経路探索（AStarGrid2D）。
## 通れないマス: 生えている木の幹、"nav_boxes" グループのノード（柵・製材台・機械。meta "nav_size" = 幅x奥行き）。
## 木は切られたり生え直したりするので、経路を引き直すたびに refresh() で塗り直す。

const CELL := 0.25
## 体の太さ＋少しの余裕（これより近くは通らない）
const CLEARANCE := 0.42

var _astar := AStarGrid2D.new()
var _origin := Vector2.ZERO  # マス (0, 0) の左上の XZ
var _marked: Array[Vector2i] = []


## rect: 歩ける範囲（XZ。x = X、y = Z）
func _init(rect: Rect2) -> void:
	_origin = rect.position
	_astar.region = Rect2i(0, 0, ceili(rect.size.x / CELL), ceili(rect.size.y / CELL))
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()


## 障害物を塗り直す。ignore（向かう先の機械など）は通れる扱いにする
func refresh(tree: SceneTree, ignore: Node = null) -> void:
	for c in _marked:
		_astar.set_point_solid(c, false)
	_marked.clear()
	for node in tree.get_nodes_in_group("trees"):
		var t := node as ChoppableTree
		if t.alive:
			_mark_circle(t.global_position, t.radius + CLEARANCE)
	for node in tree.get_nodes_in_group("nav_boxes"):
		var n := node as Node3D
		if n == ignore or not n.is_inside_tree() or n.is_queued_for_deletion():
			continue
		_mark_box(n.global_transform, n.get_meta("nav_size", Vector2.ONE) as Vector2)


## from から to への経路（XZ の折れ線、y = 0）。行き着けなければ、いちばん近づける所までの経路を返す
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var start := _nearest_free(_cell(from))
	var goal_cell := _cell(to)
	var goal := _nearest_free(goal_cell)
	if start == Vector2i(-1, -1) or goal == Vector2i(-1, -1):
		return out
	var ids := _astar.get_id_path(start, goal, true)
	if ids.is_empty():
		return out
	var pts: Array[Vector3] = [Vector3(from.x, 0, from.z)]
	for i in range(1, ids.size()):
		pts.append(_world(ids[i]))
	# 行き先のマスがそのまま通れて、最後まで行けたなら、行き先ちょうどで止まる
	if ids[-1] == goal and goal == goal_cell:
		pts[-1] = Vector3(to.x, 0, to.z)
	# 見通せる点は飛ばして、まっすぐ歩けるようにする
	var i := 0
	out.append(pts[0])
	while i < pts.size() - 1:
		var j := pts.size() - 1
		while j > i + 1 and not _clear_line(pts[i], pts[j]):
			j -= 1
		out.append(pts[j])
		i = j
	return out


func is_blocked(pos: Vector3) -> bool:
	var c := _cell(pos)
	return not _astar.is_in_boundsv(c) or _astar.is_point_solid(c)


# ---- 内部 ----

func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori((p.x - _origin.x) / CELL), floori((p.z - _origin.y) / CELL))


func _world(c: Vector2i) -> Vector3:
	return Vector3(_origin.x + (c.x + 0.5) * CELL, 0, _origin.y + (c.y + 0.5) * CELL)


func _set_solid(c: Vector2i) -> void:
	if _astar.is_in_boundsv(c) and not _astar.is_point_solid(c):
		_astar.set_point_solid(c, true)
		_marked.append(c)


func _mark_circle(center: Vector3, r: float) -> void:
	var lo := _cell(center - Vector3(r, 0, r))
	var hi := _cell(center + Vector3(r, 0, r))
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var w := _world(Vector2i(x, y))
			if Vector2(w.x - center.x, w.z - center.z).length() <= r:
				_set_solid(Vector2i(x, y))


## 向きのある箱（幅 size.x・奥行き size.y）を体の太さぶん広げて塗る
func _mark_box(xf: Transform3D, size: Vector2) -> void:
	var hx := size.x * 0.5 + CLEARANCE
	var hz := size.y * 0.5 + CLEARANCE
	var reach := Vector2(hx, hz).length()
	var center := xf.origin
	var inv := xf.affine_inverse()
	var lo := _cell(center - Vector3(reach, 0, reach))
	var hi := _cell(center + Vector3(reach, 0, reach))
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var w := _world(Vector2i(x, y))
			w.y = center.y
			var local := inv * w
			if absf(local.x) <= hx and absf(local.z) <= hz:
				_set_solid(Vector2i(x, y))


## c が通れなければ、まわりでいちばん近い通れるマス（無ければ (-1, -1)）
func _nearest_free(c: Vector2i) -> Vector2i:
	var r := _astar.region
	c = Vector2i(clampi(c.x, 0, r.size.x - 1), clampi(c.y, 0, r.size.y - 1))
	if not _astar.is_point_solid(c):
		return c
	for ring in range(1, 24):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for y in range(c.y - ring, c.y + ring + 1):
			for x in range(c.x - ring, c.x + ring + 1):
				if maxi(absi(x - c.x), absi(y - c.y)) != ring:
					continue
				var p := Vector2i(x, y)
				if _astar.is_in_boundsv(p) and not _astar.is_point_solid(p):
					var d := Vector2(p - c).length()
					if d < best_d:
						best_d = d
						best = p
		if best != Vector2i(-1, -1):
			return best
	return Vector2i(-1, -1)


func _clear_line(a: Vector3, b: Vector3) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var steps := ceili(d.length() / (CELL * 0.5))
	for s in range(1, steps):
		var p := a.lerp(b, float(s) / steps)
		if _astar.is_point_solid(_cell(p)):
			return false
	return true
