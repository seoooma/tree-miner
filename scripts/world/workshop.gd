class_name Workshop
extends Node3D
## 工房。出荷場の右隣にある屋根のない作業場で、左に材料置き場・中央に作業台・右に品物置き場が横一列に並ぶ。
## - 強化『工房』Lv1で開放。出荷場に置かれた板（炭は若木の丸太）のうち、作る品に選んだ木だけを
##   工房のコンベア（出荷場の荷台の手前を通る）で受け取る。選んでいない木はこれまでどおりトラックで売れる
## - 材料が count 個そろうと1つの品を作る（作る時間 = レシピの time / 強化『工房』の個/秒）
## - できた品は品物置き場に積まれ、販売のトラックが板・丸太と同じように積んでいく（売値は材料より高い）
## - 材料は input_cap 個まで溜める。超えた分は出荷場で待つ（作るのが追いつかないと出荷場に溜まって見える）

const ROW_Z := ShipDock.DECK_Z
const INPUT_PILE_OFFSET := Vector3(-2.3, 0, ROW_Z)
const BENCH_OFFSET := Vector3(0, 0, ROW_Z)
const GOODS_PILE_OFFSET := Vector3(2.45, 0, ROW_Z)
const DECK_Y := 0.08
## 出荷場の位置から見た工房の位置（main.gd で使う）
const FROM_DOCK := Vector3(8.6, 0, 0)

var dock: ShipDock
## 工房に届いた材料（"plank:pine" / "log:sapling"）
var inbox: Array[String] = []
## できた品（レシピの id）。販売のトラックに積まれるまで品物置き場に積む
var goods: Array[String] = []
## 出荷場 → 工房のコンベア
var belt: Conveyor

## 作っている品（レシピの id。"" = 何も作っていない）と進み具合（0..1）
var _making := ""
var _progress := 0.0
var _root: Node3D
var _body: StaticBody3D
## 作業台の手前の地面の文字（「工房」と材料・品物の数）
var _title: Label3D
var _sub: Label3D
var _input_pile: ItemPile
var _goods_pile: ItemPile
var _work_root: Node3D
var _hammer: Node3D
var _hammer_t := 0.0


func _ready() -> void:
	_root = Node3D.new()
	add_child(_root)
	_build(_root)
	for entry in GameState.stock.get("workshop_in", []):
		if _parse(str(entry)).size() == 2:
			inbox.append(str(entry))
	for id in GameState.stock.get("workshop_goods", []):
		if not GameData.recipe_def(str(id)).is_empty():
			goods.append(str(id))
	GameState.saving.connect(_on_saving)
	GameState.upgrade_changed.connect(func(_id: String, _level: int) -> void: _refresh())
	_build_belt()
	_refresh()
	_rebuild_input()
	_rebuild_goods()


func _on_saving() -> void:
	var ids := inbox.duplicate()
	if belt:
		ids.append_array(belt.ids_in_flight())
	GameState.stock["workshop_in"] = ids
	GameState.stock["workshop_goods"] = goods.duplicate()


func is_unlocked() -> bool:
	return GameState.level("workshop") > 0


## "plank:pine" → ["plank", "pine"]。形が違えば空
static func _parse(entry: String) -> Array:
	var parts := entry.split(":")
	if parts.size() != 2 or not parts[0] in ["plank", "log"] or GameData.tree_def(parts[1]).is_empty():
		return []
	return [parts[0], parts[1]]


func _refresh() -> void:
	var on := is_unlocked()
	_root.visible = on
	# 開放するまでは作業台にぶつからない（自動移動の経路探索でもよけない）
	_body.collision_layer = 1 if on else 0
	if on:
		_body.add_to_group("nav_boxes")
	elif _body.is_in_group("nav_boxes"):
		_body.remove_from_group("nav_boxes")
	if belt:
		belt.set_active(on)
	set_process(on)


func _build(root: Node3D) -> void:
	# 当たり判定は作業台だけ
	var body := StaticBody3D.new()
	_body = body
	body.collision_layer = 1
	body.position = BENCH_OFFSET
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 1.1, 1.0)
	shape.shape = box
	shape.position.y = 0.55
	body.add_child(shape)
	body.set_meta("nav_size", Vector2(box.size.x, box.size.z))
	root.add_child(body)
	_hammer = build_bench(root)

	_input_pile = ItemPile.new(func(id: String) -> MeshInstance3D: return _material_mesh(id))
	_input_pile.cols = 2
	_input_pile.rows = 3
	_input_pile.step = Vector3(0.86, 0, 0.33)
	_input_pile.layer_h = 0.17
	_input_pile.base_y = 0.09
	_input_pile.position = INPUT_PILE_OFFSET + Vector3(0, DECK_Y, 0)
	root.add_child(_input_pile)
	_goods_pile = ItemPile.new(func(id: String) -> MeshInstance3D:
		var m := goods_mesh(id)
		m.scale = Vector3.ONE * 1.3
		return m)
	_goods_pile.cols = 2
	_goods_pile.rows = 2
	_goods_pile.step = Vector3(0.8, 0, 0.7)
	_goods_pile.layer_h = 0.66
	_goods_pile.base_y = 0.0
	_goods_pile.position = GOODS_PILE_OFFSET + Vector3(0, DECK_Y, 0)
	root.add_child(_goods_pile)
	_title = Zone._flat_label(Vector3(0.4, 0.05, ROW_Z + 1.75), 96, Zone.TITLE_PX * 0.8)
	_title.text = "工房"
	root.add_child(_title)
	_sub = Zone._flat_label(Vector3(0.4, 0.05, ROW_Z + 2.45), 72, Zone.SUB_PX)
	root.add_child(_sub)
	_work_root = Node3D.new()
	_work_root.position = BENCH_OFFSET + Vector3(0, DECK_Y + 0.82, 0.05)
	root.add_child(_work_root)


## 工房の見た目（板敷きの床・作業台・道具・看板）。強化画面のサムネイルでも使う。振り下ろす金づちを返す
static func build_bench(root: Node3D) -> Node3D:
	root.add_child(Fx.box(Vector3(7.0, DECK_Y, 1.7), Color("#c99a5e"), Vector3(0, DECK_Y * 0.5, ROW_Z), "wood"))
	for i in 15:
		root.add_child(Fx.box(Vector3(0.03, 0.02, 1.7), Color("#9a7040"), Vector3(-3.5 + i * 0.5, DECK_Y + 0.005, ROW_Z)))
	var bench := Node3D.new()
	bench.position = BENCH_OFFSET + Vector3(0, DECK_Y, 0)
	root.add_child(bench)
	# 厚い天板の木の作業台と、緑の万力・道具掛け
	var top := Color("#a8743f")
	bench.add_child(Fx.box(Vector3(1.9, 0.14, 0.9), top, Vector3(0, 0.72, 0), "wood"))
	for x in [-0.82, 0.82]:
		for z in [-0.36, 0.36]:
			bench.add_child(Fx.box(Vector3(0.12, 0.66, 0.12), top.darkened(0.25), Vector3(x, 0.33, z), "wood"))
	bench.add_child(Fx.box(Vector3(1.7, 0.06, 0.7), top.darkened(0.2), Vector3(0, 0.22, 0), "wood"))
	var vise := Color("#3f9a5a")
	bench.add_child(Fx.box(Vector3(0.26, 0.2, 0.3), vise, Vector3(-0.78, 0.89, 0.2), "metal"))
	bench.add_child(Fx.box(Vector3(0.05, 0.05, 0.4), Color("#cfd6de"), Vector3(-0.78, 0.9, 0.48), "metal"))
	# 奥の道具掛け（板にのこぎり・定規）
	bench.add_child(Fx.box(Vector3(1.6, 0.9, 0.06), Color("#8a5a32"), Vector3(0, 1.25, -0.5), "wood"))
	bench.add_child(Fx.box(Vector3(0.5, 0.16, 0.02), Color("#e6eaee"), Vector3(-0.4, 1.4, -0.46), "metal"))
	bench.add_child(Fx.box(Vector3(0.06, 0.5, 0.02), Color("#ffc23d"), Vector3(0.35, 1.25, -0.46)))
	bench.add_child(Fx.box(Vector3(0.3, 0.06, 0.02), Color("#e8573a"), Vector3(0.6, 1.5, -0.46)))
	# 金づち（作っている間は振り下ろす）
	var hammer := Node3D.new()
	hammer.position = Vector3(0.55, 0.8, 0.15)
	bench.add_child(hammer)
	hammer.add_child(Fx.box(Vector3(0.05, 0.05, 0.42), Color("#8a5a32"), Vector3(0, 0.1, 0.2), "wood"))
	hammer.add_child(Fx.box(Vector3(0.18, 0.08, 0.08), Color("#59616b"), Vector3(0, 0.1, 0.42), "metal"))
	var signboard := Props.signboard("工房", Color("#3f9a5a"))
	# 看板は右端（奥は販売のトラックが走り去る道なので置かない）
	signboard.position = Vector3(3.9, 0, ROW_Z + 0.2)
	signboard.rotation_degrees.y = -70.0
	root.add_child(signboard)
	return hammer


## 出荷場の荷台の手前を通って、出荷場の板の山の前から工房の材料置き場までつなぐコンベア
func _build_belt() -> void:
	if dock == null:
		return
	var from := dock.global_position + ShipDock.STOCK_PILE_OFFSET - global_position
	var front_z := ROW_Z + 1.25
	var path: Array[Vector3] = [Vector3(from.x + 0.2, 0, front_z), Vector3(INPUT_PILE_OFFSET.x, 0, front_z), Vector3(INPUT_PILE_OFFSET.x, 0, ROW_Z + 0.55)]
	belt = Conveyor.new()
	belt.path = path
	belt.rate_source = func() -> float: return float(GameData.workshop.get("feed_rate", 2.0))
	belt.take_source = func() -> String: return dock.take_for_workshop()
	belt.room_source = func(n: int) -> bool: return inbox.size() + n < int(GameData.workshop.get("input_cap", 12))
	belt.deliver = func(id: String) -> void:
		inbox.append(id)
		_rebuild_input()
	belt.make_mesh = func(id: String) -> Node3D: return _material_mesh(id)
	add_child(belt)


static func _material_mesh(entry: String) -> MeshInstance3D:
	var p := _parse(entry)
	if p.is_empty():
		return Sawmill._plank_mesh("")
	if p[0] == "log":
		return Sawmill._pile_log(p[1])
	return Sawmill._plank_mesh(p[1])


## できた品の見た目（木の色で塗る）。工房の品物置き場・トラックの荷台・注文の一覧で使う
static func goods_mesh(recipe_id: String) -> MeshInstance3D:
	var r := GameData.recipe_def(recipe_id)
	var def := GameData.tree_def(str(r.get("tree", "")))
	var wood := LogDrop.end_color(def)
	var dark := LogDrop.grade_color(def).darkened(0.1)
	var parts: Array = []
	var b := func(size: Vector3, pos: Vector3, color: Color) -> void:
		var m := BoxMesh.new()
		m.size = size
		parts.append([m, Transform3D(Basis.IDENTITY, pos), color])
	match recipe_id:
		"charcoal":
			# 炭俵（黒い炭がのぞく、わらの俵）
			b.call(Vector3(0.5, 0.36, 0.4), Vector3(0, 0.18, 0), Color("#c9a86a"))
			b.call(Vector3(0.52, 0.06, 0.42), Vector3(0, 0.1, 0), Color("#8a6a3a"))
			b.call(Vector3(0.52, 0.06, 0.42), Vector3(0, 0.28, 0), Color("#8a6a3a"))
			b.call(Vector3(0.36, 0.08, 0.28), Vector3(0, 0.38, 0), Color("#2b2624"))
		"shelf":
			b.call(Vector3(0.06, 0.5, 0.3), Vector3(-0.24, 0.25, 0), wood)
			b.call(Vector3(0.06, 0.5, 0.3), Vector3(0.24, 0.25, 0), wood)
			for y in [0.03, 0.25, 0.47]:
				b.call(Vector3(0.54, 0.05, 0.3), Vector3(0, y, 0), wood.darkened(0.08))
			b.call(Vector3(0.54, 0.5, 0.02), Vector3(0, 0.25, -0.15), dark)
		"chair":
			b.call(Vector3(0.4, 0.06, 0.4), Vector3(0, 0.24, 0), wood)
			for x in [-0.16, 0.16]:
				for z in [-0.16, 0.16]:
					b.call(Vector3(0.05, 0.24, 0.05), Vector3(x, 0.12, z), dark)
			b.call(Vector3(0.4, 0.3, 0.05), Vector3(0, 0.42, -0.18), wood.darkened(0.08))
		"table":
			b.call(Vector3(0.56, 0.06, 0.44), Vector3(0, 0.3, 0), wood)
			for x in [-0.23, 0.23]:
				for z in [-0.17, 0.17]:
					b.call(Vector3(0.06, 0.3, 0.06), Vector3(x, 0.15, z), dark)
		_:
			# たんす（引き出し3段と取っ手）
			b.call(Vector3(0.5, 0.48, 0.34), Vector3(0, 0.24, 0), wood)
			for y in [0.09, 0.24, 0.39]:
				b.call(Vector3(0.44, 0.12, 0.02), Vector3(0, y, 0.17), wood.lightened(0.12))
				b.call(Vector3(0.1, 0.03, 0.02), Vector3(0, y, 0.185), Color("#d8b04a"))
	var mi := MeshInstance3D.new()
	mi.mesh = Fx.merged_flat("goods/" + recipe_id, parts)
	return mi


func _process(delta: float) -> void:
	if _making == "":
		_making = _next_recipe()
		_progress = 0.0
		_show_work()
	if _making != "":
		var r := GameData.recipe_def(_making)
		_progress += GameState.value("workshop") * delta / maxf(0.1, float(r.get("time", 1.0)))
		_hammer_t += delta
		_hammer.rotation_degrees.x = -50.0 * absf(sin(_hammer_t * 7.0))
		if _progress >= 1.0:
			_finish(r)
	else:
		_hammer.rotation_degrees.x = 0.0


## 材料がそろっていて、作る設定になっている品（並び順で最初のもの）
func _next_recipe() -> String:
	for r in GameData.recipes:
		var id := str(r["id"])
		if GameState.is_recipe_on(id) and inbox.count("%s:%s" % [r["input"], r["tree"]]) >= int(r.get("count", 1)):
			return id
	return ""


func _finish(r: Dictionary) -> void:
	var key := "%s:%s" % [r["input"], r["tree"]]
	for i in int(r.get("count", 1)):
		var at := inbox.rfind(key)
		if at >= 0:
			inbox.remove_at(at)
	goods.append(str(r["id"]))
	_making = ""
	_progress = 0.0
	_rebuild_input()
	_rebuild_goods()
	_show_work()
	var at := global_position + BENCH_OFFSET + Vector3(0, 1.0, 0.2)
	Vfx.wood_chips(self, at, Vector3(0.6, 0, 0.5), [LogDrop.end_color(GameData.tree_def(str(r["tree"]))), Color("#d9b47a")], 6)
	Audio.play("drop", -12.0, 1.2)


## 作業台の上に作りかけの品を出す
func _show_work() -> void:
	for child in _work_root.get_children():
		child.queue_free()
	if _making != "":
		var m := goods_mesh(_making)
		m.scale = Vector3.ONE * 0.8
		_work_root.add_child(m)


## 品を1つ取り出す（販売のトラックに積む）。無ければ空文字
func take_goods() -> String:
	if goods.is_empty():
		return ""
	var id: String = goods.pop_back()
	_rebuild_goods()
	return id


func goods_top() -> Vector3:
	return _goods_pile.top_global()


func _rebuild_input() -> void:
	_input_pile.show_items(inbox)
	_update_sub()


func _rebuild_goods() -> void:
	_goods_pile.show_items(goods)
	_update_sub()


func _update_sub() -> void:
	if _sub:
		_sub.text = "材料 %d ・ 品物 %d" % [inbox.size(), goods.size()]

