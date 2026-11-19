class_name ShipDock
extends Station
## 出荷場。製材ライン開放後、板をここに運ぶと売れる。

const PAD_RADIUS := 1.8

var _label: Label3D
var _pad: MeshInstance3D


func _ready() -> void:
	_pad = Fx.pad(PAD_RADIUS, Color("#7fd18a"))
	add_child(_pad)
	add_child(Fx.box(Vector3(1.6, 0.2, 1.2), Color("#a8834f"), Vector3(0, 0.1, -2.4)))
	add_child(Fx.box(Vector3(1.0, 0.8, 0.8), Color("#c99a5b"), Vector3(-0.3, 0.6, -2.4)))
	add_child(Fx.box(Vector3(0.1, 1.6, 0.1), Color("#6b4a2a"), Vector3(1.2, 0.8, -1.8)))
	_label = Fx.label3d("", Vector3(0, 2.4, -1.6), 48)
	add_child(_label)
	GameState.upgrade_changed.connect(func(_id: String, _level: int) -> void: _refresh())
	_refresh()


func _refresh() -> void:
	var unlocked := GameState.level("sawmill") > 0
	_label.text = "出荷場\n板を売る" if unlocked else "出荷場\n（製材ラインで開放）"
	_pad.transparency = 0.0 if unlocked else 0.6


func _process(delta: float) -> void:
	if GameState.level("sawmill") <= 0:
		return
	for carrier in carriers_near(global_position, PAD_RADIUS, true):
		var stack: CarryStack = carrier.stack
		if stack.count("plank") > 0 and tick(carrier, "sell", delta):
			var item := stack.take("plank")
			var price := GameData.plank_price(item["tree"])
			GameState.add_money(price)
			Fx.popup(self, global_position, "+¥%d" % price, Color("#ffe14d"))
