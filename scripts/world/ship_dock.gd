class_name ShipDock
extends Station
## 出荷場。製材ライン開放後、板をここに運ぶと荷台に積まれ、販売のトラックに積み込まれていく。
## - 隣の「丸太を売る」枠に置いた丸太も同じトラックで売れる（板より安い。製材所が追いつかないときの逃がし先）
## - 積み込む速さは強化『出荷のペース』（個/秒）。荷台に置ける数に上限はない
## - トラックの積める数・走る速さ・売値の上乗せは、乗り物タブの強化（トラックの荷台・速さ・取引先）
## - トラックが満載になるか、積む物がしばらく無くなると、積み荷の代金が入ってトラックが拠点の外へ走り去る。
##   すぐに空のトラックが戻ってくる。トラックがいない間の積み込みは貯めておき、戻ってきたらまとめて積む
## - 強化『板のコンベア』を開放すると、製材所の出口の板がコンベアで荷台へ自動で運ばれる

const PAD_RADIUS := 1.8
const SELL_ID := "dock"
const BELT_ID := "plank_belt"
## 丸太を売る枠（出荷場の右隣）
const LOG_PAD_OFFSET := Vector3(3.7, 0, 0.2)
const LOG_PAD_RADIUS := 1.35
const LOG_PILE_OFFSET := Vector3(3.75, 0.26, -2.6)
## 荷台の板の山の位置
const STOCK_PILE_OFFSET := Vector3(-0.65, 0.26, -2.6)
## 販売のトラックを停める位置（荷台の奥。正面は +X で、拠点の外へ向かう）
const TRUCK_OFFSET := Vector3(2.0, 0, -4.4)

var sawmill: Sawmill
## 荷台に積まれてトラックを待っている板（木のID）
var stock: Array[String] = []
## 丸太を売る枠の横に積まれてトラックを待っている丸太（木のID）
var log_stock: Array[String] = []
## 製材所の出口 → 荷台のコンベア
var belt: Conveyor
var truck: SaleTruck

var _zone: Zone
var _log_zone: Zone
## 荷台の板の山。数は stock と同じで、トラックに積んだ分だけ消える
var _stock_pile: ItemPile
var _log_pile: ItemPile
## 積み込みの進み具合（1 で1個積む）。トラックがいない間も貯まる（上限はトラック1台分）
var _load_progress := 0.0
## 積む物が無くなってからの秒数（積み荷があればこの秒数で出発する）
var _idle_time := 0.0


func _ready() -> void:
	_zone = Zone.new(Vector2.ONE * PAD_RADIUS * 2.0, Color(0.5, 0.85, 0.55, 0.16))
	add_child(_zone)
	_log_zone = Zone.new(Vector2.ONE * LOG_PAD_RADIUS * 2.0, Color(0.92, 0.55, 0.3, 0.16))
	_log_zone.position = LOG_PAD_OFFSET
	add_child(_log_zone)
	# 木の桟橋風の床（左に板、右に丸太を積む）と、出荷待ちの荷物
	add_child(Fx.box(Vector3(6.6, 0.14, 1.6), Color("#c99a5e"), Vector3(1.65, 0.07, -2.6), "wood"))
	for i in 14:
		add_child(Fx.box(Vector3(0.03, 0.02, 1.6), Color("#9a7040"), Vector3(-1.5 + i * 0.48, 0.15, -2.6)))
	add_child(Fx.box(Vector3(1.9, 0.12, 1.3), Color("#b07f48"), Vector3(STOCK_PILE_OFFSET.x, 0.2, -2.6), "wood"))
	add_child(Fx.box(Vector3(1.6, 0.12, 1.3), Color("#b07f48"), Vector3(LOG_PILE_OFFSET.x, 0.2, -2.6), "wood"))
	# 板の山: 板2枚を縦に並べ、奥行きに4枚（1段8枚）。数は stock と同じ
	_stock_pile = ItemPile.new(func(id: String) -> MeshInstance3D: return Sawmill._plank_mesh(id))
	_stock_pile.cols = 2
	_stock_pile.rows = 4
	_stock_pile.step = Vector3(0.86, 0, 0.3)
	_stock_pile.layer_h = 0.17
	_stock_pile.base_y = 0.08
	_stock_pile.layer_twist_deg = 3.0
	_stock_pile.position = STOCK_PILE_OFFSET
	add_child(_stock_pile)
	# 丸太の山: 前後に向けて横に6本（1段6本）。数は log_stock と同じ
	_log_pile = ItemPile.new(func(id: String) -> MeshInstance3D: return Sawmill._pile_log(id))
	_log_pile.cols = 6
	_log_pile.step = Vector3(0.23, 0, 0)
	_log_pile.stagger = Vector3(0.115, 0, 0)
	_log_pile.position = LOG_PILE_OFFSET
	add_child(_log_pile)
	var c1 := Props.crate(0.6)
	c1.position = Vector3(1.55, 0.14, -2.75)
	add_child(c1)
	var c2 := Props.crate(0.45, Color("#d8ab6a"))
	c2.position = Vector3(1.6, 0.74, -2.75)
	c2.rotation_degrees.y = 20.0
	add_child(c2)
	var signboard := Props.signboard("出荷場", Color("#3b8fe0"))
	signboard.position = Vector3(-2.5, 0, -1.9)
	signboard.rotation_degrees.y = 20.0
	add_child(signboard)
	# 販売のトラック（プレイヤーが乗る機械とは別。乗れない）
	truck = SaleTruck.new()
	truck.position = TRUCK_OFFSET
	add_child(truck)
	truck.arrived.connect(func() -> void: _idle_time = 0.0)
	stock = GameState.stock_list("dock")
	log_stock = GameState.stock_list("dock_logs")
	for entry in GameState.stock.get("dock_truck", []):
		var parts := str(entry).split(":")
		if parts.size() == 2 and parts[0] in ["plank", "log"] and not GameData.tree_def(parts[1]).is_empty():
			truck.add_cargo(parts[0], parts[1])
	GameState.saving.connect(_on_saving)
	_build_belt()
	GameState.upgrade_changed.connect(func(_id: String, _level: int) -> void: _refresh())
	_refresh()
	_rebuild_stock()
	_rebuild_logs()


func _on_saving() -> void:
	var ids := stock.duplicate()
	if belt:
		ids.append_array(belt.ids_in_flight())
	GameState.stock["dock"] = ids
	GameState.stock["dock_logs"] = log_stock.duplicate()
	# 走り去っている途中のトラックの積み荷は、出発したときに売れている
	var cargo: Array[String] = []
	if truck.is_parked():
		for item in truck.cargo:
			cargo.append("%s:%s" % [item["kind"], item["tree"]])
	GameState.stock["dock_truck"] = cargo


## トラック1台に積める数（強化『トラックの荷台』）
static func truck_capacity() -> int:
	return maxi(1, roundi(GameState.value("truck_capacity")))


## 製材所の出口（コンベアの始点）から荷台の横（終点）までのベルトコンベア。強化で開放するまでは隠す
func _build_belt() -> void:
	if sawmill == null:
		return
	var from := sawmill.output_pile_position() - global_position
	var to := _stock_pile.position
	var start := Vector3(from.x + 1.0, 0, from.z)
	var turn_x := to.x - 2.0
	var path: Array[Vector3] = [start, Vector3(turn_x, 0, start.z), Vector3(turn_x, 0, to.z), Vector3(to.x - 1.15, 0, to.z)]
	belt = Conveyor.new()
	belt.path = path
	belt.rate_source = func() -> float: return GameState.value(BELT_ID)
	belt.take_source = sawmill.take_plank
	belt.deliver = func(id: String) -> void: _add_stock(id)
	belt.make_mesh = func(id: String) -> Node3D: return Sawmill._plank_mesh(id)
	add_child(belt)


func _refresh() -> void:
	var unlocked := GameState.level("sawmill") > 0
	_zone.set_fill(Color(0.5, 0.85, 0.55, 0.16) if unlocked else Color(0.3, 0.3, 0.3, 0.2))
	_log_zone.visible = unlocked
	if belt:
		belt.set_active(unlocked and GameState.level(BELT_ID) > 0)
	_update_label()


func _update_label() -> void:
	if GameState.level("sawmill") <= 0:
		_zone.set_text("出荷場", "（製材ラインで開放）")
		return
	var title := "板を置く"
	if not stock.is_empty():
		title = "出荷中"
	_zone.set_text(title, "板: %d" % stock.size())
	_log_zone.set_text("丸太を売る", "板の半値")


func _process(delta: float) -> void:
	if GameState.level("sawmill") <= 0:
		return
	# 運んできた板を荷台に置く
	for carrier in carriers_near(global_position, PAD_RADIUS, "plank_carriers"):
		var stack: CarryStack = carrier.stack
		if stack.count("plank") > 0 and tick(carrier, "sell", delta):
			var item := stack.take("plank")
			Fx.fly_item(self, Sawmill._plank_mesh(item["tree"]), (carrier as Node3D).global_position + Vector3(0, 1.0, 0), _pile_top(), 0.25)
			_add_stock(item["tree"])
	# 運んできた丸太を、丸太を売る枠の横に置く
	for carrier in carriers_near(global_position + LOG_PAD_OFFSET, LOG_PAD_RADIUS):
		var stack: CarryStack = carrier.stack
		if stack.count("log") > 0 and tick(carrier, "sell_log", delta):
			var item := stack.take("log")
			Fx.fly_item(self, LogDrop.make_log_mesh(item["tree"]), (carrier as Node3D).global_position + Vector3(0, 1.0, 0), _log_pile_top(), 0.25)
			add_log(item["tree"])
	_process_truck(delta)
	_update_label()


## 荷台の板・丸太を、出荷のペースでトラックに積む。満載か、積む物がしばらく無ければ出発
func _process_truck(delta: float) -> void:
	var capacity := truck_capacity()
	var has_goods := not stock.is_empty() or not log_stock.is_empty()
	if has_goods:
		var room := capacity - (truck.cargo.size() if truck.is_parked() else 0)
		_load_progress = minf(_load_progress + GameState.value(SELL_ID) * delta, maxf(1.0, float(room)))
	else:
		_load_progress = minf(_load_progress, 1.0)
	if not truck.is_parked():
		return
	while _load_progress >= 1.0 and truck.cargo.size() < capacity and (not stock.is_empty() or not log_stock.is_empty()):
		_load_progress -= 1.0
		_load_one()
	if truck.cargo.is_empty():
		_idle_time = 0.0
		return
	if not stock.is_empty() or not log_stock.is_empty():
		_idle_time = 0.0
	else:
		_idle_time += delta
	if truck.cargo.size() >= capacity or _idle_time >= float(GameData.dock.get("depart_idle_sec", 2.5)):
		_depart()


## 荷台から1個トラックに積む（多いほうの山から）
func _load_one() -> void:
	if log_stock.size() > stock.size():
		var log_id: String = log_stock.pop_back()
		var from := _log_pile_top()
		_rebuild_logs()
		Fx.fly_item(self, LogDrop.make_log_mesh(log_id), from, truck.next_slot_position(), 0.3)
		truck.add_cargo("log", log_id)
	else:
		var plank_id: String = stock.pop_front()
		var from := _pile_top()
		_rebuild_stock()
		Fx.fly_item(self, Sawmill._plank_mesh(plank_id), from, truck.next_slot_position(), 0.3)
		truck.add_cargo("plank", plank_id)
	Audio.play("drop", -14.0, 1.25)


## 積み荷の代金を受け取って、トラックを走らせる
func _depart() -> void:
	var total := 0
	for item in truck.cargo:
		total += cargo_price(item)
	GameState.add_money(total)
	var at := truck.global_position + Vector3(-0.8, 2.0, 0)
	Fx.popup(self, at, "+¥%d" % total, Color("#ffe14d"), 84)
	for i in mini(4, 1 + truck.cargo.size() / 8):
		Fx.coin_pop(self, at + Vector3(randf_range(-1.2, 1.2), -1.0, 0))
	Audio.play("sell", -4.0, 1.0)
	Audio.play("board", -12.0, 0.8)
	_idle_time = 0.0
	truck.depart()


## 積み荷1個の売値。強化『トラックの取引先』の%だけ上乗せする
static func cargo_price(item: Dictionary) -> int:
	var base := GameData.log_price(str(item.get("tree", ""))) if item.get("kind", "") == "log" else GameData.plank_price(str(item.get("tree", "")))
	return maxi(1, roundi(base * GameState.value("truck_price") / 100.0))


func _add_stock(tree_id: String) -> void:
	stock.append(tree_id)
	_rebuild_stock()


## 丸太を売りに出す（丸太を売る枠に置いたとき）
func add_log(tree_id: String) -> void:
	log_stock.append(tree_id)
	_rebuild_logs()


## 板の山のいちばん上（次に置く場所）
func _pile_top() -> Vector3:
	return _stock_pile.top_global()


func _log_pile_top() -> Vector3:
	return _log_pile.top_global()


## 荷台の板の山（数は stock と同じ）
func _rebuild_stock() -> void:
	_stock_pile.show_items(stock)


## 売りに出した丸太の山（数は log_stock と同じ）
func _rebuild_logs() -> void:
	_log_pile.show_items(log_stock)
