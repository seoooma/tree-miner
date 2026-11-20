class_name Sawmill
extends Station
## 製材所。
## - 製材ライン未開放: 投入口に置いた丸太をその場で売却する。
## - 製材ライン開放後: 丸太を板に加工し、出口に積む。板は出荷場で売る（売値 x plank_multiplier）。

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
var _blade: MeshInstance3D


func _ready() -> void:
	_build()
	GameState.upgrade_changed.connect(func(_id: String, _level: int) -> void: _refresh())
	_refresh()


func is_line_unlocked() -> bool:
	return GameState.level("sawmill") > 0


func input_position() -> Vector3:
	return global_position + INPUT_OFFSET


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
	# 煙突と丸太の山
	root.add_child(Fx.cylinder(0.14, 1.0, Color("#5b5f63"), Vector3(1.1, 2.7, 0.6), -1.0, 10, false, "metal"))
	var pile := Props.log_pile(3, "pine")
	pile.position = Vector3(-2.4, 0, 0.4)
	root.add_child(pile)
	return blade


func _process(delta: float) -> void:
	var unlocked := is_line_unlocked()

	# 投入口: 運搬者から丸太を受け取る
	for carrier in carriers_near(input_position(), _pad_radius()):
		var stack: CarryStack = carrier.stack
		if stack.count("log") > 0 and tick(carrier, "in", delta):
			var item := stack.take("log")
			_accept_log(item["tree"])

	if unlocked:
		_process_line(delta)
		# 出口: プレイヤー・運搬車が板を受け取る
		for carrier in carriers_near(output_position(), _pad_radius(), "plank_carriers"):
			var stack: CarryStack = carrier.stack
			if not output.is_empty() and not stack.is_full() and tick(carrier, "out", delta):
				stack.add({"kind": "plank", "tree": output.pop_back()})
				_rebuild_output()

	_blade.rotate_object_local(Vector3.UP, delta * (12.0 if unlocked and not queue.is_empty() else 1.0))
	_update_labels(unlocked)


func _accept_log(tree_id: String) -> void:
	if is_line_unlocked():
		queue.append(tree_id)
	else:
		var price := GameData.log_price(tree_id)
		GameState.add_money(price)
		Fx.popup(self, input_position(), "+¥%d" % price, Color("#ffe14d"))
		Fx.coin_pop(self, input_position())
		Audio.play("sell", -6.0)


func _process_line(delta: float) -> void:
	var output_max := int(GameData.sawmill.get("output_max", 60))
	if queue.is_empty() or output.size() >= output_max:
		_progress = 0.0
		return
	_progress += GameState.value("sawmill") * delta
	var changed := false
	while _progress >= 1.0 and not queue.is_empty() and output.size() < output_max:
		_progress -= 1.0
		output.append(queue.pop_front())
		changed = true
	if changed:
		_rebuild_output()


func _rebuild_output() -> void:
	for child in _output_pile.get_children():
		child.queue_free()
	for i in mini(output.size(), 30):
		var def := GameData.tree_def(output[i])
		var color := Color(def.get("trunk_color", "#a77a4f")).lightened(0.45)
		var col := i % 3
		var row := floori(i / 3.0)
		_output_pile.add_child(Fx.box(Vector3(0.9, 0.16, 0.3), color, Vector3(0, 0.1 + row * 0.17, (col - 1) * 0.34)))


func _refresh() -> void:
	_output_root.visible = is_line_unlocked()


func _update_labels(unlocked: bool) -> void:
	if unlocked:
		_input_zone.set_text("積み込み", "積載量: %d" % queue.size())
		_output_zone.set_text("製材中" if not queue.is_empty() else "板", "積載量: %d" % output.size())
	else:
		_input_zone.set_text("丸太を売る", "")
