class_name SaleTruck
extends Node3D
## 出荷場に来る販売専用のトラック（見た目と動きだけ。積み込みと売上は ShipDock が決める）。
## プレイヤーが乗る機械（トラクター・小型トラック）と見分けがつくように、
## 青い運転台に長い平荷台を引く大きなトラックにして、屋根に「出荷」の札を付けている。乗れない。
## 正面は +X。荷台に板・丸太が積まれ、満載になると +X の方向（拠点の外）へ走り去り、
## しばらくすると空のトラックがバックで戻ってくる。

signal arrived

enum State { PARKED, LEAVING, AWAY, ARRIVING }

## 停める位置から、見えなくなる位置までの距離（+X 方向）
const EXIT_DISTANCE := 18.0
const SPEED := 9.0
const AWAY_SEC := 0.6
## 荷台（ローカル座標）。板は荷台の長さ方向に4枚、横に4枚並べて積む
const BED_CENTER := Vector3(-0.85, 0.82, 0)
const BED_SIZE := Vector3(4.0, 0.12, 1.5)
const SLOT_COLS := 4
const SLOT_ROWS := 4
const LAYER_H := 0.17

const CAB_COLOR := Color("#2f6fd6")
const TRIM_COLOR := Color("#f4f1ea")
const BED_COLOR := Color("#4a4f57")
const STAKE_COLOR := Color("#ffc23d")

var state := State.PARKED
## 積んでいる荷物 {"kind": "plank" | "log", "tree": 木のID}
var cargo: Array[Dictionary] = []

var park_x := 0.0
var _speed := 0.0
var _away_timer := 0.0
var _wheels: Array[Node3D] = []
var _body: Node3D
var _load_root: Node3D


func _ready() -> void:
	park_x = position.x
	_build()


func is_parked() -> bool:
	return state == State.PARKED


## 次に積む荷物が飛んでいく先（荷台の上）
func next_slot_position() -> Vector3:
	return to_global(_slot(cargo.size()) + Vector3(0, 0.15, 0))


func add_cargo(kind: String, tree_id: String) -> void:
	cargo.append({"kind": kind, "tree": tree_id})
	_load_root.add_child(_cargo_mesh(cargo.size() - 1))


func clear_cargo() -> void:
	cargo.clear()
	for child in _load_root.get_children():
		child.queue_free()


## 積み荷ごと拠点の外へ走り去る
func depart() -> void:
	if state != State.PARKED:
		return
	state = State.LEAVING
	_speed = 0.0


func _process(delta: float) -> void:
	match state:
		State.LEAVING:
			_speed = minf(SPEED, _speed + 6.0 * delta)
			position.x += _speed * delta
			if position.x >= park_x + EXIT_DISTANCE:
				state = State.AWAY
				visible = false
				_away_timer = AWAY_SEC
				clear_cargo()
		State.AWAY:
			_away_timer -= delta
			if _away_timer <= 0.0:
				state = State.ARRIVING
				visible = true
				position.x = park_x + EXIT_DISTANCE
		State.ARRIVING:
			# バックで出荷場の横へ。止まる手前でゆっくりになる
			var left := position.x - park_x
			var v := clampf(left * 1.6, 1.2, SPEED)
			position.x = maxf(park_x, position.x - v * delta)
			_speed = -v
			if position.x <= park_x:
				_speed = 0.0
				state = State.PARKED
				arrived.emit()
		State.PARKED:
			_speed = 0.0
	# タイヤを回し、走っているときだけ車体を少し揺らす
	for w in _wheels:
		w.rotate_object_local(Vector3.RIGHT, -_speed * delta / 0.36)
	if _body:
		_body.position.y = sin(Time.get_ticks_msec() * 0.02) * 0.015 if absf(_speed) > 0.1 else 0.0


func _slot(index: int) -> Vector3:
	var per_layer := SLOT_COLS * SLOT_ROWS
	var layer := floori(index / float(per_layer))
	var cell := index % per_layer
	var col := cell % SLOT_COLS
	var row := floori(cell / float(SLOT_COLS))
	return BED_CENTER + Vector3((col - (SLOT_COLS - 1) * 0.5) * 0.96, 0.14 + layer * LAYER_H, (row - (SLOT_ROWS - 1) * 0.5) * 0.33)


func _cargo_mesh(index: int) -> Node3D:
	var item := cargo[index]
	var node: Node3D
	if item["kind"] == "log":
		node = LogDrop.make_log_mesh(item["tree"], 0.0)
		node.scale = Vector3(1.3, 1.2, 1.2)
	else:
		node = Sawmill._plank_mesh(item["tree"])
	node.position = _slot(index)
	node.rotation_degrees.y = 2.0 if index % 2 == 0 else -2.0
	return node


## 車体: 青い運転台（白い帯と屋根の「出荷」の札）＋黄色い柱の長い平荷台＋6輪
func _build() -> void:
	_body = Node3D.new()
	add_child(_body)
	# シャシー
	_body.add_child(Fx.box(Vector3(5.9, 0.22, 1.0), Color("#2b2f35"), Vector3(-0.1, 0.5, 0), "metal"))
	# 運転台（前が +X）
	var cab_x := 2.15
	_body.add_child(Fx.box(Vector3(1.35, 1.25, 1.62), CAB_COLOR, Vector3(cab_x, 1.2, 0), "metal"))
	_body.add_child(Fx.box(Vector3(0.55, 0.6, 1.55), CAB_COLOR, Vector3(cab_x + 0.9, 0.85, 0), "metal"))
	_body.add_child(Fx.box(Vector3(1.37, 0.16, 1.64), TRIM_COLOR, Vector3(cab_x, 0.95, 0)))
	_body.add_child(Fx.box(Vector3(0.08, 0.5, 1.4), Color("#24303f"), Vector3(cab_x + 0.66, 1.5, 0)))
	for z in [-1, 1]:
		_body.add_child(Fx.box(Vector3(0.7, 0.45, 0.04), Color("#24303f"), Vector3(cab_x + 0.15, 1.52, z * 0.81)))
		_body.add_child(Fx.box(Vector3(0.1, 0.12, 0.3), Color("#fff0b0"), Vector3(cab_x + 1.17, 0.95, z * 0.55)))
		# バックミラー
		_body.add_child(Fx.box(Vector3(0.06, 0.28, 0.08), Color("#2b2f35"), Vector3(cab_x + 0.6, 1.55, z * 0.92)))
	_body.add_child(Fx.box(Vector3(0.12, 0.3, 1.5), Color("#9aa3ad"), Vector3(cab_x + 1.2, 0.62, 0), "metal"))
	# 屋根の「出荷」の札（販売のトラックだとひと目でわかるように）
	_body.add_child(Fx.box(Vector3(0.9, 0.06, 0.7), Color("#2b2f35"), Vector3(cab_x - 0.05, 1.86, 0)))
	var board := Fx.box(Vector3(0.95, 0.42, 0.12), Color("#ffd23f"), Vector3(cab_x - 0.05, 2.12, 0))
	_body.add_child(board)
	for side in [-1, 1]:
		var label := Label3D.new()
		label.text = "出荷"
		label.font_size = 64
		label.pixel_size = 0.0055
		label.modulate = Color("#2b2f35")
		label.outline_size = 0
		label.position = Vector3(cab_x - 0.05, 2.12, side * 0.065)
		label.rotation_degrees.y = 0.0 if side > 0 else 180.0
		_body.add_child(label)
	# 排気筒
	_body.add_child(Fx.cylinder(0.06, 1.1, Color("#9aa3ad"), Vector3(cab_x - 0.75, 1.65, -0.7), -1.0, 8, false, "metal"))
	# 平荷台と前の鳥居（荷物止め）、両脇の黄色い柱
	_body.add_child(Fx.box(BED_SIZE, BED_COLOR, BED_CENTER, "metal"))
	_body.add_child(Fx.box(Vector3(BED_SIZE.x + 0.04, 0.08, BED_SIZE.z + 0.04), STAKE_COLOR, BED_CENTER + Vector3(0, -0.08, 0), "metal"))
	_body.add_child(Fx.box(Vector3(0.1, 1.0, 1.5), BED_COLOR, BED_CENTER + Vector3(BED_SIZE.x * 0.5 - 0.05, 0.5, 0), "metal"))
	for i in 4:
		var x := BED_CENTER.x - BED_SIZE.x * 0.5 + 0.2 + i * (BED_SIZE.x - 0.5) / 3.0
		for z in [-1, 1]:
			_body.add_child(Fx.box(Vector3(0.08, 0.7, 0.08), STAKE_COLOR, BED_CENTER + Vector3(x - BED_CENTER.x, 0.35, z * 0.72), "metal"))
	# テールランプ
	for z in [-1, 1]:
		_body.add_child(Fx.box(Vector3(0.06, 0.12, 0.25), Color("#ff4d4d"), Vector3(BED_CENTER.x - BED_SIZE.x * 0.5 - 0.02, 0.62, z * 0.55)))
	# タイヤ（Kenney の Car Kit のトラック用）。前1軸・後ろ2軸
	for x in [2.35, -1.6, -2.4]:
		for z in [-1, 1]:
			var wheel := Fx.model("res://assets/kenney/car/wheel-truck.glb")
			wheel.position = Vector3(x, 0.36, z * 0.7)
			wheel.rotation_degrees.y = 90.0
			wheel.scale = Vector3.ONE * 1.2
			add_child(wheel)
			_wheels.append(wheel)
	_load_root = Node3D.new()
	_body.add_child(_load_root)
