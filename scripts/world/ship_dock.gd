class_name ShipDock
extends Station
## 出荷場。製材ライン開放後、板をここに運ぶと荷台に積まれ、1枚ずつ売れていく。
## - 売れる速さは強化『出荷のペース』（枚/秒）。荷台に置ける数は dock.stock_max まで
## - 強化『板のコンベア』を開放すると、製材所の出口の板がコンベアで荷台へ自動で運ばれる

const PAD_RADIUS := 1.8
const SELL_ID := "dock"
const BELT_ID := "plank_belt"
const PILE_VISIBLE := 48

var sawmill: Sawmill
## 荷台に積まれて売れるのを待っている板（木のID）
var stock: Array[String] = []
## 製材所の出口 → 荷台のコンベア
var belt: Conveyor

var _zone: Zone
## 荷台の板の山。数は stock と同じで、売れた分だけ消える
var _stock_pile: Node3D
var _sell_progress := 0.0


func _ready() -> void:
	_zone = Zone.new(Vector2.ONE * PAD_RADIUS * 2.0, Color(0.5, 0.85, 0.55, 0.16))
	add_child(_zone)
	# 木の桟橋風の床と、出荷待ちの荷物
	add_child(Fx.box(Vector3(3.2, 0.14, 1.6), Color("#a8834f"), Vector3(0, 0.07, -2.6)))
	for i in 7:
		add_child(Fx.box(Vector3(0.03, 0.02, 1.6), Color("#7a5a33"), Vector3(-1.5 + i * 0.5, 0.15, -2.6)))
	add_child(Fx.box(Vector3(1.3, 0.12, 1.1), Color("#a8834f"), Vector3(-0.7, 0.2, -2.6), "wood"))
	_stock_pile = Node3D.new()
	_stock_pile.position = Vector3(-0.7, 0.26, -2.6)
	add_child(_stock_pile)
	var c1 := Props.crate(0.7)
	c1.position = Vector3(0.7, 0.14, -2.7)
	add_child(c1)
	var c2 := Props.crate(0.5, Color("#d8ab6a"))
	c2.position = Vector3(0.75, 0.84, -2.7)
	c2.rotation_degrees.y = 20.0
	add_child(c2)
	var signboard := Props.signboard("出荷場")
	signboard.position = Vector3(1.9, 0, -1.6)
	signboard.rotation_degrees.y = -20.0
	add_child(signboard)
	stock = GameState.stock_list("dock")
	GameState.saving.connect(func() -> void:
		var ids := stock.duplicate()
		if belt:
			ids.append_array(belt.ids_in_flight())
		GameState.stock["dock"] = ids)
	_build_belt()
	GameState.upgrade_changed.connect(func(_id: String, _level: int) -> void: _refresh())
	_refresh()
	_rebuild_stock()


func stock_max() -> int:
	return int(GameData.dock.get("stock_max", 40))


func has_room(incoming := 0) -> bool:
	return stock.size() + incoming < stock_max()


## 製材所の出口（コンベアの始点）から荷台の横（終点）までのベルトコンベア。強化で開放するまでは隠す
func _build_belt() -> void:
	if sawmill == null:
		return
	var from := sawmill.output_pile_position() - global_position
	var to := _stock_pile.position
	var start := Vector3(from.x + 1.0, 0, from.z)
	var turn_x := to.x - 2.0
	var path: Array[Vector3] = [start, Vector3(turn_x, 0, start.z), Vector3(turn_x, 0, to.z), Vector3(to.x - 0.9, 0, to.z)]
	belt = Conveyor.new()
	belt.path = path
	belt.rate_source = func() -> float: return GameState.value(BELT_ID)
	belt.take_source = sawmill.take_plank
	belt.room_source = func(n: int) -> bool: return has_room(n)
	belt.deliver = func(id: String) -> void: _add_stock(id)
	belt.make_mesh = func(id: String) -> Node3D: return Sawmill._plank_mesh(id)
	add_child(belt)


func _refresh() -> void:
	var unlocked := GameState.level("sawmill") > 0
	_zone.set_fill(Color(0.5, 0.85, 0.55, 0.16) if unlocked else Color(0.3, 0.3, 0.3, 0.2))
	if belt:
		belt.set_active(unlocked and GameState.level(BELT_ID) > 0)
	_update_label()


func _update_label() -> void:
	if GameState.level("sawmill") <= 0:
		_zone.set_text("出荷場", "（製材ラインで開放）")
		return
	var title := "板を置く"
	if stock.size() >= stock_max():
		title = "出荷場 満杯"
	elif not stock.is_empty():
		title = "出荷中"
	_zone.set_text(title, "板: %d / %d" % [stock.size(), stock_max()])


func _process(delta: float) -> void:
	if GameState.level("sawmill") <= 0:
		return
	# 運んできた板を荷台に置く（いっぱいなら持ったまま）
	for carrier in carriers_near(global_position, PAD_RADIUS, "plank_carriers"):
		var stack: CarryStack = carrier.stack
		if stack.count("plank") > 0 and has_room() and tick(carrier, "sell", delta):
			var item := stack.take("plank")
			Fx.fly_item(self, Sawmill._plank_mesh(item["tree"]), (carrier as Node3D).global_position + Vector3(0, 1.0, 0), _pile_top(), 0.25)
			_add_stock(item["tree"])
	# 荷台の板が1枚ずつ売れていく
	if stock.is_empty():
		_sell_progress = 0.0
	else:
		_sell_progress += GameState.value(SELL_ID) * delta
		while _sell_progress >= 1.0 and not stock.is_empty():
			_sell_progress -= 1.0
			_sell_one()
	_update_label()


func _add_stock(tree_id: String) -> void:
	stock.append(tree_id)
	_rebuild_stock()


func _sell_one() -> void:
	var tree_id: String = stock.pop_front()
	var top := _pile_top()
	_rebuild_stock()
	Fx.fly_item(self, Sawmill._plank_mesh(tree_id), top, top + Vector3(1.2, 1.6, -1.2), 0.35)
	var price := GameData.plank_price(tree_id)
	GameState.add_money(price)
	Fx.popup(self, _stock_pile.global_position + Vector3(0, 0.6, 0), "+¥%d" % price, Color("#ffe14d"))
	Fx.coin_pop(self, _stock_pile.global_position)
	Audio.play("sell", -6.0, 1.1)


func _pile_top() -> Vector3:
	return _stock_pile.global_position + Vector3(0, 0.1 + floori(mini(stock.size(), PILE_VISIBLE) / 4.0) * 0.17, 0)


## 荷台の板の山（4枚ずつ互い違いに積む）
func _rebuild_stock() -> void:
	for child in _stock_pile.get_children():
		child.queue_free()
	for i in mini(stock.size(), PILE_VISIBLE):
		var col := i % 4
		var row := floori(i / 4.0)
		var plank := Sawmill._plank_mesh(stock[i])
		plank.position = Vector3(0, 0.08 + row * 0.17, (col - 1.5) * 0.26)
		plank.rotation_degrees.y = 4.0 if row % 2 == 0 else -4.0
		_stock_pile.add_child(plank)
