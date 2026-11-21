extends Node
## 見た目の確認用に、決まった場面のスクリーンショットを撮る（クラウドのセッション向け）。
## 実行: tools/cloud/screenshots.sh <出力フォルダ> [幅x高さ] [撮る場面（カンマ区切り）]。fuel / upgrades / upgrades_chop / overview は名前を指定したときだけ撮る
## セーブデータは書き換えない。

const SHOTS := ["home", "chop", "felled", "saw", "sell", "river"]

var main: Node3D
var out_dir := "user://shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	GameState.save_enabled = false
	GameState.reset_game()
	seed(4)
	# 施設が一通り動いている状態にする（ゲームの数値は変えない）
	GameState.add_money(500000)
	for id in ["sawmill", "river", "conveyor", "lumberjack", "lumberjack", "dock"]:
		GameState.buy_upgrade(id)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(10)
	var names: Array = SHOTS
	if args.size() > 1 and args[1] != "":
		names = Array(args[1].split(","))
	for name in names:
		await call("_shot_" + name)
		await _save(name)
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _place(pos: Vector3) -> void:
	main.player.global_position = pos
	main.player.velocity = Vector3.ZERO
	main.camera.snap()


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("shot: ", name)


func _nearest_tree(pos: Vector3) -> ChoppableTree:
	var best: ChoppableTree = null
	for t in get_tree().get_nodes_in_group("trees"):
		var tree := t as ChoppableTree
		if tree.alive and (best == null or tree.global_position.distance_to(pos) < best.global_position.distance_to(pos)):
			best = tree
	return best


func _shot_home() -> void:
	_place(main.PLAYER_SPAWN)
	await _wait(1.0)


func _shot_chop() -> void:
	var tree := _nearest_tree(Vector3(3, 0, -4))
	_place(tree.global_position + Vector3(0.9, 0, 0.6))
	await _wait(0.6)
	for i in 6:
		if not tree.alive:
			break
		tree.hit(tree.max_hp * 0.3, main.player.global_position)
		await _wait(0.12)
	# 倒れきる直前
	await _wait(ChoppableTree.CREAK_SEC + ChoppableTree.FALL_SEC - 0.2)


func _shot_felled() -> void:
	# chop の続き: 着地して葉と土ぼこりが舞っているところ
	await _wait(0.35)


func _shot_saw() -> void:
	for i in 6:
		main.sawmill.accept_log("pine")
	_place(main.sawmill.input_position() + Vector3(1.5, 0, 2.0))
	await _wait(2.5)


func _shot_sell() -> void:
	for i in 10:
		main.dock._add_stock("pine")
	for i in 6:
		main.dock.add_log("oak")
	# 販売のトラックにある程度積まれたところ
	for i in 7:
		main.dock.truck.add_cargo("plank" if i % 3 else "log", "pine" if i % 3 else "oak")
	_place(main.DOCK_POS + Vector3(1.5, 0, 3.0))
	await _wait(1.2)


## 販売のトラックが満載で走り去るところ（名前を指定したときだけ撮る: truck）
func _shot_truck() -> void:
	for i in ShipDock.truck_capacity() - 1:
		main.dock.truck.add_cargo("plank", "maple")
	main.dock._add_stock("maple")
	_place(main.DOCK_POS + Vector3(5.0, 0, 3.0))
	await _wait(1.75)


func _shot_river() -> void:
	var line: LogLine = main.lines["river"]
	for i in 8:
		line.launch("pine", line._points[0])
	_place(Vector3(-13, 0, -6))
	await _wait(3.0)


## 給油所（名前を指定したときだけ撮る: fuel）
func _shot_fuel() -> void:
	_place(main.FUEL_POS + Vector3(0, 0, 2.5))
	await _wait(1.0)


## 強化画面の機械のカード（車両タブ。名前を指定したときだけ撮る: upgrades）
func _shot_upgrades() -> void:
	_place(main.PLAYER_SPAWN)
	main.hud._set_sheet(true)
	main.hud._select_tab(GameData.upgrade_group_of("harvester"))
	await _wait(0.5)


## 強化画面の最初のタブ（伐採。伐採員の役割チップまで見えるよう下へ送る。名前を指定したときだけ撮る: upgrades_chop）
func _shot_upgrades_chop() -> void:
	_place(main.PLAYER_SPAWN)
	main.hud._set_sheet(true)
	main.hud._select_tab(GameData.upgrade_group_of("axe_power"))
	await _wait(0.5)
	main.hud._scroll.scroll_vertical = 100000
	await _wait(0.3)


## 拠点全体を高い所から見下ろす（配置の確認用。名前を指定したときだけ撮る: overview。カメラを外すので最後に撮る）
func _shot_overview() -> void:
	_place(main.PLAYER_SPAWN)
	await _wait(0.5)
	var cam: FollowCamera = main.camera
	cam.target = null
	cam.global_position = Vector3(0, 30, 24)
	cam.look_at(Vector3(0, 0, 4), Vector3.UP)
	await _wait(0.3)


## 販売のトラックの道を真上から（名前を指定したときだけ撮る: road。カメラを外すので最後に撮る）
func _shot_road() -> void:
	_place(main.DOCK_POS)
	await _wait(0.5)
	var cam: FollowCamera = main.camera
	cam.target = null
	cam.global_position = Vector3(13, 22, 12)
	cam.look_at(Vector3(13, 0, 5), Vector3.UP)
	await _wait(0.3)
