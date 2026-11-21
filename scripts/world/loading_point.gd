class_name LoadingPoint
extends Station
## 川の積み場（川岸の積み込み枠）。そのエリアが開放済みなら、最初は支払い枠として出ていて、
## 立つと少しずつ支払い（エリアの柵と同じしくみ）、払い終わると積み込み枠になる。
## 積み込み枠の上に立つと（プレイヤー・運搬役の伐採員・運搬車）丸太を降ろし、川が拠点の集積所まで流す。

const RADIUS := 1.4
## 何回の支払いで満額になるか（エリアの柵と同じ）
const PAY_STEPS := AreaGate.PAY_STEPS

const LOAD_FILL := Color(0.45, 0.75, 0.95, 0.18)
const PAY_FILL := Color(0.95, 0.65, 0.3, 0.18)

var line: LogLine
var area_index := 0

var _zone: Zone
var _unlocked := false


func _ready() -> void:
	_zone = Zone.new(Vector2(RADIUS * 2.0, RADIUS * 2.0), LOAD_FILL)
	add_child(_zone)
	refresh()


## 丸太を積める状態か（エリアと積み場の両方が開放済み）
func is_active() -> bool:
	return line != null and GameState.is_area_unlocked(area_index) and GameState.is_river_point_unlocked(area_index)


## 支払い待ちの枠を出しているか
func is_for_sale() -> bool:
	return GameState.is_area_unlocked(area_index) and not GameState.is_river_point_unlocked(area_index)


func refresh() -> void:
	_unlocked = is_active()
	visible = _unlocked or is_for_sale()
	if _unlocked:
		add_to_group("log_dropoffs")
	else:
		remove_from_group("log_dropoffs")
	if _zone:
		_zone.set_fill(LOAD_FILL if _unlocked else PAY_FILL)
	refresh_text()


func refresh_text() -> void:
	if _zone == null or line == null:
		return
	if _unlocked:
		_zone.set_text("川へ積み込み")
	else:
		_zone.set_text("川の積み場を開放", "¥%d" % GameState.river_point_remaining(area_index))


func _process(delta: float) -> void:
	if not visible:
		return
	if not _unlocked:
		_process_payment(delta)
		return
	for carrier in carriers_near(global_position, RADIUS):
		var stack: CarryStack = carrier.stack
		if stack.count("log") > 0 and tick(carrier, "load", delta):
			var item := stack.take("log")
			Fx.fly_item(self, LogDrop.make_log_mesh(item["tree"]), (carrier as Node3D).global_position + Vector3(0, 1.0, 0), Vector3(line.x, 0.2, global_position.z), 0.3)
			line.launch(item["tree"], self)
			refresh_text()


func _process_payment(delta: float) -> void:
	var chunk := maxi(1, ceili(float(GameState.river_point_cost(area_index)) / PAY_STEPS))
	for carrier in carriers_near(global_position, RADIUS, "player"):
		if GameState.money > 0 and tick(carrier, "pay", delta, 0.03):
			GameState.pay_toward_river_point(area_index, chunk)
			if GameState.is_river_point_unlocked(area_index):
				Audio.play("unlock", 0.0)
				Fx.burst(get_parent(), global_position + Vector3(0, 1.0, 0), [Color("#ffd84a"), Color("#6bc4ff"), Color("#8fe07a")], 40, 6.0, 0.12, 1.4)
				return
			refresh_text()


## 丸太の届け先のうち、from にいちばん近い場所（製材所の投入口か、使える積み込み枠）。
static func nearest_dropoff(context: Node, from: Vector3, sawmill: Sawmill) -> Vector3:
	var best := sawmill.input_position() if sawmill else Vector3.INF
	var best_d := Fx.xz_distance(best, from) if sawmill else INF
	for node in context.get_tree().get_nodes_in_group("log_dropoffs"):
		var p := node as LoadingPoint
		var d := Fx.xz_distance(p.global_position, from)
		if d < best_d:
			best_d = d
			best = p.global_position
	return best
