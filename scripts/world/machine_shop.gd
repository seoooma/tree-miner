class_name MachineShop
extends Station
## 機械の購入パッド。上に立つと少しずつ支払い、払い終わると機械が出現（2回目以降は既存の機械がランクアップ）。

const PAD_RADIUS := 1.4
const PAY_STEPS := 60.0

var kind := "harvester"

var _pad_root: Node3D
var _label: Label3D
## 購入直後は、一度パッドから降りるまで次のランクの支払いを始めない
var _wait_leave := false


func _ready() -> void:
	_pad_root = Node3D.new()
	add_child(_pad_root)
	_pad_root.add_child(Fx.pad(PAD_RADIUS, Color("#b07ae0")))
	_label = Fx.label3d("", Vector3(0, 1.6, 0), 44)
	add_child(_label)
	GameState.machine_changed.connect(func(_k: String, _r: int) -> void: _update_label())
	_update_label()


func _update_label() -> void:
	var title := GameData.machine_name(kind)
	if GameState.machine_is_maxed(kind):
		_label.text = "%s\n最高ランク" % title
		_pad_root.visible = false
		return
	var next := GameData.machine_rank(kind, GameState.machine_rank(kind) + 1)
	var verb := "購入" if GameState.machine_rank(kind) == 0 else "ランクアップ"
	_label.text = "%s %s\n¥%d" % [next.get("name", title), verb, GameState.shop_remaining(kind)]


func _process(delta: float) -> void:
	if GameState.machine_is_maxed(kind):
		return
	var chunk := maxi(1, ceili(GameState.machine_next_cost(kind) / PAY_STEPS))
	var on_pad := carriers_near(global_position, PAD_RADIUS, "player")
	if on_pad.is_empty():
		_wait_leave = false
		return
	if _wait_leave:
		return
	for carrier in on_pad:
		if (carrier as Player).vehicle == null and GameState.money > 0 and tick(carrier, "pay", delta, 0.03):
			var rank_before := GameState.machine_rank(kind)
			GameState.pay_toward_machine(kind, chunk)
			if GameState.machine_rank(kind) != rank_before:
				_wait_leave = true
			_update_label()
