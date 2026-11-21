extends Node
## ヘッドレスで一通りのループが動くか確認するスモークテスト。
## 伐採→丸太を拾う→売却→強化→伐採員の役割→製材→出荷→給油→伐採機・運搬車の購入と運転→エリア開放
## 実行: godot --headless --fixed-fps 60 --path . res://tests/smoke_test.tscn
## 成功で終了コード0、失敗で1。

var main: Node3D
var player: Player
var _failed := false


func _ready() -> void:
	GameState.save_enabled = false  # プレイ中のセーブデータを上書きしない
	GameState.reset_game()
	seed(12345)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().physics_frame
	player = main.player
	await _run()
	print("SMOKE TEST: ", "FAIL" if _failed else "PASS")
	get_tree().quit(1 if _failed else 0)


func _check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + msg)
	if not cond:
		_failed = true


func _run() -> void:
	# 1. 伐採すると丸太が落ち、近くを歩くと拾える
	var tree := _nearest_tree(player.global_position)
	await _chop_down(tree)
	await _wait(0.6)
	_check(player.stack.count("log") + get_tree().get_nodes_in_group("drops").size() >= 2, "木を倒すと丸太が2本以上落ちる")
	await _gather_until_full()
	_check(player.stack.is_full(), "落ちた丸太を拾って運搬容量いっぱいにできる (%d)" % player.stack.size())

	# 満杯でも伐採できる
	tree = _nearest_tree(player.global_position)
	var hp_before := tree.hp
	# 木の横に立った瞬間には切れず、斧を振り下ろしたところで1回分だけ減る
	var side := (player.global_position - tree.global_position)
	side.y = 0.0
	player.global_position = tree.global_position + side.normalized() * (tree.radius + 0.9)
	await _wait(0.15)
	_check(tree.hp == hp_before, "木に触れた瞬間には切れない")
	await _wait(0.5)
	_check(tree.hp < hp_before or not tree.alive, "積荷が満杯でも木を切れる（斧を振り下ろした瞬間に当たる）")
	_check(not tree.alive or tree.hp >= hp_before - GameState.value("axe_power") * 1.01, "1振りで当たるのは1回だけ")

	# 2. 製材所（ライン未開放）で丸太を売る
	await _walk_to(main.sawmill.input_position(), 0.5)
	await _wait(2.0)
	_check(player.stack.count("log") == 0, "製材所で丸太を全部渡せる")
	_check(GameState.money > 0, "丸太の売却でお金が増える (¥%d)" % GameState.money)

	# 3. 強化と伐採員
	GameState.add_money(200000)
	var cap_before := player.capacity()
	_check(GameState.buy_upgrade("capacity"), "運搬容量を強化できる")
	_check(player.capacity() > cap_before, "強化で容量が増える (%d → %d)" % [cap_before, player.capacity()])
	_check(GameState.buy_upgrade("sawmill"), "製材ラインを開放できる")
	GameState.buy_upgrade("lumberjack")
	GameState.buy_upgrade("lumberjack")
	await get_tree().process_frame
	_check(main.lumberjacks.size() == 2, "伐採員を2人雇える")
	_check(main.lumberjacks[0].role == "chop" and main.lumberjacks[1].role == "haul", "初期の役割は 伐採・運搬")
	GameState.set_lumberjack_role(0, "haul")
	_check(main.lumberjacks[0].role == "haul", "伐採員の役割を運搬に切り替えられる")
	GameState.set_lumberjack_role(0, "chop")
	GameState.set_lumberjack_target("pine")
	await get_tree().process_frame
	await get_tree().process_frame
	var aimed: ChoppableTree = main.lumberjacks[0]._target_tree
	_check(aimed != null and GameData.tree_grade(aimed.tree_id) >= GameData.tree_grade("pine"), "伐採員が狙う木のグレードを選べる (%s)" % (aimed.tree_id if aimed else "なし"))
	_check(GameState.meets_lumberjack_target("maple") and not GameState.meets_lumberjack_target("sapling"), "選んだグレード以上の木だけを優先する")
	GameState.set_lumberjack_target("")

	# 4. 製材 → 出荷
	await _gather_until_full()
	await _walk_to(main.sawmill.input_position(), 0.5)
	await _wait(2.0)
	await _wait(20.0)
	_check(main.sawmill.output.size() > 0, "丸太が板に加工される (%d枚)" % main.sawmill.output.size())
	await _walk_to(main.sawmill.output_position(), 0.5)
	await _wait(2.0)
	_check(player.stack.count("plank") > 0, "出口で板を受け取れる (%d枚)" % player.stack.count("plank"))
	var money_before := GameState.money
	var planks_held := player.stack.count("plank")
	await _walk_to(main.DOCK_POS, 0.5)
	await _wait(1.0)
	_check(player.stack.count("plank") == 0 and main.dock.stock.size() > 0, "出荷場に板を置ける (%d枚)" % main.dock.stock.size())
	_check(main.dock.stock.size() < planks_held or GameState.money == money_before, "板はその場では全部売れず、荷台に残る")
	await _wait(planks_held / GameState.value("dock") + float(GameData.dock.get("depart_idle_sec", 2.5)) + 1.0)
	_check(GameState.money > money_before and main.dock.stock.is_empty(), "荷台の板がトラックに積まれ、走り去ると売上が入る (+¥%d)" % (GameState.money - money_before))
	_check(not main.dock.truck.is_parked() or main.dock.truck.cargo.is_empty(), "積み込んだトラックは拠点の外へ走り去る")
	_check(main.sawmill.queue.size() + main.sawmill.output.size() > 0 or main.lumberjacks[1].stack.size() > 0, "運搬役の伐採員が丸太を運んでいる")

	# 5. 給油所で燃料缶を受け取る
	await _walk_to(main.FUEL_POS, 0.4)
	await _wait(1.0)
	_check(player.stack.count("fuel") > 0, "給油所で燃料缶を受け取れる (%d個)" % player.stack.count("fuel"))

	# 6. 伐採機を買う（ほかの強化と同じく、強化画面のカードのボタンで買う）
	_check(not main.has_node("MachineShop") and get_tree().get_nodes_in_group("machines").is_empty(), "最初は機械が無い")
	_check(main.hud._rows.has("harvester") and main.hud._rows.has("hauler"), "強化画面に伐採機・運搬車のカードがある")
	# 強化画面はタブで分ける。すべての強化・機械が upgrade_groups のどれかのタブに入っている
	var ungrouped: Array = []
	for id in main.hud._rows:
		if GameData.upgrade_group_of(id) == "":
			ungrouped.append(id)
	_check(ungrouped.is_empty() and main.hud._rows.size() == GameData.upgrades.size() + GameData.machines.keys().filter(func(k: String) -> bool: return not k.begins_with("_")).size(), "強化画面のカードがすべてどれかのタブに入っている%s" % ("" if ungrouped.is_empty() else " (タブ無し: %s)" % ", ".join(ungrouped)))
	main.hud._select_tab(GameData.upgrade_group_of("harvester"))
	_check(main.hud._pages[GameData.upgrade_group_of("harvester")].visible, "タブを切り替えると、そのタブのカードが出る")
	_check(not main.hud._pages[GameData.upgrade_group_of("axe_power")].visible, "ほかのタブのカードは隠れる")
	main.hud._select_tab(str(GameData.upgrade_groups[0]["id"]))
	GameState.money = maxi(GameState.money, GameState.machine_next_cost("harvester"))
	var money_before_machine := GameState.money
	_press_card("harvester")
	await _wait(0.5)
	_check(main.machines.has("harvester") and GameState.money == money_before_machine - int(GameData.machine_rank("harvester", 1)["cost"]), "強化画面で伐採機を買うと出現する")
	_check(_card_text("harvester", 0) == "Lv.1" and _card_text("harvester", 2) == "Lv.2", "伐採機のカードはほかの強化と同じく Lv で表示される")
	if not main.machines.has("harvester"):
		return
	var harvester: Machine = main.machines["harvester"]
	_check(is_equal_approx(harvester.fuel, harvester.fuel_max()), "最初の燃料は満タン")

	# 7. 乗る → 乗っているだけでは燃料が減らない → 運転すると減る
	await _walk_to(harvester.global_position, 2.0)
	player.board(player.nearby_machine())
	_check(player.vehicle == harvester, "伐採機に乗れる")
	var fuel0 := harvester.fuel
	await _wait(1.5)
	_check(is_equal_approx(harvester.fuel, fuel0), "乗っているだけでは燃料が減らない")
	var target := _nearest_tree(harvester.global_position)
	var alive_before := _alive_tree_count()
	await _drive_to(target.global_position, 1.8)
	await _wait(3.0)
	_check(harvester.fuel < fuel0, "運転・伐採で燃料が減る (%.1f → %.1f)" % [fuel0, harvester.fuel])
	# 走っている間に別の木が生え直すことがあるので、狙った木が倒れたかでも判定する
	_check(not target.alive or _alive_tree_count() < alive_before, "伐採機で木を切り倒せる")

	# 8. 燃料切れ → 降りて燃料缶で補給
	harvester.fuel = 0.0
	var pos_before := harvester.global_position
	player.joystick_vector = Vector2(0, 1)
	await _wait(0.5)
	player.joystick_vector = Vector2.ZERO
	_check(Fx.xz_distance(pos_before, harvester.global_position) < 0.01, "燃料切れだと動かない")
	player.exit_vehicle()
	_check(player.vehicle == null, "機械から降りられる")
	_check(player.stack.count("fuel") == 0, "機械に乗ると持っていた燃料缶はなくなる")
	if player.stack.count("fuel") == 0:
		# 途中で拾った板や丸太で手がふさがっていたら、給油所に着いてから空ける
		# （森を通る道のりで落ちた丸太を拾って満杯になると缶を受け取れないため）
		await _go_to_fuel_station()
		_empty_hands()
		await _wait(1.0)
		await _walk_to(harvester.global_position, 2.0)
	await _wait(1.0)
	_check(harvester.fuel > 0.0, "燃料缶を持って近づくと補給される (燃料 %.0f)" % harvester.fuel)

	# 9. 運搬車を買って、落ちている丸太を集めて製材所へ
	GameState.money = maxi(GameState.money, GameState.machine_next_cost("hauler"))
	_press_card("hauler")
	await _wait(0.5)
	_check(main.machines.has("hauler"), "運搬車を買える")
	if not main.machines.has("hauler"):
		return
	var hauler: Machine = main.machines["hauler"]
	# 拾いやすいように運搬車の近くへ丸太をばらまく
	for i in 3:
		var t := _nearest_tree(hauler.global_position)
		await _walk_to(t.global_position, 0.6 + t.radius + 0.4)
		t.hit(9999.0)
	await _walk_to(hauler.global_position, 2.0)
	player.board(player.nearby_machine())
	_check(player.vehicle == hauler, "運搬車に乗れる")
	for i in 4:
		var drop := _nearest_drop(hauler.global_position)
		if drop == null:
			break
		await _drive_to(drop.global_position, 1.0)
	_check(hauler.stack.count("log") > 0, "運搬車で落ちた丸太を拾える (%d本)" % hauler.stack.count("log"))
	main.sawmill.queue.clear()
	main.sawmill.output.clear()
	var queue_before: int = main.sawmill.queue.size()
	# 木に引っかからないよう、中央の道に置き直してから製材所へ（経路探索はテストの対象外）
	hauler.fuel = hauler.fuel_max()
	hauler.global_position = Vector3(0, 0, hauler.global_position.z)
	await _drive_to(Vector3(0, 0, main.sawmill.input_position().z), 0.8)
	await _drive_to(main.sawmill.input_position(), 0.8)
	await _wait(3.0)
	_check(hauler.stack.count("log") == 0 and main.sawmill.queue.size() > queue_before, "運搬車から製材所に丸太を降ろせる")
	player.exit_vehicle()

	# 10. ランクアップ（強化画面のボタン1回で1ランク）
	GameState.money = GameState.machine_next_cost("hauler") * 3
	_press_card("hauler")
	await _wait(0.5)
	_check(hauler.rank == 2 and GameState.machine_rank("hauler") == 2, "強化画面で運搬車をランクアップできる（1回で1ランクだけ）")
	_check(hauler.stack.capacity() == int(GameData.machine_rank("hauler", 2)["capacity"]) and _card_text("hauler", 3) == "%d本" % int(GameData.machine_rank("hauler", 2)["capacity"]), "ランクアップで積載量が上がり、カードに表示される")
	GameState.money = 0
	_press_card("hauler")
	await _wait(0.2)
	_check(hauler.rank == 2, "お金が足りないとランクアップできない")
	GameState.money = GameState.gate_remaining(1)

	# 11. エリア開放
	var gate_pad := Vector3(0, 0, main._area_ranges[1].x + AreaGate.PAD_OFFSET.z)
	await _walk_to(gate_pad, 0.4)
	await _wait(4.0)
	_check(GameState.is_area_unlocked(1), "柵の前で支払うとエリア1が開放される")

	# 12. 燃料缶を捨てる
	_empty_hands()
	await _go_to_fuel_station()
	await _wait(1.0)
	var cans := player.stack.count("fuel")
	var dropped := player.discard_fuel()
	_check(cans > 0 and dropped == cans and player.stack.count("fuel") == 0, "燃料缶を捨てられる (%d個)" % dropped)

	# 13. 乗ったまま給油所に入ると補給される
	await _walk_to(hauler.global_position, 2.0)
	player.board(hauler)
	hauler.fuel = 5.0
	await _drive_to(Vector3(0, 0, hauler.global_position.z), 0.8)
	await _drive_to(main.FUEL_POS, 0.6)
	var fuel_at_station := hauler.fuel
	await _wait(2.0)
	_check(hauler.fuel > fuel_at_station + 10.0, "乗ったまま給油所で補給される (%.0f → %.0f)" % [fuel_at_station, hauler.fuel])
	player.exit_vehicle()

	# 14. 伐採員の積載量の強化
	GameState.money += 1000000
	var cap0: int = main.lumberjacks[0].stack.capacity()
	GameState.buy_upgrade("lumberjack_capacity")
	_check(main.lumberjacks[0].stack.capacity() > cap0, "伐採員の積載量を強化できる (%d → %d)" % [cap0, main.lumberjacks[0].stack.capacity()])

	# 15. 川流しを開放して、積み込み枠から製材所へ丸太を流す
	var river: LogLine = main.lines["river"]
	_check(not river.visible, "川流しは最初は使えない")
	GameState.buy_upgrade("river")
	await get_tree().process_frame
	_check(river.visible and get_tree().get_nodes_in_group("log_dropoffs").size() > 0, "強化で川流しが開放される")
	var point: LoadingPoint = null
	for node in get_tree().get_nodes_in_group("log_dropoffs"):
		var lp := node as LoadingPoint
		if lp.line == river and lp.area_index == 1:
			point = lp
	_check(point != null, "開放済みエリアに積み込み枠がある")
	if point == null:
		return
	# 運搬役の伐採員が川へ丸太を積むと数が変わるので止めておく
	for lj in main.lumberjacks:
		lj.process_mode = Node.PROCESS_MODE_DISABLED
	_empty_hands()
	for i in 3:
		player.stack.add({"kind": "log", "tree": "pine"})
	player.global_position = point.global_position
	await _wait(2.0)
	_check(player.stack.count("log") == 0 and river.in_transit_from(point) > 0, "積み込み枠に丸太を置くと川を流れる (%d本)" % river.in_transit_from(point))
	player.global_position = main.PLAYER_SPAWN
	var frames := 0
	while river.yard_count() < 3 and frames < 60 * 60:
		await get_tree().physics_frame
		frames += 1
	await _wait(2.0)
	_check(river.yard_count() == 3 and river._yard_pile.shown_count() == 3, "流れ着いた丸太は集積所に積まれる (%d本)" % river.yard_count())
	_check(not river.belt.visible, "集積所コンベアは最初は無く、丸太は集積所に溜まったまま")

	# 16. 集積所の丸太は手で拾って製材所に運ぶ
	main.sawmill.queue.clear()
	main.sawmill.output.clear()
	main.sawmill._rebuild_input()
	await _walk_to(river.yard_pad_position(), 0.4)
	await _wait(1.5)
	_check(player.stack.count("log") == 3 and river.yard_count() == 0, "集積所の枠に立つと丸太を拾える (%d本)" % player.stack.count("log"))
	await _walk_to(main.sawmill.input_position(), 0.5)
	await _wait(1.5)
	_check(player.stack.count("log") == 0 and main.sawmill.queue.size() == 3, "拾った丸太を製材所に運べる")

	# 17. 集積所コンベアを開放すると、集積所から製材所へ自動で運ばれる
	GameState.buy_upgrade("conveyor")
	await get_tree().process_frame
	_check(river.belt.visible, "強化で集積所コンベアが開放される")
	for i in 4:
		river._yard.append({"tree": "pine", "z": 0.0, "node": null, "from": null})
	river._rebuild_yard()
	var d0: int = river.belt.delivered
	frames = 0
	while river.belt.delivered < d0 + 4 and frames < 60 * 30:
		await get_tree().physics_frame
		frames += 1
	_check(river.belt.delivered == d0 + 4 and river.yard_count() == 0, "集積所コンベアで製材所に届く (%.1f秒)" % (frames / 60.0))
	_check(frames / 60.0 >= 3.0 / GameState.value("conveyor"), "コンベアは1秒あたりの本数に限りがある (%.2f本/秒)" % GameState.value("conveyor"))

	# 18. 置き場に上限は無い: たくさん溜まっていても、投入口でもコンベアでも受け取り、加工も続く
	const MANY := 80
	main.sawmill.queue.clear()
	for i in MANY:
		main.sawmill.queue.append("pine")
	main.sawmill._rebuild_input()
	main.sawmill.output.resize(MANY)
	main.sawmill.output.fill("pine")
	main.sawmill._rebuild_output()
	for i in 2:
		river._yard.append({"tree": "pine", "z": 0.0, "node": null, "from": null})
	_empty_hands()
	player.stack.add({"kind": "log", "tree": "pine"})
	frames = 0
	while (river.yard_count() > 0 or river.belt.in_flight() > 0) and frames < 60 * 20:
		await get_tree().physics_frame
		frames += 1
	_check(river.yard_count() == 0 and river.belt.in_flight() == 0, "丸太置き場に%d本あってもコンベアは止まらない" % MANY)
	await _walk_to(main.sawmill.input_position(), 0.5)
	await _wait(1.0)
	_check(player.stack.count("log") == 0, "丸太置き場がたくさんでも投入口で渡せる")
	_check(main.sawmill.output.size() > MANY, "出口に板がたくさんあっても加工は続く (%d枚)" % main.sawmill.output.size())
	_check(main.sawmill._input_pile.shown_count() == maxi(0, main.sawmill.queue.size() - 1) and main.sawmill._output_pile.shown_count() == main.sawmill.output.size(), "山には実際の数だけ積む（丸太置き場 %d本・板 %d枚）" % [main.sawmill._input_pile.shown_count(), main.sawmill._output_pile.shown_count()])
	_check(not main.sawmill._input_zone._title.text.contains("満杯"), "「満杯」の表示は出ない")
	_empty_hands()

	# 19. 加工と見た目: 丸太置き場の丸太の数は加工待ちと同じで、加工されると消える
	main.sawmill.output.clear()
	main.sawmill.queue.resize(3)
	main.sawmill._rebuild_input()
	main.sawmill._rebuild_output()
	river._yard.clear()
	river._rebuild_yard()
	await get_tree().process_frame
	_check(main.sawmill._input_pile.shown_count() == 2 and (main.sawmill._work_log.visible or main.sawmill._work_plank.visible), "丸太置き場の丸太と製材台の1本を合わせた数が加工待ちと一致する (山 %d本)" % main.sawmill._input_pile.shown_count())
	frames = 0
	while not main.sawmill.queue.is_empty() and frames < 60 * 90:
		await get_tree().physics_frame
		frames += 1
	await get_tree().process_frame
	_check(main.sawmill.queue.is_empty() and main.sawmill._input_pile.shown_count() == 0 and main.sawmill.output.size() == 3, "板に加工された丸太は丸太置き場から消え、出口に板が積まれる (%d枚)" % main.sawmill.output.size())
	_check(frames / 60.0 >= 2.0 / GameState.value("sawmill"), "加工には時間がかかる (%.1f秒で3本)" % (frames / 60.0))

	# 20. 板のコンベアを開放すると、製材所の板が出荷場へ運ばれて売れていく
	_check(not main.dock.belt.visible, "板のコンベアは最初は無い")
	GameState.buy_upgrade("plank_belt")
	await get_tree().process_frame
	_check(main.dock.belt.visible, "強化で板のコンベアが開放される")
	var m0 := GameState.money
	frames = 0
	while (not main.sawmill.output.is_empty() or main.dock.belt.in_flight() > 0 or not main.dock.stock.is_empty()) and frames < 60 * 40:
		await get_tree().physics_frame
		frames += 1
	await _wait(float(GameData.dock.get("depart_idle_sec", 2.5)) + 0.5)
	_check(main.sawmill.output.is_empty() and main.dock.stock.is_empty() and GameState.money > m0, "板のコンベアで出荷場に届き、売れる (+¥%d, %.1f秒)" % [GameState.money - m0, frames / 60.0])
	await get_tree().process_frame
	_check(main.dock._stock_pile.shown_count() == 0, "売れた板は出荷場に残らない")

	# 21. 出荷場の荷台にも上限は無い
	while main.dock.stock.size() < MANY:
		main.dock.stock.append("pine")
	player.stack.add({"kind": "plank", "tree": "pine"})
	player.global_position = main.DOCK_POS
	await _wait(0.3)
	_check(player.stack.count("plank") == 0, "出荷場に%d枚あっても板を置ける" % MANY)
	_empty_hands()

	# 21b. 販売のトラックと、丸太をそのまま売る枠
	main.dock.stock.clear()
	main.dock._rebuild_stock()
	frames = 0
	while not (main.dock.truck.is_parked() and main.dock.truck.cargo.is_empty()) and frames < 60 * 20:
		await get_tree().physics_frame
		frames += 1
	_check(main.dock.truck.is_parked() and main.dock.truck.cargo.is_empty(), "トラックは走り去ったあと空で戻ってくる (%.1f秒)" % (frames / 60.0))
	_check(not main.dock.truck.is_in_group("vehicles") and not main.dock.truck.is_in_group("machines"), "販売のトラックには乗れない（機械とは別）")
	_check(GameData.log_price("oak") < GameData.plank_price("oak"), "丸太の売値は板より安い")
	_check(main.dock._log_zone.visible, "製材ライン開放後は「丸太を売る」枠がある")
	var m_logs := GameState.money
	for i in 3:
		player.stack.add({"kind": "log", "tree": "oak"})
	player.global_position = main.DOCK_POS + ShipDock.LOG_PAD_OFFSET
	await _wait(0.6)
	_check(player.stack.count("log") == 0, "「丸太を売る」枠に丸太を置ける")
	_check(GameState.money == m_logs, "丸太はその場では売れず、トラックを待つ")
	player.global_position = main.PLAYER_SPAWN
	await _wait(3.0 / GameState.value("dock") + float(GameData.dock.get("depart_idle_sec", 2.5)) + 0.5)
	_check(GameState.money - m_logs == GameData.log_price("oak") * 3, "丸太はトラックで丸太の売値で売れる (+¥%d)" % (GameState.money - m_logs))
	# 満載になると、積む物が残っていても出発する
	var cap := ShipDock.truck_capacity()
	frames = 0
	while not main.dock.truck.is_parked() and frames < 60 * 20:
		await get_tree().physics_frame
		frames += 1
	for i in cap + 4:
		main.dock.stock.append("pine")
	frames = 0
	var max_cargo := 0
	while main.dock.truck.is_parked() and frames < 60 * 60:
		await get_tree().process_frame
		max_cargo = maxi(max_cargo, main.dock.truck.cargo.size())
		frames += 1
	_check(max_cargo == cap and main.dock.stock.size() == 4, "トラックは%d個で満載になり、残りは次のトラックを待つ (%d個積んで、残り%d個)" % [cap, max_cargo, main.dock.stock.size()])
	main.dock.stock.clear()
	# 販売のトラックは乗り物タブで強化できる（荷台・速さ・取引先）
	for tid in ["truck_capacity", "truck_speed", "truck_price"]:
		_check(GameData.upgrade_group_of(tid) == "vehicle", "%s は乗り物タブにある" % tid)
	var truck_cap0 := ShipDock.truck_capacity()
	var truck_speed0: float = main.dock.truck.max_speed()
	var truck_price0 := ShipDock.cargo_price({"kind": "plank", "tree": "oak"})
	for tid in ["truck_capacity", "truck_speed", "truck_price"]:
		GameState.money = maxi(GameState.money, GameState.next_cost(tid))
		GameState.buy_upgrade(tid)
	_check(ShipDock.truck_capacity() > truck_cap0, "トラックの荷台を強化すると積める数が増える (%d → %d)" % [truck_cap0, ShipDock.truck_capacity()])
	_check(main.dock.truck.max_speed() > truck_speed0, "トラックの速さを強化すると速く走る (%.1f → %.1f)" % [truck_speed0, main.dock.truck.max_speed()])
	_check(ShipDock.cargo_price({"kind": "plank", "tree": "oak"}) >= truck_price0, "トラックの取引先を強化すると売値が下がらない (¥%d → ¥%d)" % [truck_price0, ShipDock.cargo_price({"kind": "plank", "tree": "oak"})])
	_check(is_equal_approx(GameState.value("truck_price"), 105.0), "取引先 Lv1 で売値 105%")
	main.dock.stock.append("pine")

	# 22. 在庫はセーブに入る
	GameState.saving.emit()
	_check((GameState.stock.get("dock", []) as Array).size() > 0 and GameState.stock.has("yard") and GameState.stock.has("sawmill_queue"), "集積所・製材所・出荷場の在庫がセーブに入る")
	_check(not main.lines.has("trolley"), "トロッコは無くなっている")

	# 23. 先に開放が必要な強化
	GameState.reset_state()
	GameState.add_money(100000)
	_check(not GameState.buy_upgrade("conveyor") and not GameState.buy_upgrade("plank_belt"), "川流し・製材ラインの前にはコンベアを買えない")




# ---- ヘルパー ----

## 製材所の出口（板を拾ってしまう）を避けて、右側から給油所へ向かう
func _go_to_fuel_station() -> void:
	await _walk_to(Vector3(3.5, 0, player.global_position.z), 0.5)
	await _walk_to(Vector3(3.5, 0, main.FUEL_POS.z), 0.5)
	await _walk_to(main.FUEL_POS, 0.4)


func _empty_hands() -> void:
	while not player.stack.is_empty():
		player.stack.take(player.stack.items[-1]["kind"])


func _chop_down(tree: ChoppableTree) -> void:
	var frames := 0
	while tree.alive and frames < 900:
		_steer(tree.global_position, 0.6 + tree.radius + 0.4)
		await get_tree().physics_frame
		frames += 1
	player.joystick_vector = Vector2.ZERO


## 強化画面のカードのボタンを押す
func _press_card(id: String) -> void:
	main.hud._refresh()
	(main.hud._rows[id]["button"] as Button).pressed.emit()


## カードの値の表示（0 = 今の Lv, 2 = 次の Lv, 3 = 今の値, 5 = 次の値）
func _card_text(id: String, cell: int) -> String:
	main.hud._refresh()
	return (main.hud._rows[id]["cells"][cell] as Label).text


func _gather_until_full() -> void:
	var frames := 0
	while not player.stack.is_full() and frames < 4000:
		var drop := _nearest_drop(player.global_position)
		if drop:
			_steer(drop.global_position, 0.2)
		else:
			var tree := _nearest_tree(player.global_position)
			if tree == null:
				break
			_steer(tree.global_position, 0.6 + tree.radius + 0.4)
		await get_tree().physics_frame
		frames += 1
	player.joystick_vector = Vector2.ZERO


func _steer(target: Vector3, arrive: float) -> void:
	var from := player.vehicle.global_position if player.vehicle else player.global_position
	var to := target - from
	player.joystick_vector = Vector2(to.x, to.z).normalized() if Vector2(to.x, to.z).length() > arrive else Vector2.ZERO


func _nearest_tree(from: Vector3) -> ChoppableTree:
	var best: ChoppableTree = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group("trees"):
		var t := node as ChoppableTree
		if t.alive and GameState.is_area_unlocked(t.area_index):
			var d := Fx.xz_distance(t.global_position, from)
			if d < best_d:
				best_d = d
				best = t
	return best


func _nearest_drop(from: Vector3) -> LogDrop:
	var best: LogDrop = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group("drops"):
		var d := Fx.xz_distance((node as Node3D).global_position, from)
		if d < best_d:
			best_d = d
			best = node
	return best


func _alive_tree_count() -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group("trees"):
		if (node as ChoppableTree).alive:
			n += 1
	return n


func _walk_to(target: Vector3, arrive: float) -> void:
	var frames := 0
	while Fx.xz_distance(player.global_position, target) > arrive and frames < 1200:
		_steer(target, 0.0)
		await get_tree().physics_frame
		frames += 1
	player.joystick_vector = Vector2.ZERO
	if frames >= 1200:
		print("  (walk timeout to ", target, " at ", player.global_position, ")")


func _drive_to(target: Vector3, arrive: float) -> void:
	var frames := 0
	while Fx.xz_distance(player.vehicle.global_position, target) > arrive and frames < 900:
		_steer(target, 0.0)
		await get_tree().physics_frame
		frames += 1
	player.joystick_vector = Vector2.ZERO
	if frames >= 900:
		print("  (drive timeout to ", target, " at ", player.vehicle.global_position, ")")


func _wait(sec: float) -> void:
	for i in int(sec * 60):
		await get_tree().physics_frame
