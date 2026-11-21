class_name Sawmill
extends Station
## 製材所。
## - 製材ライン未開放: 投入口に置いた丸太をその場で売却する。
## - 製材ライン開放後: 丸太を板に加工し、出口に積む。板は出荷場で売る（売値 x plank_multiplier）。
##   丸太置き場（input_max）と出口（output_max）には上限があり、いっぱいだと受け取り・加工が止まる。
##   加工は強化『製材ライン』の本/秒で1本ずつ進み、作業台の上を丸太がノコギリへ送られていく。

const INPUT_OFFSET := Vector3(0, 0, -3.0)
const OUTPUT_OFFSET := Vector3(3.6, 0, 0.6)

var queue: Array[String] = []
var output: Array[String] = []
var _progress := 0.0

var _title: Label3D
var _input_zone: Zone
var _output_zone: Zone
var _output_root: Node3D
var _output_pile: Node3D
## 投入口の左前（森側。投入口に立っても屋根に隠れない位置）に積み上がる、加工待ちの丸太置き場。数は queue と同じ
var _input_pile: Node3D
const INPUT_PILE_OFFSET := Vector3(-3.0, 0, -3.6)
const PILE_VISIBLE := 48
var _blade: MeshInstance3D
## 作業台の上でノコギリへ送られている丸太（加工の進み具合が見える）
var _cutting: Node3D
var _cutting_id := ""


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


func input_max() -> int:
	return int(GameData.sawmill.get("input_max", 40))


func output_max() -> int:
	return int(GameData.sawmill.get("output_max", 40))


## 丸太置き場にまだ置けるか。incoming = コンベアで運んでいる途中の数（ライン未開放ならその場で売るので常に置ける）
func has_input_room(incoming := 0) -> bool:
	return not is_line_unlocked() or queue.size() + incoming < input_max()


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


func _pad_radius() -> float:
	return float(GameData.sawmill.get("pad_radius", 1.6))


func _build() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.6, 2.4, 3.0)
	shape.shape = box
	shape.position.y = 1.2
	body.add_child(shape)
	add_child(body)
	_blade = build_house(self)
	_title = Fx.label3d("製材所", Vector3(0, 3.6, 0), 56)
	add_child(_title)

	_input_zone = Zone.new(Vector2.ONE * _pad_radius() * 2.0, Color(0.95, 0.8, 0.3, 0.16))
	_input_zone.position = INPUT_OFFSET
	add_child(_input_zone)

	_output_root = Node3D.new()
	_output_root.position = OUTPUT_OFFSET
	add_child(_output_root)
	_output_zone = Zone.new(Vector2.ONE * _pad_radius() * 2.0, Color(0.55, 0.8, 0.95, 0.16))
	_output_root.add_child(_output_zone)
	_output_pile = Node3D.new()
	_output_root.add_child(_output_pile)
	_input_pile = Node3D.new()
	_input_pile.position = INPUT_PILE_OFFSET
	add_child(_input_pile)
	_cutting = Node3D.new()
	_cutting.visible = false
	add_child(_cutting)


## 製材所の建物の見た目（当たり判定・受け渡しの印は含まない）。強化画面のサムネイルでも使う。回転するノコギリを返す。
static func build_house(root: Node3D) -> MeshInstance3D:
	# 土台・板壁・切妻屋根
	root.add_child(Fx.box(Vector3(3.9, 0.16, 3.3), Color("#9b9a92"), Vector3(0, 0.08, 0)))
	var wall := Props.plank_wall(Vector3(3.5, 1.7, 2.9), Color("#b9784a"))
	wall.position.y = 0.16
	root.add_child(wall)
	var roof := Props.gable_roof(3.9, 3.4, 1.1, Color("#b8452f"))
	roof.position.y = 1.86
	root.add_child(roof)
	root.add_child(Fx.box(Vector3(3.95, 0.1, 0.12), Color("#7a2f22"), Vector3(0, 2.95, 0), "metal"))
	# 正面（森側）の作業口とノコギリ、ベルトコンベア
	root.add_child(Fx.box(Vector3(1.6, 1.1, 0.05), Color("#3a2618"), Vector3(0, 0.75, -1.47)))
	root.add_child(Fx.box(Vector3(1.8, 0.12, 0.12), Color("#7a4a2a"), Vector3(0, 1.36, -1.5), "wood"))
	var blade := Fx.cylinder(0.5, 0.05, Color("#c9ced3"), Vector3(0, 0.75, -1.52), -1.0, 16, false, "metal")
	blade.rotation_degrees.z = 90.0
	blade.rotation_degrees.y = 90.0
	root.add_child(blade)
	root.add_child(Fx.box(Vector3(0.9, 0.12, 1.4), Color("#3d4247"), Vector3(0, 0.45, -2.15), "metal"))
	for i in 4:
		root.add_child(Fx.box(Vector3(0.95, 0.05, 0.08), Color("#8c939a"), Vector3(0, 0.53, -1.6 - i * 0.33), "metal"))
	root.add_child(Fx.box(Vector3(0.1, 0.4, 0.1), Color("#3d4247"), Vector3(-0.4, 0.2, -2.7)))
	root.add_child(Fx.box(Vector3(0.1, 0.4, 0.1), Color("#3d4247"), Vector3(0.4, 0.2, -2.7)))
	# 煙突（丸太の山は飾りを置かず、実際の加工待ちの数だけ _input_pile に積む）
	root.add_child(Fx.cylinder(0.14, 1.0, Color("#5b5f63"), Vector3(1.1, 2.7, 0.6), -1.0, 10, false, "metal"))
	return blade


func _process(delta: float) -> void:
	var unlocked := is_line_unlocked()

	# 投入口: 運搬者から丸太を受け取る
	for carrier in carriers_near(input_position(), _pad_radius()):
		var stack: CarryStack = carrier.stack
		if stack.count("log") > 0 and has_input_room() and tick(carrier, "in", delta):
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
				Fx.fly_item(self, _plank_mesh(tree_id), output_position() + Vector3(0, 0.6, 0), (carrier as Node3D).global_position + Vector3(0, 1.0, 0), 0.22)
				_rebuild_output()

	var cutting := unlocked and not queue.is_empty() and output.size() < output_max()
	_blade.rotate_object_local(Vector3.UP, delta * (12.0 if cutting else 1.0))
	_update_cutting(cutting)
	_update_labels(unlocked)


## 運ばれてきた丸太が投入口（加工待ちの山）へ飛んでいく演出
func _fly_in(tree_id: String, from: Vector3) -> void:
	var target := input_position() + Vector3(0, 0.3, 0)
	if is_line_unlocked():
		target = global_position + INPUT_PILE_OFFSET + Vector3(0, 0.2 + floori(mini(queue.size(), PILE_VISIBLE) / 4.0) * 0.2, 0)
	Fx.fly_item(self, LogDrop.make_log_mesh(tree_id), from + Vector3(0, 1.0, 0), target, 0.25)


## 丸太を受け取る（プレイヤー・運搬者・川の集積所のコンベアから）。
func accept_log(tree_id: String) -> void:
	_accept_log(tree_id)


func _accept_log(tree_id: String) -> void:
	if is_line_unlocked():
		queue.append(tree_id)
		_rebuild_input()
	else:
		var price := GameData.log_price(tree_id)
		GameState.add_money(price)
		Fx.popup(self, input_position(), "+¥%d" % price, Color("#ffe14d"))
		Fx.coin_pop(self, input_position())
		Audio.play("sell", -6.0)


func _process_line(delta: float) -> void:
	var out_max := output_max()
	if queue.is_empty() or output.size() >= out_max:
		# 出口がいっぱいのときは途中まで進んだ丸太をそのまま止めておく
		if queue.is_empty():
			_progress = 0.0
		return
	_progress += GameState.value("sawmill") * delta
	var changed := false
	while _progress >= 1.0 and not queue.is_empty() and output.size() < out_max:
		_progress -= 1.0
		output.append(queue.pop_front())
		changed = true
	if changed:
		_rebuild_output()
		_rebuild_input()
		Fx.burst(self, global_position + Vector3(0, 0.8, -1.55), [Color("#e8c99a"), Color("#c99a5b")], 6, 1.6, 0.05, 0.4)


## 作業台の上で、いま加工中の丸太を進み具合に合わせてノコギリへ送る
func _update_cutting(cutting: bool) -> void:
	_cutting.visible = cutting
	if not cutting:
		return
	var id: String = queue[0]
	if id != _cutting_id:
		_cutting_id = id
		for c in _cutting.get_children():
			c.queue_free()
		var log_mesh := LogDrop.make_log_mesh(id, 90.0)
		_cutting.add_child(log_mesh)
	_cutting.position = Vector3(0, 0.62, lerpf(-2.75, -1.6, clampf(_progress, 0.0, 1.0)))


## 出口の板の山（4枚ずつ互い違いに積む）
func _rebuild_output() -> void:
	for child in _output_pile.get_children():
		child.queue_free()
	for i in mini(output.size(), 60):
		var col := i % 4
		var row := floori(i / 4.0)
		var plank := _plank_mesh(output[i])
		plank.position = Vector3(0, 0.1 + row * 0.17, (col - 1.5) * 0.32)
		plank.rotation_degrees.y = 4.0 if row % 2 == 0 else -4.0
		_output_pile.add_child(plank)


## 投入口の左前の加工待ちの丸太の山（4本ずつ積む）
func _rebuild_input() -> void:
	for child in _input_pile.get_children():
		child.queue_free()
	for i in mini(queue.size(), PILE_VISIBLE):
		var col := i % 4
		var row := floori(i / 4.0)
		var log_mesh := LogDrop.make_log_mesh(queue[i], 90.0)
		log_mesh.scale = Vector3(1.5, 1.0, 1.0)
		log_mesh.position = Vector3((col - 1.5) * 0.23 + (0.11 if row % 2 == 1 else 0.0), 0.12 + row * 0.2, 0)
		_input_pile.add_child(log_mesh)


static func _plank_mesh(tree_id: String) -> MeshInstance3D:
	var def := GameData.tree_def(tree_id)
	var color := Color(def.get("trunk_color", "#a77a4f")).lightened(0.45)
	return Fx.box(Vector3(0.9, 0.16, 0.3), color, Vector3.ZERO, "wood")


func _refresh() -> void:
	_output_root.visible = is_line_unlocked()


func _update_labels(unlocked: bool) -> void:
	if unlocked:
		var in_full := queue.size() >= input_max()
		var out_full := output.size() >= output_max()
		_input_zone.set_text("丸太置き場 満杯" if in_full else "積み込み", "丸太: %d / %d" % [queue.size(), input_max()])
		var title := "板"
		if out_full:
			title = "板 満杯"
		elif not queue.is_empty():
			title = "製材中"
		_output_zone.set_text(title, "板: %d / %d" % [output.size(), output_max()])
	else:
		_input_zone.set_text("丸太を売る", "")
