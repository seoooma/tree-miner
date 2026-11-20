class_name FuelStation
extends Station
## 給油所。上に立つと燃料缶を無料で受け取れる（運搬容量を使う）。缶を持って機械に近づくと補給される。

const PAD_RADIUS := 1.4
const GIVE_INTERVAL := 0.25


func _ready() -> void:
	add_child(Fx.pad(PAD_RADIUS, Color("#e8695a")))
	add_child(Fx.box(Vector3(0.8, 1.6, 0.6), Color("#d83a2e"), Vector3(0, 0.8, -2.0)))
	add_child(Fx.box(Vector3(0.6, 0.4, 0.05), Color("#ffffff"), Vector3(0, 1.2, -1.68)))
	add_child(Fx.box(Vector3(2.4, 0.15, 1.6), Color("#8c8c8c"), Vector3(0, 2.4, -1.6)))
	add_child(Fx.box(Vector3(0.12, 2.4, 0.12), Color("#6c6c6c"), Vector3(-1.0, 1.2, -1.0)))
	add_child(Fx.box(Vector3(0.12, 2.4, 0.12), Color("#6c6c6c"), Vector3(1.0, 1.2, -1.0)))
	add_child(Fx.label3d("給油所\n燃料缶（無料）", Vector3(0, 3.1, -1.6), 44))


func _process(delta: float) -> void:
	for carrier in carriers_near(global_position, PAD_RADIUS, "player"):
		var p := carrier as Player
		if p.vehicle == null and not p.stack.is_full() and tick(carrier, "fuel", delta, GIVE_INTERVAL):
			p.stack.add({"kind": Machine.FUEL_KIND})
