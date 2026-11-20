class_name ShipDock
extends Station
## 出荷場。製材ライン開放後、板をここに運ぶと売れる。

const PAD_RADIUS := 1.8

var _zone: Zone


func _ready() -> void:
	_zone = Zone.new(Vector2.ONE * PAD_RADIUS * 2.0, Color(0.5, 0.85, 0.55, 0.16))
	add_child(_zone)
	# 木の桟橋風の床と、出荷待ちの荷物
	add_child(Fx.box(Vector3(3.2, 0.14, 1.6), Color("#a8834f"), Vector3(0, 0.07, -2.6)))
	for i in 7:
		add_child(Fx.box(Vector3(0.03, 0.02, 1.6), Color("#7a5a33"), Vector3(-1.5 + i * 0.5, 0.15, -2.6)))
	var pallet := Props.pallet_of_planks()
	pallet.position = Vector3(-0.7, 0.14, -2.6)
	add_child(pallet)
	var c1 := Props.crate(0.7)
	c1.position = Vector3(0.7, 0.14, -2.7)
	add_child(c1)
	var c2 := Props.crate(0.5, Color("#d8ab6a"))
	c2.position = Vector3(0.75, 0.84, -2.7)
	c2.rotation_degrees.y = 20.0
	add_child(c2)
	var sign := Props.signboard("出荷場")
	sign.position = Vector3(1.9, 0, -1.6)
	sign.rotation_degrees.y = -20.0
	add_child(sign)
	GameState.upgrade_changed.connect(func(_id: String, _level: int) -> void: _refresh())
	_refresh()


func _refresh() -> void:
	var unlocked := GameState.level("sawmill") > 0
	_zone.set_text("出荷場", "板を売る" if unlocked else "（製材ラインで開放）")
	_zone.set_fill(Color(0.5, 0.85, 0.55, 0.16) if unlocked else Color(0.3, 0.3, 0.3, 0.2))


func _process(delta: float) -> void:
	if GameState.level("sawmill") <= 0:
		return
	for carrier in carriers_near(global_position, PAD_RADIUS, "plank_carriers"):
		var stack: CarryStack = carrier.stack
		if stack.count("plank") > 0 and tick(carrier, "sell", delta):
			var item := stack.take("plank")
			var price := GameData.plank_price(item["tree"])
			GameState.add_money(price)
			Fx.popup(self, global_position, "+¥%d" % price, Color("#ffe14d"))
			Fx.coin_pop(self, global_position)
			Audio.play("sell", -6.0, 1.1)
