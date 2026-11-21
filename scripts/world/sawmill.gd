class_name Sawmill
extends Station
## 製材所。出荷場と同じく屋根のない作業場で、左に丸太置き場・中央に製材台・右に板置き場が横一列に並ぶ。
## 手前の左の枠で丸太を渡し、右の枠で板を受け取る。製材台の上では丸太がノコギリを通って板になるのが見える。
## - 製材ライン未開放: 投入口に置いた丸太をその場で売却する。
## - 製材ライン開放後: 丸太を板に加工し、出口に積む。板は出荷場で売る（売値 x plank_multiplier）。
##   丸太置き場・出口に置ける数に上限はなく、山にはいつも実際の数だけ積む。
##   加工は強化『製材ライン』の本/秒で1本ずつ進み、製材台の上を丸太が左から右へ流れていく。

## 受け渡しの枠（手前）。左が丸太の投入口、右が板の出口
const INPUT_OFFSET := Vector3(-2.6, 0, -0.8)
const OUTPUT_OFFSET := Vector3(2.6, 0, -0.8)
## 奥の作業列（z が小さいほど森側）。丸太置き場・製材台・板置き場の位置
const ROW_Z := -3.6
const BENCH_OFFSET := Vector3(0, 0, ROW_Z)
const OUTPUT_PILE_OFFSET := Vector3(2.6, 0, ROW_Z)
## 製材台の上を丸太が流れる範囲（ノコギリは x=0）
const BENCH_FEED_X := 0.95
const DECK_Y := 0.08

var queue: Array[String] = []
var output: Array[String] = []
var _progress := 0.0

var _input_zone: Zone
var _output_zone: Zone
var _output_root: Node3D
var _output_pile: ItemPile
## 作業列の左にある、加工待ちの丸太置き場。数は queue と同じ
var _input_pile: ItemPile
const INPUT_PILE_OFFSET := Vector3(-2.45, 0, ROW_Z)
var _blade: MeshInstance3D
## 製材台の上で加工中の1本（ノコギリの手前は丸太、過ぎると板の見た目）
var _work_log: Node3D
var _work_plank: Node3D
var _work_tree := ""
## ノコギリから出るおがくず（加工中だけ出す）
var _sawdust: CPUParticles3D
var _sawdust_haze: CPUParticles3D
var _spark_timer := 1.0


func _ready() -> void:
	_build()
	queue = GameState.stock_list("sawmill_queue")
	output = GameState.stock_list("sawmill_output")
	GameState.saving.connect(func() -> void:
		GameState.stock["sawmill_queue"] = queue.duplicate()
		GameState.stock["sawmill_output"] = output.duplicate())
	GameState.upgrade_changed.connect(func(_id: String, _level: int) -> void: _refresh())
	_refresh()
	_rebuild_input()
	_rebuild_output()


## 出口の板を1枚取り出す（板のコンベア用）。無ければ空文字
func take_plank() -> String:
	if output.is_empty():
		return ""
	var id: String = output.pop_back()
	_rebuild_output()
	return id


func is_line_unlocked() -> bool:
	return GameState.level("sawmill") > 0


func input_position() -> Vector3:
	return global_position + INPUT_OFFSET


## 加工待ちの丸太置き場の位置（川の集積所からのコンベアの終点）
func input_pile_position() -> Vector3:
	return global_position + INPUT_PILE_OFFSET


func output_position() -> Vector3:
	return global_position + OUTPUT_OFFSET


## 板置き場（出口で受け取る板・板のコンベアに載る板はここから出ていく）
func output_pile_position() -> Vector3:
	return global_position + OUTPUT_PILE_OFFSET


func _pad_radius() -> float:
	return float(GameData.sawmill.get("pad_radius", 1.6))


func _build() -> void:
	# 当たり判定は製材台だけ（丸太置き場・板置き場は通り抜けられる）
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = BENCH_OFFSET
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 1.2, 1.0)
	shape.shape = box
	shape.position.y = 0.6
	body.add_child(shape)
	body.add_to_group("nav_boxes")
	body.set_meta("nav_size", Vector2(box.size.x, box.size.z))
	add_child(body)
	_blade = build_bench(self)
	# おがくずは丸太の入ってくる側（左）の手前へ吹き出す
	var blade_top := BENCH_OFFSET + Vector3(0, DECK_Y + 0.8, 0.05)
	_sawdust = Vfx.make_sawdust(Vector3(-0.8, 0.9, 0.5).normalized())
	_sawdust.position = blade_top
	_sawdust.emitting = false
	add_child(_sawdust)
	_sawdust_haze = Vfx.make_sawdust_haze(Vector3(-0.5, 0.8, 0.6).normalized())
	_sawdust_haze.position = blade_top
	_sawdust_haze.emitting = false
	add_child(_sawdust_haze)

	_input_zone = Zone.new(Vector2.ONE * _pad_radius() * 2.0, Color(0.95, 0.8, 0.3, 0.16))
	_input_zone.position = INPUT_OFFSET
	add_child(_input_zone)

	_output_root = Node3D.new()
	_output_root.position = OUTPUT_OFFSET
	add_child(_output_root)
	_output_zone = Zone.new(Vector2.ONE * _pad_radius() * 2.0, Color(0.55, 0.8, 0.95, 0.16))
	_output_root.add_child(_output_zone)
	# 板置き場: 板2枚を縦に並べ、奥行きに4枚（1段8枚）
	_output_pile = ItemPile.new(func(id: String) -> MeshInstance3D: return _plank_mesh(id))
	_output_pile.cols = 2
	_output_pile.rows = 4
	_output_pile.step = Vector3(0.86, 0, 0.33)
	_output_pile.layer_h = 0.17
	_output_pile.base_y = 0.09
	_output_pile.layer_twist_deg = 3.0
	_output_pile.position = OUTPUT_PILE_OFFSET + Vector3(0, DECK_Y, 0)
	add_child(_output_pile)
	# 丸太置き場: 丸太を前後に向けて横に6本（1段6本。上の段は半分ずらす）
	_input_pile = ItemPile.new(func(id: String) -> MeshInstance3D: return _pile_log(id))
	_input_pile.cols = 6
	_input_pile.step = Vector3(0.23, 0, 0)
	_input_pile.stagger = Vector3(0.115, 0, 0)
	_input_pile.position = INPUT_PILE_OFFSET + Vector3(0, DECK_Y, 0)
	add_child(_input_pile)

	_work_log = Node3D.new()
	add_child(_work_log)
	_work_plank = Node3D.new()
	add_child(_work_plank)


## 製材所の見た目（板敷きの床・製材台・ノコギリ・看板。当たり判定・受け渡しの印・在庫の山は含まない）。
## 強化画面のサムネイルでも使う。回転するノコギリを返す。
static func build_bench(root: Node3D) -> MeshInstance3D:
	# 作業列の下の板敷きの床（出荷場の桟橋と同じ色）
	root.add_child(Fx.box(Vector3(7.0, DECK_Y, 1.7), Color("#c99a5e"), Vector3(0, DECK_Y * 0.5, ROW_Z), "wood"))
	for i in 15:
		root.add_child(Fx.box(Vector3(0.03, 0.02, 1.7), Color("#9a7040"), Vector3(-3.5 + i * 0.5, DECK_Y + 0.005, ROW_Z)))
	# 製材機: 赤い本体の上に鋼の台、台を貫く丸ノコと黄色のカバー。両端に丸太を送るローラー
	var bench := Node3D.new()
	bench.position = BENCH_OFFSET + Vector3(0, DECK_Y, 0)
	root.add_child(bench)
	var body := Color("#e8573a")
	bench.add_child(Fx.box(Vector3(1.5, 0.62, 0.86), body, Vector3(0, 0.31, 0), "metal"))
	bench.add_child(Fx.box(Vector3(1.56, 0.08, 0.92), body.darkened(0.25), Vector3(0, 0.04, 0), "metal"))
	bench.add_child(Fx.box(Vector3(2.4, 0.1, 0.9), Color("#cfd6de"), Vector3(0, 0.67, 0), "metal"))
	for x in [-1.05, 1.05]:
		bench.add_child(Fx.box(Vector3(0.12, 0.62, 0.12), Color("#59616b"), Vector3(x, 0.31, 0), "metal"))
		var roller := Fx.cylinder(0.07, 0.8, Color("#59616b"), Vector3(x, 0.76, 0), -1.0, 10, false, "metal")
		roller.rotation_degrees.x = 90.0
		bench.add_child(roller)
	var blade := Fx.cylinder(0.36, 0.04, Color("#e6eaee"), Vector3(0, 0.74, 0), -1.0, 20, false, "metal")
	blade.rotation_degrees.z = 90.0
	blade.rotation_degrees.y = 90.0
	bench.add_child(blade)
	# ノコギリの上のカバー（黄色）と、奥から支える柱
	var hood := Color("#ffc23d")
	bench.add_child(Fx.box(Vector3(0.84, 0.16, 0.2), hood, Vector3(0, 1.12, 0), "metal"))
	bench.add_child(Fx.box(Vector3(0.1, 0.5, 0.1), hood, Vector3(0, 0.96, -0.38), "metal"))
	bench.add_child(Fx.box(Vector3(0.1, 0.1, 0.38), hood, Vector3(0, 1.17, -0.2), "metal"))
	# 操作盤
	bench.add_child(Fx.box(Vector3(0.3, 0.26, 0.06), Color("#3a4250"), Vector3(0.55, 0.4, 0.45), "metal"))
	bench.add_child(Fx.box(Vector3(0.08, 0.08, 0.04), Color("#5bd15b"), Vector3(0.5, 0.42, 0.49)))
	bench.add_child(Fx.box(Vector3(0.08, 0.08, 0.04), Color("#ff4d4d"), Vector3(0.62, 0.42, 0.49)))
	# 看板（出荷場と同じ形）
	var signboard := Props.signboard("製材所", Color("#e8573a"))
	signboard.position = BENCH_OFFSET + Vector3(0, 0, -1.2)
	root.add_child(signboard)
	return blade


func _process(delta: float) -> void:
	var unlocked := is_line_unlocked()

	# 投入口: 運搬者から丸太を受け取る
	for carrier in carriers_near(input_position(), _pad_radius()):
		var stack: CarryStack = carrier.stack
		if stack.count("log") > 0 and tick(carrier, "in", delta):
			var item := stack.take("log")
			_fly_in(item["tree"], (carrier as Node3D).global_position)
			_accept_log(item["tree"])

	if unlocked:
		_process_line(delta)
		# 出口: プレイヤー・運搬車が板を受け取る
		for carrier in carriers_near(output_position(), _pad_radius(), "plank_carriers"):
			var stack: CarryStack = carrier.stack
			if not output.is_empty() and not stack.is_full() and tick(carrier, "out", delta):
				var tree_id: String = output.pop_back()
				stack.add({"kind": "plank", "tree": tree_id})
				_rebuild_output()
				Fx.fly_item(self, _plank_mesh(tree_id), _output_pile.top_global(), (carrier as Node3D).global_position + Vector3(0, 1.0, 0), 0.22)

	var cutting := unlocked and not queue.is_empty()
	_blade.rotate_object_local(Vector3.UP, delta * (14.0 if cutting else 1.0))
	_update_work(cutting)
	_update_effects(cutting, delta)
	_update_labels(unlocked)


func _update_effects(cutting: bool, delta: float) -> void:
	if _sawdust.emitting != cutting:
		_sawdust.emitting = cutting
		_sawdust_haze.emitting = cutting
	if not cutting:
		return
	# ときどき節に当たって火花が散る
	_spark_timer -= delta
	if _spark_timer <= 0.0:
		_spark_timer = randf_range(0.8, 2.2)
		Vfx.sparks(self, global_position + BENCH_OFFSET + Vector3(0, DECK_Y + 0.85, 0.1), Vector3(-0.3, 0, 1.0), 5)


## 運ばれてきた丸太が投入口（加工待ちの山）へ飛んでいく演出
func _fly_in(tree_id: String, from: Vector3) -> void:
	var target := input_position() + Vector3(0, 0.3, 0)
	if is_line_unlocked():
		target = _input_pile.top_global() + Vector3(0, 0.1, 0)
	Fx.fly_item(self, LogDrop.make_log_mesh(tree_id), from + Vector3(0, 1.0, 0), target, 0.25)


## 丸太を受け取る（プレイヤー・運搬者・川の集積所のコンベアから）。
func accept_log(tree_id: String) -> void:
	_accept_log(tree_id)


func _accept_log(tree_id: String) -> void:
	if is_line_unlocked():
		# 山は上から使う（queue の最後が製材台で加工中の1本）。加工中の1本はそのままにして、
		# 新しく来た丸太はその手前＝山のいちばん上に積む
		if queue.is_empty():
			queue.append(tree_id)
		else:
			queue.insert(queue.size() - 1, tree_id)
		_rebuild_input()
	else:
		var price := GameData.log_price(tree_id)
		GameState.add_money(price)
		Fx.popup(self, input_position(), "+¥%d" % price, Color("#ffe14d"))
		Fx.coin_pop(self, input_position())
		Audio.play("sell", -6.0)


func _process_line(delta: float) -> void:
	if queue.is_empty():
		_progress = 0.0
		return
	# 進み具合は 0〜1（1本ぶん）。硬い木ほど saw_time 倍の時間がかかる
	_progress += GameState.value("sawmill") * delta / GameData.saw_time(queue.back())
	var changed := false
	while _progress >= 1.0 and not queue.is_empty():
		_progress -= 1.0
		output.append(queue.pop_back())
		changed = true
		if not queue.is_empty():
			# 余った進み具合は次の木の硬さで換算し直す
			_progress *= GameData.saw_time(output.back()) / GameData.saw_time(queue.back())
	if changed:
		_rebuild_output()
		_rebuild_input()
		var at := global_position + BENCH_OFFSET + Vector3(BENCH_FEED_X, DECK_Y + 0.8, 0)
		Vfx.wood_chips(self, at, Vector3(1, 0, 0.4), [Color("#f0d6a4"), Color("#d9b47a")], 5)
		Vfx.dust(self, at, Color("#efdcb5"), 3, 0.45, 0.9)


## 製材台の上の1本を加工の進み具合に合わせて左から右へ流す。ノコギリ（中央）より左は丸太、右は板に見える。
func _update_work(cutting: bool) -> void:
	if not cutting:
		_work_log.visible = false
		_work_plank.visible = false
		return
	var tree_id: String = queue.back()
	if tree_id != _work_tree:
		_work_tree = tree_id
		for child in _work_log.get_children():
			child.queue_free()
		for child in _work_plank.get_children():
			child.queue_free()
		_work_log.add_child(LogDrop.make_log_mesh(tree_id))
		_work_plank.add_child(_plank_mesh(tree_id))
	var x := lerpf(-BENCH_FEED_X, BENCH_FEED_X, clampf(_progress, 0.0, 1.0))
	var top := BENCH_OFFSET + Vector3(0, DECK_Y + 0.72, 0)
	_work_log.visible = x < 0.0
	_work_plank.visible = x >= 0.0
	_work_log.position = top + Vector3(x, 0.11, 0)
	_work_plank.position = top + Vector3(x, 0.08, 0)


## 板置き場の板の山（数は output と同じ）
func _rebuild_output() -> void:
	_output_pile.show_items(output)


## 丸太置き場の加工待ちの丸太の山。製材台の上で加工中の1本（queue の最後＝山のいちばん上から取った1本）は山から除くので、
## 山と製材台の丸太を合わせた数が queue と同じになる
func _rebuild_input() -> void:
	var waiting := queue
	if is_line_unlocked() and not queue.is_empty():
		waiting = queue.slice(0, queue.size() - 1)
	_input_pile.show_items(waiting)


static func _pile_log(tree_id: String) -> MeshInstance3D:
	var log_mesh := LogDrop.make_log_mesh(tree_id, 90.0) as MeshInstance3D
	return log_mesh


## 板の見た目。木の種類ごとの木口の色の板に、両端へ等級の色を塗る（丸太の帯と同じ色）。
static func _plank_mesh(tree_id: String) -> MeshInstance3D:
	var def := GameData.tree_def(tree_id)
	var body := LogDrop.end_color(def)
	var grade := LogDrop.grade_color(def)
	var box := BoxMesh.new()
	box.size = Vector3(0.8, 0.16, 0.3)
	var cap := BoxMesh.new()
	cap.size = Vector3(0.05, 0.162, 0.302)
	var mesh := Fx.merged_flat("plank/" + tree_id, [
		[box, Transform3D.IDENTITY, body],
		[cap, Transform3D(Basis.IDENTITY, Vector3(0.425, 0, 0)), grade],
		[cap, Transform3D(Basis.IDENTITY, Vector3(-0.425, 0, 0)), grade],
	])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi


func _refresh() -> void:
	_output_root.visible = is_line_unlocked()
	_rebuild_input()


func _update_labels(unlocked: bool) -> void:
	if unlocked:
		_input_zone.set_text("積み込み", "丸太: %d" % queue.size())
		_output_zone.set_text("板" if queue.is_empty() else "製材中", "板: %d" % output.size())
	else:
		_input_zone.set_text("丸太を売る", "")
