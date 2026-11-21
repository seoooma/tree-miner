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
	await _walk_to(tree.global_position, 0.6 + tree.radius + 0.4)
	await _wait(1.0)
	_check(tree.hp < hp_before or not tree.alive, "積荷が満杯でも木を切れる")

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
	await _walk_to(main.DOCK_POS, 0.5)
	await _wait(2.0)
	_check(GameState.money > money_before, "出荷場で板が売れる (+¥%d)" % (GameState.money - money_before))
	_check(main.sawmill.queue.size() + main.sawmill.output.size() > 0 or main.lumberjacks[1].stack.size() > 0, "運搬役の伐採員が丸太を運んでいる")

	# 5. 給油所で燃料缶を受け取る
	await _walk_to(main.FUEL_POS, 0.4)
	await _wait(1.0)
	_check(player.stack.count("fuel") > 0, "給油所で燃料缶を受け取れる (%d個)" % player.stack.count("fuel"))

	# 6. 伐採機を買う
	await _walk_to(main.SHOP_POS["harvester"], 0.4)
	await _wait(3.0)
	_check(main.machines.has("harvester"), "購入パッドで伐採機を買うと出現する")
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
	await _walk_to(main.SHOP_POS["hauler"], 0.4)
	await _wait(3.0)
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
	var queue_before: int = main.sawmill.queue.size()
	# 木に引っかからないよう、中央の道に置き直してから製材所へ（経路探索はテストの対象外）
	hauler.fuel = hauler.fuel_max()
	hauler.global_position = Vector3(0, 0, hauler.global_position.z)
	await _drive_to(Vector3(0, 0, main.sawmill.input_position().z), 0.8)
	await _drive_to(main.sawmill.input_position(), 0.8)
	await _wait(3.0)
	_check(hauler.stack.count("log") == 0 and main.sawmill.queue.size() > queue_before, "運搬車から製材所に丸太を降ろせる")
	player.exit_vehicle()

	# 10. ランクアップ
	await _walk_to(main.SHOP_POS["hauler"], 0.4)
	await _wait(4.0)
	_check(hauler.rank == 2, "購入パッドで運搬車をランクアップできる（1回で1ランクだけ）")

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
	_empty_hands()
	for i in 3:
		player.stack.add({"kind": "log", "tree": "pine"})
	player.global_position = point.global_position
	await _wait(2.0)
	_check(player.stack.count("log") == 0 and river.in_transit_from(point) > 0, "積み込み枠に丸太を置くと川を流れる (%d本)" % river.in_transit_from(point))
	player.global_position = main.PLAYER_SPAWN
	var d0 := river.delivered
	var frames := 0
	var yard_max := 0
	while river.in_transit_from(point) > 0 and frames < 60 * 60:
		await get_tree().physics_frame
		frames += 1
		yard_max = maxi(yard_max, river.yard_count())
	_check(yard_max > 0, "流れ着いた丸太はいったん集積所に積まれる (最大%d本)" % yard_max)
	_check(river.delivered >= d0 + 3 and river.in_transit_from(point) == 0 and river.yard_count() == 0, "集積所からコンベアで製材所に届く (%.0f秒)" % (frames / 60.0))

	# 16. 丸太置き場の見た目の数は加工待ちの数と同じ（加工されたら消える）
	await get_tree().process_frame
	var pile_n: int = main.sawmill._input_pile.get_child_count()
	_check(pile_n == mini(main.sawmill.queue.size(), Sawmill.PILE_VISIBLE), "丸太置き場の丸太の数が加工待ちと一致する (%d / %d)" % [pile_n, main.sawmill.queue.size()])
	# 伐採員を止めて新しい丸太が来ないようにし、出口を空けて加工を進める
	for lj in main.lumberjacks:
		lj.process_mode = Node.PROCESS_MODE_DISABLED
	main.sawmill.output.clear()
	main.sawmill.queue.resize(mini(main.sawmill.queue.size(), 3))
	main.sawmill._rebuild_input()
	var q_before: int = main.sawmill.queue.size()
	var wait_frames := 0
	while not main.sawmill.queue.is_empty() and wait_frames < 60 * 90:
		await get_tree().physics_frame
		wait_frames += 1
	await get_tree().process_frame
	pile_n = main.sawmill._input_pile.get_child_count()
	_check(q_before > 0 and main.sawmill.queue.is_empty() and pile_n == 0, "板に加工された丸太は丸太置き場から消える (%d → %d本)" % [q_before, pile_n])
	_check(main.dock._stock_pile.get_child_count() == 0, "売れた板は出荷場に残らない")
	_check(not main.lines.has("trolley"), "トロッコは無くなっている")


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
