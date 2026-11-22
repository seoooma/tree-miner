class_name ShipDock
extends Station
## 出荷場。製材ライン開放後、板や丸太をここに運ぶと荷台に積まれ、販売のトラックに積み込まれていく。
## - 板も丸太も同じ1つの枠に置ける。板は荷台の左の山、丸太は右の山に積まれる（丸太は板より安い。製材所が追いつかないときの逃がし先）
## - 積み込む速さは強化『出荷のペース』（個/秒）。荷台に置ける数に上限はない
## - トラックの積める数と走る速さは、乗り物タブの強化『販売のトラック』
## - トラックが満載になるか、積む物がしばらく無くなると、積み荷の代金が入ってトラックが拠点の外へ走り去る。
##   すぐに空のトラックが戻ってくる。戻ってきたトラックにも最初から1個ずつ積む
## - 強化『板のコンベア』を開放すると、製材所の出口の板がコンベアで荷台へ自動で運ばれる

## 板も丸太も置ける1つの枠（荷台の前の真ん中。大きさは製材所の枠と同じ）。中心は出荷場の原点からのずれ、大きさは幅×奥行き
const PAD_OFFSET := Vector3(1.6, 0, 0.1)
const PAD_SIZE := Vector2(3.2, 3.2)
const SELL_ID := "dock"
const BELT_ID := "plank_belt"
## 荷台（板敷きの床と板・丸太の山）の奥行き。製材所の作業列と同じにして、板のコンベアをまっすぐ平行に通す
const DECK_Z := Sawmill.ROW_Z
const LOG_PILE_OFFSET := Vector3(3.75, 0.26, DECK_Z)
## 荷台の板の山の位置
const STOCK_PILE_OFFSET := Vector3(-0.65, 0.26, DECK_Z)
## 販売のトラックを停める位置（荷台の奥。正面は +X で、拠点の外へ向かう）
const TRUCK_OFFSET := Vector3(2.0, 0, DECK_Z - 1.8)

var sawmill: Sawmill
## 隣の工房（工房に回す木の板・丸太は、トラックに積まずに工房のコンベアへ渡す）
var workshop: Workshop
## 荷台に積まれてトラックを待っている板（木のID）
var stock: Array[String] = []
## 丸太を売る枠の横に積まれてトラックを待っている丸太（木のID）
var log_stock: Array[String] = []
## 製材所の出口 → 荷台のコンベア
var belt: Conveyor
var truck: SaleTruck

var _zone: Zone
## 荷台の板の山。数は stock と同じで、トラックに積んだ分だけ消える
var _stock_pile: ItemPile
var _log_pile: ItemPile
## 積み込みの進み具合（1 で1個積む）。トラックが停まっている間だけ進み、1個分より多くは貯めない
var _load_progress := 0.0
## 積む物が無くなってからの秒数（積み荷があればこの秒数で出発する）
var _idle_time := 0.0


func _ready() -> void:
	_zone = Zone.new(PAD_SIZE, Color(0.5, 0.85, 0.55, 0.16))
	_zone.position = PAD_OFFSET
	add_child(_zone)
	# 木の桟橋風の床（左に板、右に丸太を積む）と、出荷待ちの荷物
	add_child(Fx.box(Vector3(6.6, 0.14, 1.6), Color("#c99a5e"), Vector3(1.65, 0.07, DECK_Z), "wood"))
	for i in 14:
		add_child(Fx.box(Vector3(0.03, 0.02, 1.6), Color("#9a7040"), Vector3(-1.5 + i * 0.48, 0.15, DECK_Z)))
	add_child(Fx.box(Vector3(1.9, 0.12, 1.3), Color("#b07f48"), Vector3(STOCK_PILE_OFFSET.x, 0.2, DECK_Z), "wood"))
	add_child(Fx.box(Vector3(1.6, 0.12, 1.3), Color("#b07f48"), Vector3(LOG_PILE_OFFSET.x, 0.2, DECK_Z), "wood"))
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
	c1.position = Vector3(1.55, 0.14, DECK_Z - 0.15)
	add_child(c1)
	var c2 := Props.crate(0.45, Color("#d8ab6a"))
	c2.position = Vector3(1.6, 0.74, DECK_Z - 0.15)
	c2.rotation_degrees.y = 20.0
	add_child(c2)
	var signboard := Props.signboard("出荷場", Color("#3b8fe0"))
	signboard.position = Vector3(-2.6, 0, -1.9)
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
		elif parts.size() == 2 and parts[0] == "goods" and not GameData.recipe_def(parts[1]).is_empty():
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


## トラック1台に積める数（強化『販売のトラック』）
static func truck_capacity() -> int:
	return maxi(1, roundi(GameState.value("truck_capacity")))


## 製材所の出口（コンベアの始点）から荷台の横（終点）までのベルトコンベア。強化で開放するまでは隠す
func _build_belt() -> void:
	if sawmill == null:
		return
	var from := sawmill.output_pile_position() - global_position
	var to := _stock_pile.position
	# 製材所の板置き場の右から荷台の左まで、曲げずに1本のまっすぐなベルトでつなぐ（同じ奥行きなので平行）
	var start := Vector3(from.x + 1.3, 0, from.z)
	var path: Array[Vector3] = [start, Vector3(to.x - 1.15, 0, to.z)]
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
	if belt:
		belt.set_active(unlocked and GameState.level(BELT_ID) > 0)
	_update_label()


func _update_label() -> void:
	if GameState.level("sawmill") <= 0:
		_zone.set_text("出荷場", "（製材ラインで開放）")
		return
	var title := "板・丸太を置く"
	if not stock.is_empty() or not log_stock.is_empty():
		title = "出荷中"
	var for_workshop := _count_for_workshop(stock, "plank") + _count_for_workshop(log_stock, "log")
	_zone.set_text(title, "板: %d　丸太: %d" % [stock.size(), log_stock.size()] + ("（工房へ %d）" % for_workshop if for_workshop > 0 else ""))


func _process(delta: float) -> void:
	if GameState.level("sawmill") <= 0:
		return
	# 運んできた板と丸太を、同じ枠から荷台に置く（板は左の山、丸太は右の山。1回に1個ずつ交互に）
	for carrier in carriers_on_pad():
		var stack: CarryStack = carrier.stack
		var from := (carrier as Node3D).global_position + Vector3(0, 1.0, 0)
		var has_plank := stack.count("plank") > 0 and carrier.is_in_group("plank_carriers")
		var has_log := stack.count("log") > 0
		if not (has_plank or has_log) or not tick(carrier, "sell", delta):
			continue
		if has_plank and (not has_log or stack.count("plank") >= stack.count("log")):
			var item := stack.take("plank")
			Fx.fly_item(self, Sawmill._plank_mesh(item["tree"]), from, _pile_top(), 0.25)
			_add_stock(item["tree"])
		else:
			var item := stack.take("log")
			Fx.fly_item(self, LogDrop.make_log_mesh(item["tree"]), from, _log_pile_top(), 0.25)
			add_log(item["tree"])
	_process_truck(delta)
	_update_label()


## 出荷の枠（横長の角丸の四角）に乗っている運搬者
func carriers_on_pad() -> Array[Node]:
	var result: Array[Node] = []
	var center := pad_position()
	for node in get_tree().get_nodes_in_group("carriers"):
		var reach := float(node.get_meta("pad_reach", 0.0))
		var d := (node as Node3D).global_position - center
		if absf(d.x) <= PAD_SIZE.x * 0.5 + reach and absf(d.z) <= PAD_SIZE.y * 0.5 + reach:
			result.append(node)
	return result


## 出荷の枠の中心（自動移動や案内の矢印の行き先）
func pad_position() -> Vector3:
	return global_position + PAD_OFFSET


## 荷台の板・丸太を、出荷のペースでトラックに積む。満載か、積む物がしばらく無ければ出発
func _process_truck(delta: float) -> void:
	var capacity := truck_capacity()
	var has_goods := _loadable_count() > 0
	# 積み込みはトラックが停まっている間だけ進め、1個ずつ積む（貯めておいて一度にまとめて積むと、
	# 戻ってきたトラックの1段目が一瞬で埋まって見えるため）
	if not truck.is_parked():
		_load_progress = 0.0
		return
	if has_goods:
		_load_progress = minf(_load_progress + GameState.value(SELL_ID) * delta, 1.0)
	else:
		_load_progress = minf(_load_progress, 1.0)
	while _load_progress >= 1.0 and truck.cargo.size() < capacity and _loadable_count() > 0:
		_load_progress -= 1.0
		_load_one()
	if truck.cargo.is_empty():
		_idle_time = 0.0
		return
	if _loadable_count() > 0:
		_idle_time = 0.0
	else:
		_idle_time += delta
	if truck.cargo.size() >= capacity or _idle_time >= float(GameData.dock.get("depart_idle_sec", 2.5)):
		_depart()


## 工房に回す（トラックに積まない）木の数
static func _count_for_workshop(ids: Array[String], kind: String) -> int:
	var n := 0
	for id in ids:
		if GameState.is_for_workshop(kind, id):
			n += 1
	return n


## いまトラックに積める数（工房に回す板・丸太を除き、工房でできた品を含む）
func _loadable_count() -> int:
	var n := stock.size() - _count_for_workshop(stock, "plank") + log_stock.size() - _count_for_workshop(log_stock, "log")
	if workshop:
		n += workshop.goods.size()
	return n


## 山の上から見て、最初に見つかる工房に回さない品の位置（無ければ -1）
static func _last_loadable(ids: Array[String], kind: String) -> int:
	for i in range(ids.size() - 1, -1, -1):
		if not GameState.is_for_workshop(kind, ids[i]):
			return i
	return -1


## 工房のコンベアに1つ渡す（工房に回す板、無ければ丸太）。"plank:pine" の形。無ければ空文字
func take_for_workshop() -> String:
	for i in range(stock.size() - 1, -1, -1):
		if GameState.is_for_workshop("plank", stock[i]):
			var id: String = stock[i]
			stock.remove_at(i)
			_rebuild_stock()
			return "plank:" + id
	for i in range(log_stock.size() - 1, -1, -1):
		if GameState.is_for_workshop("log", log_stock[i]):
			var id: String = log_stock[i]
			log_stock.remove_at(i)
			_rebuild_logs()
			return "log:" + id
	return ""


## 荷台から1個トラックに積む（積める数がいちばん多い山から。工房に回す板・丸太は積まない）
func _load_one() -> void:
	var plank_at := _last_loadable(stock, "plank")
	var log_at := _last_loadable(log_stock, "log")
	var n_planks := stock.size() - _count_for_workshop(stock, "plank")
	var n_logs := log_stock.size() - _count_for_workshop(log_stock, "log")
	var n_goods := workshop.goods.size() if workshop else 0
	if n_goods > 0 and n_goods >= n_planks and n_goods >= n_logs:
		var from := workshop.goods_top()
		var goods_id := workshop.take_goods()
		Fx.fly_item(self, Workshop.goods_mesh(goods_id), from, truck.next_slot_position(), 0.4)
		truck.add_cargo("goods", goods_id)
	elif log_at >= 0 and n_logs > n_planks:
		var log_id: String = log_stock[log_at]
		log_stock.remove_at(log_at)
		var from := _log_pile_top()
		_rebuild_logs()
		Fx.fly_item(self, LogDrop.make_log_mesh(log_id), from, truck.next_slot_position(), 0.3)
		truck.add_cargo("log", log_id)
	elif plank_at >= 0:
		var plank_id: String = stock[plank_at]
		stock.remove_at(plank_at)
		var from := _pile_top()
		_rebuild_stock()
		Fx.fly_item(self, Sawmill._plank_mesh(plank_id), from, truck.next_slot_position(), 0.3)
		truck.add_cargo("plank", plank_id)
	else:
		return
	Audio.play("drop", -14.0, 1.25)


## 積み荷の代金を受け取って、トラックを走らせる
func _depart() -> void:
	var total := 0
	var bonus := 0
	for item in truck.cargo:
		var price := cargo_price(item)
		total += price
		# 注文に合う品は数えられ、割増の代金が入る
		var kind := str(item.get("kind", ""))
		var tree_id := str(item.get("tree", ""))
		if kind == "goods":
			# 工房の品の注文は、品の材料の木で数える
			tree_id = str(GameData.recipe_def(tree_id).get("tree", ""))
		bonus += Orders.record_sale(kind, tree_id, price)
	GameState.add_money(total + bonus)
	var at := truck.global_position + Vector3(-0.8, 2.0, 0)
	Fx.popup(self, at, "+¥%d" % (total + bonus), Color("#ffe14d"), 84)
	if bonus > 0:
		Fx.popup(self, at + Vector3(0, 1.1, 0), "注文 +¥%d" % bonus, Color("#ff9d1e"), 60)
	for i in mini(4, 1 + truck.cargo.size() / 8):
		Fx.coin_pop(self, at + Vector3(randf_range(-1.2, 1.2), -1.0, 0))
	Audio.play("sell", -4.0, 1.0)
	Audio.play("board", -12.0, 0.8)
	_idle_time = 0.0
	truck.depart()


static func cargo_price(item: Dictionary) -> int:
	if item.get("kind", "") == "goods":
		return GameData.goods_price(str(item.get("tree", "")))
	if item.get("kind", "") == "log":
		return GameData.log_price(str(item.get("tree", "")))
	return GameData.plank_price(str(item.get("tree", "")))


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
