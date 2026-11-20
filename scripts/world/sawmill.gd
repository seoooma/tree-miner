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
var _input_label: Label3D
var _output_label: Label3D
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
	add_child(Fx.box(Vector3(3.6, 2.2, 3.0), Color("#b5774a"), Vector3(0, 1.1, 0)))
	add_child(Fx.box(Vector3(4.0, 0.4, 3.4), Color("#7a3f2a"), Vector3(0, 2.4, 0)))
	_blade = Fx.cylinder(0.7, 0.05, Color("#d0d4d8"), Vector3(0, 1.0, -1.55))
	_blade.rotation_degrees.x = 90.0
	add_child(_blade)
	_title = Fx.label3d("製材所", Vector3(0, 3.6, 0), 56)
	add_child(_title)

	var input_pad := Fx.pad(_pad_radius(), Color("#f2d16b"))
	input_pad.position += INPUT_OFFSET
	add_child(input_pad)
	_input_label = Fx.label3d("", INPUT_OFFSET + Vector3(0, 0.6, 0.8), 40)
	add_child(_input_label)

	_output_root = Node3D.new()
	_output_root.position = OUTPUT_OFFSET
	add_child(_output_root)
	_output_root.add_child(Fx.pad(_pad_radius(), Color("#9ad0f0")))
	_output_pile = Node3D.new()
	_output_root.add_child(_output_pile)
	_output_label = Fx.label3d("", Vector3(0, 0.6, 0.9), 40)
	_output_root.add_child(_output_label)


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

	_blade.rotation_degrees.y += delta * (720.0 if unlocked and not queue.is_empty() else 60.0)
	_update_labels(unlocked)


func _accept_log(tree_id: String) -> void:
	if is_line_unlocked():
		queue.append(tree_id)
	else:
		var price := GameData.log_price(tree_id)
		GameState.add_money(price)
		Fx.popup(self, input_position(), "+¥%d" % price, Color("#ffe14d"))


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
		_input_label.text = "丸太を置く（待ち %d本）" % queue.size()
		_output_label.text = "板 %d枚" % output.size()
	else:
		_input_label.text = "丸太を売る"
