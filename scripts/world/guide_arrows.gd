class_name GuideArrows
extends Node3D
## 次に向かう場所へ、地面に緑の三角（シェブロン）を点線のように並べて案内する。ゆっくり流れる。
## - 積荷が満杯: いちばん近い届け先（製材所の投入口か、川の積み込み枠）。板を持っていれば出荷場
## - 拠点にいて手ぶらのとき: 製材所の板（板のコンベアが未開放なら）、川の集積所の丸太（集積所コンベアが未開放なら）
## - それ以外: いちばん近い木
## - 自動移動中: 行き先までの経路に沿って並べる
## 案内先は HUD の画面端インジケーター（goal / goal_kind）でも使う。表示だけでゲームの処理には影響しない。

const COLOR := Color("#6BD13A")
const SPACING := 1.0
const MAX_ARROWS := 14
const SCROLL_SPEED := 0.7

var player: Player
var sawmill: Sawmill
var dock: Node3D
var river: LogLine

## 案内先（無ければ Vector3.INF）と種類（"home" = 届け先 / "tree" = 木）
var goal := Vector3.INF
var goal_kind := "tree"

var _mm: MultiMesh
var _search_timer := 0.0
var _scroll := 0.0
var _tree_goal: ChoppableTree


func _ready() -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = _chevron_mesh()
	_mm.instance_count = MAX_ARROWS
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.material_override = _material()
	# MultiMesh の範囲は最初の配置で決まるので、マップ全体を覆う大きさにしておく
	mmi.custom_aabb = AABB(Vector3(-200, -1, -200), Vector3(400, 2, 400))
	add_child(mmi)


func _process(delta: float) -> void:
	if player == null or player.vehicle != null:
		goal = Vector3.INF
		_mm.visible_instance_count = 0
		return
	_scroll = fmod(_scroll + delta * SCROLL_SPEED, SPACING)
	if player.is_auto_moving():
		_search_timer = 0.0
		var path := player.auto_path
		if path.size() < 2:
			goal = Vector3.INF
			_mm.visible_instance_count = 0
			return
		goal = path[-1]
		goal_kind = "home"
		var pts := PackedVector3Array([player.global_position])
		for i in range(maxi(1, player._auto_index), path.size()):
			pts.append(path[i])
		_layout_path(pts, 1.0)
		return
	_search_timer -= delta
	if _search_timer <= 0.0:
		_search_timer = 0.25
		_pick_goal()
	if _tree_goal and goal_kind == "tree":
		if not _tree_goal.alive:
			_search_timer = 0.0
		goal = _tree_goal.global_position
	_layout()


func _pick_goal() -> void:
	var stack := player.stack
	_tree_goal = null
	if stack.count("plank") > 0 and dock and GameState.level("sawmill") > 0:
		goal = dock.global_position
		goal_kind = "home"
	elif stack.is_full() and sawmill:
		goal = LoadingPoint.nearest_dropoff(self, player.global_position, sawmill)
		goal_kind = "home"
	elif stack.is_empty() and player.global_position.z > 0.0 and _manual_pickup() != Vector3.INF:
		goal = _manual_pickup()
		goal_kind = "home"
	else:
		_tree_goal = _nearest_tree()
		goal = _tree_goal.global_position if _tree_goal else Vector3.INF
		goal_kind = "tree"


## 手で運ぶ必要があるもの（コンベアが未開放の工程）の受け取り場所。無ければ Vector3.INF
func _manual_pickup() -> Vector3:
	if sawmill and dock and GameState.level("plank_belt") == 0 and not sawmill.output.is_empty():
		return sawmill.output_position()
	if river and river.is_active() and not river.conveyor_active() and river.yard_count() > 0:
		return river.yard_pad_position()
	return Vector3.INF


func _nearest_tree() -> ChoppableTree:
	var best: ChoppableTree = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group("trees"):
		var t := node as ChoppableTree
		if not t.alive or not GameState.is_area_unlocked(t.area_index):
			continue
		var d := Fx.xz_distance(t.global_position, player.global_position)
		if d < best_d:
			best_d = d
			best = t
	return best


func _layout() -> void:
	if goal == Vector3.INF:
		_mm.visible_instance_count = 0
		return
	var from := player.global_position
	var to_goal := Vector3(goal.x - from.x, 0, goal.z - from.z)
	var dist := to_goal.length()
	var start := 1.0
	var end := dist - (1.2 if goal_kind == "tree" else 1.6)
	if end <= start:
		_mm.visible_instance_count = 0
		return
	var dir := to_goal / dist
	var arrow_basis := Basis.looking_at(-dir, Vector3.UP)
	var count := 0
	var d := start + _scroll
	while d < end and count < MAX_ARROWS:
		# 両端は小さくしてふわっと出入りさせる
		var fade := clampf(minf(d - start, end - d) / 0.8, 0.0, 1.0)
		var s := 0.35 + 0.65 * fade
		_mm.set_instance_transform(count, Transform3D(arrow_basis.scaled(Vector3.ONE * s), Vector3(from.x, 0.05, from.z) + dir * d))
		count += 1
		d += SPACING
	_mm.visible_instance_count = count


## 折れ線 pts に沿って矢印を並べる（最後の点の end_margin 手前まで）
func _layout_path(pts: PackedVector3Array, end_margin: float) -> void:
	var total := 0.0
	for i in range(1, pts.size()):
		total += Fx.xz_distance(pts[i - 1], pts[i])
	var start := 1.0
	var end := total - end_margin
	var count := 0
	var d := start + _scroll
	var seg := 1
	var seg_start := 0.0
	while d < end and count < MAX_ARROWS and seg < pts.size():
		var a := Vector3(pts[seg - 1].x, 0, pts[seg - 1].z)
		var b := Vector3(pts[seg].x, 0, pts[seg].z)
		var seg_len := a.distance_to(b)
		if d > seg_start + seg_len or seg_len < 0.01:
			seg_start += seg_len
			seg += 1
			continue
		var dir := (b - a) / seg_len
		var fade := clampf(minf(d - start, end - d) / 0.8, 0.0, 1.0)
		var s := 0.35 + 0.65 * fade
		var pos := a + dir * (d - seg_start)
		_mm.set_instance_transform(count, Transform3D(Basis.looking_at(-dir, Vector3.UP).scaled(Vector3.ONE * s), Vector3(pos.x, 0.05, pos.z)))
		count += 1
		d += SPACING
	_mm.visible_instance_count = count


## 進行方向（-Z → ローカル +Z を前とする）を向いた三角。濃い縁取り付き。
static func _chevron_mesh() -> Mesh:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var dark := Color(0.08, 0.2, 0.05)
	for layer in 2:
		var grow := 0.07 if layer == 0 else 0.0
		var y := 0.0 if layer == 0 else 0.004
		var c := dark if layer == 0 else COLOR
		var tip := Vector3(0, y, 0.32 + grow * 1.6)
		var left := Vector3(-0.3 - grow, y, -0.2 - grow)
		var right := Vector3(0.3 + grow, y, -0.2 - grow)
		for v in [tip, right, left]:
			verts.append(v)
			colors.append(c)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = colors
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static func _material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
