class_name LoadingPoint
extends Station
## 川岸の積み込み枠。上に立つと（プレイヤー・運搬役の伐採員・運搬車）丸太を降ろし、
## 川が拠点の集積所まで流す。川流しが開放済みで、そのエリアも開放済みのときだけ使える。

const RADIUS := 1.4

var line: LogLine
var area_index := 0

var _zone: Zone


func _ready() -> void:
	_zone = Zone.new(Vector2(RADIUS * 2.0, RADIUS * 2.0), Color(0.45, 0.75, 0.95, 0.18))
	add_child(_zone)
	refresh()


func is_active() -> bool:
	return line != null and line.is_active() and GameState.is_area_unlocked(area_index)


func refresh() -> void:
	visible = is_active()
	if visible:
		add_to_group("log_dropoffs")
	else:
		remove_from_group("log_dropoffs")
	refresh_text()


func refresh_text() -> void:
	if _zone == null or line == null:
		return
	_zone.set_text("川へ積み込み", "積載量: %d" % line.in_transit_from(self))


func _process(delta: float) -> void:
	if not visible:
		return
	for carrier in carriers_near(global_position, RADIUS):
		var stack: CarryStack = carrier.stack
		if stack.count("log") > 0 and tick(carrier, "load", delta):
			var item := stack.take("log")
			Fx.fly_item(self, LogDrop.make_log_mesh(item["tree"]), (carrier as Node3D).global_position + Vector3(0, 1.0, 0), Vector3(line.x, 0.2, global_position.z), 0.3)
			line.launch(item["tree"], self)
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
