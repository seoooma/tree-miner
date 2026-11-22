extends Node
## 見た目の確認用に、決まった場面のスクリーンショットを撮る（クラウドのセッション向け）。
## 実行: tools/cloud/screenshots.sh <出力フォルダ> [幅x高さ] [撮る場面（カンマ区切り）]。orders / workshop / master / autumn / bamboo / travel_menu / travel / fuel / upgrades / upgrades_chop / overview / gate / grades / piles / dockpiles / yard などは名前を指定したときだけ撮る
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
	GameState.unlock_river_point(0)
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


## 左上の注文の一覧と、評判が足りない柵（名前を指定したときだけ撮る: orders）
func _shot_orders() -> void:
	Orders.running = false
	GameState.unlock_area(1)
	GameState.reputation = 4
	GameState.reputation_changed.emit(GameState.reputation)
	GameState.orders.clear()
	var a := Orders.make_order("pine", "plank")
	a["done"] = 7
	a["time_left"] = 205.0
	var b := Orders.make_order("sapling", "log")
	b["done"] = 3
	b["time_left"] = 25.0
	GameState.orders.append(a)
	GameState.orders.append(b)
	Orders.orders_changed.emit()
	_place(Vector3(3, 0, main._area_ranges[1].x - 8.0))
	await _wait(1.0)


## 出荷場の右隣の工房（名前を指定したときだけ撮る: workshop）
func _shot_workshop() -> void:
	GameState.buy_upgrade("workshop")
	for i in 6:
		main.dock.stock.append(["pine", "maple", "oak"][i % 3])
	for i in 4:
		main.dock.log_stock.append("sapling")
	main.workshop.goods.append_array(["chest", "table", "chair", "shelf", "charcoal"])
	main.workshop._rebuild_goods()
	main.dock._rebuild_stock()
	main.dock._rebuild_logs()
	_place(main.DOCK_POS + Workshop.FROM_DOCK + Vector3(0.5, 0, 2.2))
	await _wait(3.0)


## 強化画面の親方タブ（エリアをすべて開放して移れる状態。名前を指定したときだけ撮る: master）
func _shot_master() -> void:
	GameState.unlocked_area_count = GameData.areas.size()
	GameState.reputation = 52
	GameState.skill_points = 6
	GameState.perks["appraise"] = 2
	GameState.perks_changed.emit()
	main.hud._set_sheet(true)
	main.hud._select_tab("master")
	await _wait(0.8)


## 別の山（紅葉の山・竹の谷）の森。場面を作り直して撮る（名前を指定したときだけ撮る: autumn / bamboo）
func _shot_autumn() -> void:
	await _rebuild_on_mountain(1)


func _shot_bamboo() -> void:
	await _rebuild_on_mountain(2)


func _rebuild_on_mountain(n: int) -> void:
	GameState.mountain = n
	GameData.apply_mountain(n)
	GameState._sync_prices()
	GameState.unlock_area(1)
	main.queue_free()
	await _frames(2)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(10)
	_place(Vector3(2, 0, -2))
	await _wait(1.0)


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


## 自動移動の行き先メニュー（名前を指定したときだけ撮る: travel_menu）
func _shot_travel_menu() -> void:
	_place(main.PLAYER_SPAWN)
	main.hud._set_travel_menu(true)
	await _wait(0.5)


## 自動移動中（森から川の積み場へ。経路に沿った矢印と移動中の帯。名前を指定したときだけ撮る: travel）
func _shot_travel() -> void:
	main.hud._set_travel_menu(false)
	_place(Vector3(6, 0, -8))
	for d in main.travel_destinations():
		if d["id"] == "river_point":
			main.player.start_auto_move(d)
	await _wait(1.0)


func _shot_river() -> void:
	var line: LogLine = main.lines["river"]
	for i in 8:
		line.launch("pine", line._points[0])
	_place(Vector3(-13, 0, -6))
	await _wait(3.0)


## 開放前の川の積み場の支払い枠（名前を指定したときだけ撮る: river_pay）
func _shot_river_pay() -> void:
	var line: LogLine = main.lines["river"]
	GameState.river_points.erase("0")
	line._refresh()
	_place(line._points[0].global_position + Vector3(0.5, 0, 3.0))
	await _wait(1.5)


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


## 強化画面の乗り物タブ（販売のトラックのカード）（名前を指定したときだけ撮る: upgrades_truck）
func _shot_upgrades_truck() -> void:
	_place(main.PLAYER_SPAWN)
	main.hud._set_sheet(true)
	main.hud._select_tab(GameData.upgrade_group_of("truck_capacity"))
	await _wait(0.5)
	main.hud._scroll.scroll_vertical = 0
	await _wait(0.3)


## 強化画面の仲間タブ（伐採員のカードと役割・狙う木。名前を指定したときだけ撮る: upgrades_chop）
func _shot_upgrades_chop() -> void:
	_place(main.PLAYER_SPAWN)
	main.hud._set_sheet(true)
	main.hud._select_tab(GameData.upgrade_group_of("lumberjack"))
	await _wait(0.5)
	main.hud._scroll.scroll_vertical = 00
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


## エリア開放の柵と支払いの枠（名前を指定したときだけ撮る: gate）
func _shot_gate() -> void:
	_place(Vector3(0, 0, main._area_ranges[1].x + AreaGate.PAD_OFFSET.z + 3.0))
	await _wait(0.8)


## 木の種類ごとの丸太と板を並べる（見分けやすさの確認。名前を指定したときだけ撮る: grades）
func _shot_grades() -> void:
	var at: Vector3 = main.PLAYER_SPAWN + Vector3(0, 0, -3.0)
	var root := Node3D.new()
	main.add_child(root)
	for i in GameData.trees.size():
		var id := str(GameData.trees[i]["id"])
		var x := (i - 2) * 1.0
		var log_mesh := LogDrop.make_log_mesh(id, 90.0)
		log_mesh.position = at + Vector3(x, 0.15, 0)
		root.add_child(log_mesh)
		var log2 := LogDrop.make_log_mesh(id, 0.0)
		log2.position = at + Vector3(x, 0.15, 1.0)
		root.add_child(log2)
		var plank := Sawmill._plank_mesh(id)
		plank.position = at + Vector3(x, 0.1, 1.8)
		plank.rotation_degrees.y = 90.0
		root.add_child(plank)
	_place(main.PLAYER_SPAWN + Vector3(0, 0, 1.5))
	await _wait(0.5)


## 製材所の置き場にたくさん積み、背中にも運搬容量いっぱいに積んだところ（実際の数だけ積めているか。名前を指定したときだけ撮る: piles）
func _shot_piles() -> void:
	var ids := ["sapling", "pine", "maple", "oak", "ebony"]
	for i in 40:
		main.sawmill.accept_log(ids[i % 5])
	for i in 30:
		main.sawmill.output.append(ids[(i / 3) % 5])
	main.sawmill._rebuild_output()
	for i in 12:
		GameState.buy_upgrade("capacity")
	var stack: CarryStack = main.player.stack
	var n := 0
	while not stack.is_full():
		stack.add({"kind": "log", "tree": ids[n % 5]})
		n += 1
	_place(main.SAWMILL_POS + Vector3(0, 0, 1.5))
	await _wait(0.5)


## 出荷場の山にたくさん積んだところ（名前を指定したときだけ撮る: dockpiles）
func _shot_dockpiles() -> void:
	var ids := ["sapling", "pine", "maple", "oak", "ebony"]
	for i in 45:
		main.dock._add_stock(ids[(i / 2) % 5])
	for i in 27:
		main.dock.add_log(ids[i % 5])
	_place(main.DOCK_POS + Vector3(1.5, 0, 2.0))
	await _wait(1.5)


## 川の集積所にたくさん流れ着いたところ（名前を指定したときだけ撮る: yard）
func _shot_yard() -> void:
	var line: LogLine = main.lines["river"]
	var ids := ["sapling", "pine", "maple", "oak", "ebony"]
	for i in 33:
		line._yard.append({"tree": ids[i % 5], "z": line.near_z, "node": null, "from": null})
	line._rebuild_yard()
	_place(line.yard_pad_position() + Vector3(1.5, 0, 1.5))
	await _wait(0.5)


## 製材所から出荷場への板のコンベア（名前を指定したときだけ撮る: belt）
func _shot_belt() -> void:
	GameState.buy_upgrade("plank_belt")
	for i in 12:
		main.sawmill.output.append("pine")
	main.sawmill._rebuild_output()
	_place(Vector3(1.0, 0, 8.0))
	await _wait(2.0)
