extends Node3D
## ゲーム全体の組み立て。マップ・施設・木・プレイヤー・カメラ・UIを data/balance.json から生成する。
##
## マップ構成（上から見て、画面上方向が -Z）:
##   z > 0         : 拠点（製材所・出荷場）
##   z = 0 .. -20  : エリア0（最初から開放）
##   z = -20 .. -40: エリア1（柵の手前のパッドで支払うと開放）... 以降も同様
## 拠点に近いエリアほど柔らかい木が多く、遠いほど硬い木が多い（重みは JSON で設定）。

const CAMERA_OFFSET := Vector3(0, 15, 11)
const CAMERA_FOLLOW_SPEED := 6.0

const SAWMILL_POS := Vector3(-5, 0, 9)
const DOCK_POS := Vector3(5.5, 0, 9)
const PLAYER_SPAWN := Vector3(1, 0, 4)

var player: Player
var camera: Camera3D
var sawmill: Sawmill
var hud: Hud
var lumberjacks: Array[Lumberjack] = []

var _area_ranges: Array[Vector2] = []  # 各エリアの (near_z, far_z)


func _ready() -> void:
	_compute_area_ranges()
	_build_environment()
	_build_ground()
	_build_bounds()
	_build_facilities()
	_build_gates()
	_spawn_trees()
	_spawn_player()
	_build_camera()
	hud = Hud.new()
	add_child(hud)
	hud.bind_player(player)
	_sync_lumberjacks()
	GameState.upgrade_changed.connect(func(id: String, _l: int) -> void:
		if id == "lumberjack":
			_sync_lumberjacks())


func _process(delta: float) -> void:
	var target := player.global_position + CAMERA_OFFSET
	camera.global_position = camera.global_position.lerp(target, minf(1.0, delta * CAMERA_FOLLOW_SPEED))


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
	sky_mat.sky_top_color = Color("#6fb3e8")
	sky_mat.sky_horizon_color = Color("#cfe8f5")
	sky_mat.ground_horizon_color = Color("#cfe8f5")
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#b8c8d8")
	env.ambient_light_energy = 0.45
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)


func _build_ground() -> void:
	var width := _width()
	var base_depth := float(GameData.world.get("base_depth", 18))
	_add_ground_tile(width, base_depth, base_depth * 0.5, Color("#c9b07a"))
	for i in GameData.areas.size():
		var r := _area_ranges[i]
		_add_ground_tile(width, r.x - r.y, (r.x + r.y) * 0.5, Color(GameData.areas[i].get("ground_color", "#7fbf5a")))


func _add_ground_tile(width: float, depth: float, center_z: float, color: Color) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(width, depth)
	mesh.material = Fx.material(color)
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
	var dock := ShipDock.new()
	dock.position = DOCK_POS
	add_child(dock)


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
			tree.setup(GameData.tree_def(GameData.pick_tree_for_area(i, rng)), i)
			tree.position = pos
			tree.rotation.y = rng.randf() * TAU
			add_child(tree)
			placed.append(pos)
			spawned += 1


func _is_free_spot(pos: Vector3, placed: Array[Vector3], spacing: float) -> bool:
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
	camera = Camera3D.new()
	camera.fov = 50.0
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	add_child(camera)
	camera.look_at_from_position(player.global_position + CAMERA_OFFSET, player.global_position)
	camera.current = true


func _sync_lumberjacks() -> void:
	var wanted := roundi(GameState.value("lumberjack"))
	while lumberjacks.size() < wanted:
		var lj := Lumberjack.new()
		lj.sawmill = sawmill
		lj.position = sawmill.input_position() + Vector3(lumberjacks.size() * 0.8 - 1.0, 0, -1.0)
		add_child(lj)
		lumberjacks.append(lj)
