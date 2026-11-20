extends Node3D
## ゲーム全体の組み立て。マップ・施設・木・プレイヤー・カメラ・UIを data/balance.json から生成する。
##
## マップ構成（上から見て、画面上方向が -Z）:
##   z > 0         : 拠点（製材所・出荷場）
##   z = 0 .. -20  : エリア0（最初から開放）
##   z = -20 .. -40: エリア1（柵の手前のパッドで支払うと開放）... 以降も同様
## 拠点に近いエリアほど柔らかい木が多く、遠いほど硬い木が多い（重みは JSON で設定）。

const SAWMILL_POS := Vector3(-5, 0, 9)
const DOCK_POS := Vector3(5.5, 0, 9)
const PLAYER_SPAWN := Vector3(1, 0, 4)
const FUEL_POS := Vector3(0, 0, 14)
## 機械の購入パッドと出現位置
const SHOP_POS := {"harvester": Vector3(-12, 0, 6), "hauler": Vector3(12, 0, 6)}
const MACHINE_SPAWN := {"harvester": Vector3(-12, 0, 11), "hauler": Vector3(12, 0, 11)}
## 川流し（左端）とトロッコ（右端）の通る位置。木はこの帯と積み込み枠のまわりには生やさない
const LINE_X := {"river": -16.5, "trolley": 16.5}
const LINE_CLEAR_X := 14.6

var player: Player
var camera: FollowCamera
var sawmill: Sawmill
var dock: ShipDock
var guide: GuideArrows
var lines: Dictionary = {}  # "river" / "trolley" -> LogLine
var hud: Hud
var lumberjacks: Array[Lumberjack] = []
var machines: Dictionary = {}  # kind -> Machine

var _area_ranges: Array[Vector2] = []  # 各エリアの (near_z, far_z)


func _ready() -> void:
	_compute_area_ranges()
	_build_environment()
	_build_ground()
	Decor.build(self, _area_ranges, _width(), float(GameData.world.get("base_depth", 18)), int(GameData.world.get("seed", 1)))
	_build_bounds()
	_build_facilities()
	_build_gates()
	_build_lines()
	_spawn_trees()
	_spawn_player()
	_build_camera()
	guide = GuideArrows.new()
	guide.player = player
	guide.sawmill = sawmill
	guide.dock = dock
	add_child(guide)
	hud = Hud.new()
	hud.guide = guide
	add_child(hud)
	hud.bind_player(player)
	_sync_lumberjacks()
	GameState.upgrade_changed.connect(func(id: String, _l: int) -> void:
		if id == "lumberjack":
			_sync_lumberjacks())
	GameState.lumberjack_role_changed.connect(func(i: int, role: String) -> void:
		if i < lumberjacks.size():
			lumberjacks[i].set_role(role))
	for kind in GameData.machines:
		if kind.begins_with("_"):
			continue
		if GameState.machine_rank(kind) > 0:
			_spawn_machine(kind)
	GameState.machine_changed.connect(_on_machine_changed)


func _unhandled_input(event: InputEvent) -> void:
	# デバッグ用ショートカット（リリース時は削除してよい）
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_F9:
				GameState.add_money(1000)
			KEY_F10:
				GameState.reset_game()
				get_tree().reload_current_scene()


# ---- マップ ----

func _width() -> float:
	return float(GameData.world.get("width", 40))


func _compute_area_ranges() -> void:
	var z := 0.0
	for area in GameData.areas:
		var depth := float(area.get("depth", 20))
		_area_ranges.append(Vector2(z, z - depth))
		z -= depth


func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	# 環境光は「上が涼しい青、下が土色」の半球ライトとして効かせる
	sky_mat.sky_top_color = Color("#7aa6d6")
	sky_mat.sky_horizon_color = Color("#c9d8e2")
	sky_mat.ground_horizon_color = Color("#8c7a5e")
	sky_mat.ground_bottom_color = Color("#4a3f30")
	sky_mat.sun_angle_max = 20.0
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.42
	env.ambient_light_sky_contribution = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.88
	env.tonemap_white = 6.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# 暖色の太陽を画面の左上から。少し低めにして影を長く
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-44, -140, 0)
	sun.light_color = Color("#ffe2b8")
	sun.light_energy = 1.05
	sun.light_angular_distance = 1.2
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.85
	sun.shadow_blur = 1.6
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	# 影の範囲をカメラに映る範囲にぴったり合わせて、2048px の影マップをくっきり使う
	sun.directional_shadow_max_distance = 18.0
	add_child(sun)


func _build_ground() -> void:
	var width := _width()
	var base_depth := float(GameData.world.get("base_depth", 18))
	# 拠点は踏み固められた土、森は草地（奥のエリアほど少し暗く、落ち着いた緑に）
	_add_ground_tile(width, base_depth, base_depth * 0.5, "yard", Color.WHITE)
	for i in GameData.areas.size():
		var r := _area_ranges[i]
		var tint := Color("#e6e2d4").lerp(Color("#c4ccb0"), minf(1.0, i * 0.22)).darkened(0.04 * i)
		_add_ground_tile(width, r.x - r.y, (r.x + r.y) * 0.5, "grass", tint)


func _add_ground_tile(width: float, depth: float, center_z: float, kind: String, tint: Color) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(width, depth)
	mesh.material = Mats.ground(kind, tint)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(0, 0, center_z)
	add_child(mi)


## プレイヤーがマップ外に出ないための見えない壁。
func _build_bounds() -> void:
	var width := _width()
	var near := float(GameData.world.get("base_depth", 18))
	var far: float = _area_ranges[-1].y if not _area_ranges.is_empty() else 0.0
	var length := near - far
	var center_z := (near + far) * 0.5
	_add_wall(Vector3(1, 4, length), Vector3(-width * 0.5 - 0.5, 2, center_z))
	_add_wall(Vector3(1, 4, length), Vector3(width * 0.5 + 0.5, 2, center_z))
	_add_wall(Vector3(width, 4, 1), Vector3(0, 2, near + 0.5))
	_add_wall(Vector3(width, 4, 1), Vector3(0, 2, far - 0.5))


func _add_wall(size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)


func _build_facilities() -> void:
	sawmill = Sawmill.new()
	sawmill.position = SAWMILL_POS
	add_child(sawmill)
	dock = ShipDock.new()
	dock.position = DOCK_POS
	add_child(dock)
	var fuel := FuelStation.new()
	fuel.position = FUEL_POS
	add_child(fuel)
	for kind in SHOP_POS:
		var shop := MachineShop.new()
		shop.kind = kind
		shop.position = SHOP_POS[kind]
		add_child(shop)


func _build_lines() -> void:
	for kind in LINE_X:
		var line := LogLine.new()
		line.kind = kind
		line.x = LINE_X[kind]
		line.far_z = _area_ranges[-1].y + 1.0
		line.near_z = 3.0
		line.sawmill = sawmill
		line.area_ranges = _area_ranges
		add_child(line)
		lines[kind] = line


func _build_gates() -> void:
	for i in range(1, GameData.areas.size()):
		if GameState.is_area_unlocked(i):
			continue
		var gate := AreaGate.new()
		gate.area_index = i
		gate.width = _width()
		gate.position = Vector3(0, 0, _area_ranges[i].x)
		add_child(gate)


func _spawn_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(GameData.world.get("seed", 1))
	var spacing := float(GameData.world.get("tree_min_spacing", 2.3))
	var half := _width() * 0.5 - 2.0
	var placed: Array[Vector3] = []
	var field := TreeField.new()
	field.name = "TreeField"
	add_child(field)
	for i in GameData.areas.size():
		var area: Dictionary = GameData.areas[i]
		var r := _area_ranges[i]
		var count := int(area.get("tree_count", 15))
		var attempts := 0
		var spawned := 0
		while spawned < count and attempts < count * 40:
			attempts += 1
			var pos := Vector3(rng.randf_range(-half, half), 0, rng.randf_range(r.y + 1.5, r.x - 2.0))
			if not _is_free_spot(pos, placed, spacing):
				continue
			var tree := ChoppableTree.new()
			tree.field = field
			tree.setup(GameData.tree_def(GameData.pick_tree_for_area(i, rng)), i, rng.randi() % ChoppableTree.VARIANTS)
			tree.position = pos
			tree.rotation.y = rng.randf() * TAU
			add_child(tree)
			placed.append(pos)
			spawned += 1
	field.build()


func _is_free_spot(pos: Vector3, placed: Array[Vector3], spacing: float) -> bool:
	# 中央の道は空けておく（機械が走りやすいように）
	if absf(pos.x) < 1.8 or absf(pos.x) > LINE_CLEAR_X:
		return false
	# 川岸・トロッコ駅の積み込み枠のまわり
	for i in _area_ranges.size():
		var cz := (_area_ranges[i].x + _area_ranges[i].y) * 0.5
		if absf(absf(pos.x) - 13.2) < 2.2 and absf(pos.z - cz) < 2.2:
			return false
	for p in placed:
		if Fx.xz_distance(p, pos) < spacing:
			return false
	# 柵の支払いパッドの周りは空けておく
	for i in range(1, _area_ranges.size()):
		if Fx.xz_distance(pos, Vector3(0, 0, _area_ranges[i].x + AreaGate.PAD_OFFSET.z)) < 3.5:
			return false
	return true


func _spawn_player() -> void:
	player = Player.new()
	player.position = PLAYER_SPAWN
	add_child(player)


func _build_camera() -> void:
	camera = FollowCamera.new()
	camera.target = player
	add_child(camera)
	camera.snap()


func _sync_lumberjacks() -> void:
	var wanted := roundi(GameState.value("lumberjack"))
	while lumberjacks.size() < wanted:
		var lj := Lumberjack.new()
		lj.index = lumberjacks.size()
		lj.role = GameState.lumberjack_role(lj.index)
		lj.sawmill = sawmill
		lj.position = sawmill.input_position() + Vector3(lumberjacks.size() * 0.8 - 1.0, 0, -1.0)
		add_child(lj)
		lumberjacks.append(lj)


# ---- 機械 ----

func _on_machine_changed(kind: String, rank: int) -> void:
	if machines.has(kind):
		(machines[kind] as Machine).set_rank(rank)
	else:
		_spawn_machine(kind, true)


func _spawn_machine(kind: String, fresh := false) -> void:
	var m := Machine.new()
	m.kind = kind
	m.rank = GameState.machine_rank(kind)
	var saved: Dictionary = GameState.machine_state.get(kind, {})
	if fresh or saved.is_empty():
		# 最初の燃料は満タン
		m.position = MACHINE_SPAWN[kind]
		m.fuel = float(GameData.machine_rank(kind, m.rank).get("fuel_max", 60))
	else:
		m.position = Vector3(float(saved.get("x", 0)), 0, float(saved.get("z", 0)))
		m.rotation.y = float(saved.get("ry", 0))
		m.fuel = float(saved.get("fuel", 0))
	add_child(m)
	machines[kind] = m
	if fresh:
		Fx.popup(m, m.global_position, "%s 登場！" % m.display_name(), Color("#ffe14d"))
