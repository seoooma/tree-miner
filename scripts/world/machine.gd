class_name Machine
extends CharacterBody3D
## プレイヤーが乗って運転する機械。
## - harvester（伐採機）: 近くの木を高速で切り倒す
## - hauler（運搬車）: 落ちている丸太を大量に拾い、製材所の投入口に横付けすると降ろす
## 燃料は「動作秒数」。走っている間・伐採している間だけ減り、乗っているだけでは減らない。
## 燃料が 0 になると動けない。燃料缶を持って近づくと補給される。
## 性能はランク（data/balance.json の machines）で決まり、強化画面で上位ランクを買うとその場で強化される。

const FUEL_KIND := "fuel"

var kind := "harvester"
var rank := 1
var fuel := 0.0
var driver: Player = null
## 運搬車の荷台（伐採機は null）
var stack: CarryStack

var _visual: Node3D
var _fuel_label: Label3D
var _saw: Node3D
var _chop_timer := 0.0
var _refuel_timer := 0.0
var _wheels: Array[Node] = []
## 排気の煙・走ったときの土ぼこり・伐採中のおがくず
var _exhaust: CPUParticles3D
var _dust: CPUParticles3D
var _cut_fx: CPUParticles3D


func _ready() -> void:
	add_to_group("machines")
	add_to_group("nav_boxes")
	set_meta("nav_size", Vector2(1.6, 2.4))
	collision_layer = 1
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 1.2, 2.4)
	shape.shape = box
	shape.position.y = 0.6
	add_child(shape)

	_visual = Node3D.new()
	add_child(_visual)
	# 燃料・積荷は HUD がバーで表示する（この文字は非表示）
	_fuel_label = Fx.label3d("", Vector3(0, 2.4, 0), 36)
	_fuel_label.visible = false
	add_child(_fuel_label)

	if kind == "hauler":
		add_to_group("carriers")
		add_to_group("plank_carriers")
		set_meta("pad_reach", 1.4)
		stack = CarryStack.new()
		stack.capacity_source = func() -> int: return int(spec().get("capacity", 20))
		stack.columns = 2
		stack.rows = 3
		stack.item_spacing = Vector2(0.3, 0.32)
		stack.position = Vector3(0, 0.95, -0.65)
		stack.rotation_degrees.y = 90.0
		add_child(stack)
	_build_visual()
	_build_effects()


func _build_effects() -> void:
	_exhaust = Vfx.make_smoke(10, 0.28, Color(0.36, 0.36, 0.38))
	_exhaust.position = Vector3(0.42, 1.25, -0.75)
	_exhaust.emitting = false
	add_child(_exhaust)
	_dust = Vfx.make_smoke(10, 0.5, Color("#d6c6a2"))
	_dust.position = Vector3(0, 0.15, -1.1)
	_dust.direction = Vector3(0, 0.6, -1)
	_dust.gravity = Vector3(0, 0.2, 0)
	_dust.emitting = false
	add_child(_dust)
	if kind == "harvester":
		_cut_fx = Vfx.make_sawdust(Vector3(0, 0.8, -0.6).normalized())
		_cut_fx.position = Vector3(0, 0.75, 1.75)
		_cut_fx.emitting = false
		add_child(_cut_fx)


func _update_effects(cutting: bool) -> void:
	var engine_on := driver != null and fuel > 0.0
	if _exhaust.emitting != engine_on:
		_exhaust.emitting = engine_on
	var rolling := velocity.length() > 1.0
	if _dust.emitting != rolling:
		_dust.emitting = rolling
	if _cut_fx and _cut_fx.emitting != cutting:
		_cut_fx.emitting = cutting


func spec() -> Dictionary:
	return GameData.machine_rank(kind, rank)


func fuel_max() -> float:
	return float(spec().get("fuel_max", 60))


func display_name() -> String:
	return str(spec().get("name", GameData.machine_name(kind)))


## 上位ランクを購入したとき。燃料は満タンにする。
func set_rank(new_rank: int) -> void:
	rank = new_rank
	fuel = fuel_max()
	_build_visual()


func seat_position() -> Vector3:
	return global_position + global_transform.basis * Vector3(0, 1.3, 0.1)


func exit_position() -> Vector3:
	var p := global_position + global_transform.basis * Vector3(1.8, 0, 0)
	p.y = 0.0
	return p


## トラックモデルの向き補正（モデルの正面を +Z に合わせる）
const MODEL_YAW := 0.0
## ランクごとの車体（Kenney Car Kit）。伐採機はトラクター、運搬車は荷台付きのトラック。
const MODELS := {
	"harvester": ["tractor", "tractor-shovel", "tractor-shovel"],
	"hauler": ["truck", "truck-flat", "delivery-flat"],
}


func _build_visual() -> void:
	for child in _visual.get_children():
		child.queue_free()
	_wheels.clear()
	var color := Color(spec().get("color", "#e8b030"))
	var names: Array = MODELS.get(kind, MODELS["hauler"])
	var truck := Fx.model("res://assets/kenney/car/%s.glb" % names[clampi(rank - 1, 0, names.size() - 1)])
	truck.rotation.y = MODEL_YAW
	truck.scale = Vector3.ONE * 0.95
	# ショベルの代わりに伐採用のノコギリを付けるので、元のショベルは隠す
	var shovel := truck.find_child("shovel", true, false) as Node3D
	if shovel:
		shovel.visible = false
	_visual.add_child(truck)
	for n in truck.find_children("wheel-*", "", true, false):
		_wheels.append(n)
	# 塗装金属のツヤとムラ
	for mi in truck.find_children("*", "MeshInstance3D", true, false):
		var src := (mi as MeshInstance3D).mesh.surface_get_material(0) as BaseMaterial3D
		if src and src.albedo_texture:
			(mi as MeshInstance3D).material_override = Mats.truck(src.albedo_texture)
	if kind == "harvester":
		# 前方に伸びるアームと回転ノコギリ
		_visual.add_child(Fx.box(Vector3(0.18, 0.18, 0.9), color.darkened(0.35), Vector3(0.0, 0.8, 1.2)))
		_visual.add_child(Fx.box(Vector3(1.3, 0.12, 0.18), Color("#555b61"), Vector3(0.0, 0.62, 1.6), "metal"))
		_saw = Node3D.new()
		_saw.position = Vector3(0.0, 0.62, 1.7)
		_visual.add_child(_saw)
		for x in [-0.42, 0.42]:
			var blade := Fx.cylinder(0.32, 0.05, Color("#c9ced3"), Vector3(x, 0, 0), -1.0, 14, false, "metal")
			blade.rotation_degrees.z = 90.0
			_saw.add_child(blade)
			var hub := Fx.cylinder(0.08, 0.07, Color("#3a3f44"), Vector3(x, 0, 0), -1.0, 8)
			hub.rotation_degrees.z = 90.0
			_saw.add_child(hub)
	# ランク表示（屋根の上の星）。車体の高さに合わせる
	var top := 1.5
	for mi in truck.find_children("*", "MeshInstance3D", true, false):
		var box := (mi as MeshInstance3D).get_aabb()
		top = maxf(top, (box.position.y + box.size.y) * truck.scale.y)
	for i in rank:
		_visual.add_child(Fx.sphere(0.09, Color("#ffd84a"), Vector3(-0.25 + i * 0.25, top + 0.12, -0.1), 6, 3, true))


func _physics_process(delta: float) -> void:
	var working := false
	var input := driver.move_input() if driver else Vector2.ZERO
	var has_fuel := fuel > 0.0

	if driver and has_fuel and input.length() > 0.05:
		var dir := Vector3(input.x, 0.0, input.y)
		velocity = dir * float(spec().get("speed", 6.0))
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), minf(1.0, delta * 6.0))
		working = true
	else:
		velocity = Vector3.ZERO
	move_and_slide()
	position.y = 0.0

	var cutting := false
	if driver and has_fuel:
		if kind == "harvester":
			cutting = _update_harvest(delta)
			working = cutting or working
		elif kind == "hauler":
			LogDrop.collect_near(self, stack, float(spec().get("pickup_radius", 2.5)))

	if working:
		fuel = maxf(0.0, fuel - delta)
	if _saw:
		_saw.rotation_degrees.x += delta * (900.0 if driver and has_fuel else 0.0)
	var spin := velocity.length() * delta / 0.3
	for w in _wheels:
		(w as Node3D).rotate_object_local(Vector3.RIGHT, spin)

	_update_effects(cutting)
	_refuel_from_player(delta)
	_update_label()
	_save_state()


## 伐採機: 範囲内の木を切る。切っていれば true。
func _update_harvest(delta: float) -> bool:
	var tree := _find_tree()
	if tree == null:
		return false
	_chop_timer -= delta
	if _chop_timer <= 0.0:
		_chop_timer = float(spec().get("chop_interval", 0.35))
		tree.hit(float(spec().get("chop_power", 3)), global_position)
	return true


func _find_tree() -> ChoppableTree:
	var best: ChoppableTree = null
	var best_dist := INF
	var reach := float(spec().get("chop_range", 2.0))
	for node in get_tree().get_nodes_in_group("trees"):
		var tree := node as ChoppableTree
		if not tree.alive or not GameState.is_area_unlocked(tree.area_index):
			continue
		var d := Fx.xz_distance(global_position, tree.global_position) - tree.radius
		if d <= reach and d < best_dist:
			best = tree
			best_dist = d
	return best


## 燃料缶を持ったプレイヤー（徒歩）が近くにいれば補給する。
func _refuel_from_player(delta: float) -> void:
	_refuel_timer -= delta
	if _refuel_timer > 0.0:
		return
	var per_can := float(GameData.fuel.get("per_can", 20))
	for node in get_tree().get_nodes_in_group("player"):
		var p := node as Player
		if p.vehicle != null or p.stack.count(FUEL_KIND) == 0:
			continue
		if Fx.xz_distance(p.global_position, global_position) > float(GameData.player.get("board_range", 3.0)):
			continue
		if fuel >= fuel_max() - 0.01:
			continue
		p.stack.take(FUEL_KIND)
		fuel = minf(fuel_max(), fuel + per_can)
		_refuel_timer = 0.2
		Fx.popup(self, global_position, "燃料 +%d" % roundi(per_can), Color("#ff9a7a"))
		Audio.play("fuel", -4.0, 0.8)


func _update_label() -> void:
	var text := "%s\n燃料 %d/%d" % [display_name(), ceili(fuel), roundi(fuel_max())]
	if fuel <= 0.0:
		text += "\n燃料切れ"
	if stack:
		text += "\n積荷 %d/%d" % [stack.size(), stack.capacity()]
	_fuel_label.text = text
	_fuel_label.modulate = Color("#ff8a7a") if fuel <= 0.0 else Color.WHITE


func _save_state() -> void:
	GameState.machine_state[kind] = {
		"fuel": fuel,
		"x": global_position.x,
		"z": global_position.z,
		"ry": rotation.y,
	}
