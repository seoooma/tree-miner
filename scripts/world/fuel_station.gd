class_name FuelStation
extends Station
## 給油所。上に立つと燃料缶を無料で受け取れる（運搬容量を使う）。缶を持って機械に近づくと補給される。

const PAD_RADIUS := 1.4
const GIVE_INTERVAL := 0.25


func _ready() -> void:
	var zone := Zone.new(Vector2.ONE * PAD_RADIUS * 2.0, Color(0.95, 0.4, 0.3, 0.16))
	add_child(zone)
	zone.set_text("給油所", "燃料缶（無料）")
	# 給油機と屋根
	add_child(Fx.box(Vector3(2.8, 0.1, 2.0), Color("#a3a39b"), Vector3(0, 0.05, -2.0)))
	add_child(Fx.box(Vector3(0.7, 1.4, 0.5), Color("#c43a2e"), Vector3(-0.5, 0.75, -2.2), "metal"))
	add_child(Fx.box(Vector3(0.5, 0.35, 0.04), Color("#f4f4f0"), Vector3(-0.5, 1.15, -1.94)))
	add_child(Fx.box(Vector3(0.5, 0.12, 0.04), Color("#2b2b2b"), Vector3(-0.5, 0.85, -1.94)))
	add_child(Fx.cylinder(0.04, 0.8, Color("#2b2b2b"), Vector3(-0.15, 0.7, -2.0), -1.0, 6))
	add_child(Fx.box(Vector3(3.0, 0.16, 2.2), Color("#f4f4f0"), Vector3(0, 2.5, -2.0)))
	add_child(Fx.box(Vector3(3.02, 0.12, 2.22), Color("#c43a2e"), Vector3(0, 2.4, -2.0), "metal"))
	for x in [-1.3, 1.3]:
		add_child(Fx.cylinder(0.08, 2.4, Color("#d8d8d4"), Vector3(x, 1.2, -2.0), -1.0, 10, false, "metal"))
	# 燃料缶の山
	for i in 3:
		add_child(_can(Vector3(0.5 + i * 0.32, 0.1, -2.3)))
	add_child(_can(Vector3(0.66, 0.42, -2.3)))


static func _can(pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.add_child(Fx.box(Vector3(0.26, 0.32, 0.16), Color("#c43a2e"), Vector3(0, 0.16, 0), "metal"))
	root.add_child(Fx.box(Vector3(0.12, 0.05, 0.05), Color("#2b2b2b"), Vector3(0.04, 0.34, 0)))
	return root


func _process(delta: float) -> void:
	for carrier in carriers_near(global_position, PAD_RADIUS, "player"):
		var p := carrier as Player
		if p.vehicle == null and not p.stack.is_full() and tick(carrier, "fuel", delta, GIVE_INTERVAL):
			p.stack.add({"kind": Machine.FUEL_KIND})
			Audio.play("fuel", -6.0, 1.2)
