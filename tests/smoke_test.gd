extends Node
## ヘッドレスで一通りのループ（伐採→売却→強化→製材→出荷→エリア開放）が動くか確認するスモークテスト。
## 実行: godot --headless --fixed-fps 60 --path . res://tests/smoke_test.tscn
## 成功で終了コード0、失敗で1。

var main: Node3D
var player: Player
var _failed := false


func _ready() -> void:
	GameState.save_enabled = false  # プレイ中のセーブデータを上書きしない
	GameState.reset_game()
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
	# 1. 伐採して丸太を集める
	await _gather_until_full()
	_check(player.stack.count("log") == player.capacity(), "運搬容量いっぱいまで丸太を集められる (%d)" % player.stack.size())

	# 2. 製材所（ライン未開放）で丸太を売る
	await _walk_to(main.sawmill.input_position(), 0.5)
	await _wait(2.0)
	_check(player.stack.is_empty(), "製材所で丸太を全部渡せる")
	_check(GameState.money > 0, "丸太の売却でお金が増える (¥%d)" % GameState.money)

	# 3. 強化
	GameState.add_money(100000)
	var cap_before := player.capacity()
	_check(GameState.buy_upgrade("capacity"), "運搬容量を強化できる")
	_check(player.capacity() > cap_before, "強化で容量が増える (%d → %d)" % [cap_before, player.capacity()])
	_check(GameState.buy_upgrade("sawmill"), "製材ラインを開放できる")
	_check(GameState.buy_upgrade("lumberjack"), "伐採員を雇える")
	await get_tree().process_frame
	_check(main.lumberjacks.size() == 1, "伐採員がマップに出る")

	# 4. 製材 → 出荷
	await _gather_until_full()
	await _walk_to(main.sawmill.input_position(), 0.5)
	await _wait(2.0)
	_check(not main.sawmill.queue.is_empty() or not main.sawmill.output.is_empty(), "ライン開放後は丸太が加工待ちに入る")
	await _wait(20.0)
	_check(main.sawmill.output.size() > 0, "丸太が板に加工される (%d枚)" % main.sawmill.output.size())
	await _walk_to(main.sawmill.output_position(), 0.5)
	await _wait(2.0)
	_check(player.stack.count("plank") > 0, "出口で板を受け取れる (%d枚)" % player.stack.count("plank"))
	var money_before := GameState.money
	await _walk_to(main.DOCK_POS, 0.5)
	await _wait(2.0)
	_check(GameState.money > money_before, "出荷場で板が売れる (+¥%d)" % (GameState.money - money_before))

	# 5. 伐採員が働いている
	_check(main.sawmill.queue.size() + main.sawmill.output.size() > 0 or main.lumberjacks[0].state != Lumberjack.State.FIND_TREE, "伐採員が稼働している")

	# 6. エリア開放
	var gate_pad := Vector3(0, 0, main._area_ranges[1].x + AreaGate.PAD_OFFSET.z)
	await _walk_to(gate_pad, 0.4)
	await _wait(4.0)
	_check(GameState.is_area_unlocked(1), "柵の前で支払うとエリア1が開放される")


func _gather_until_full() -> void:
	var deadline := 3000
	while not player.stack.is_full() and deadline > 0:
		var tree := _nearest_tree()
		if tree == null:
			break
		var frames := 0
		while tree.alive and not player.stack.is_full() and frames < 600:
			var to := tree.global_position - player.global_position
			to.y = 0
			player.joystick_vector = Vector2(to.x, to.z).normalized() if to.length() > 1.0 else Vector2.ZERO
			await get_tree().physics_frame
			frames += 1
			deadline -= 1
	player.joystick_vector = Vector2.ZERO


func _nearest_tree() -> ChoppableTree:
	var best: ChoppableTree = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group("trees"):
		var t := node as ChoppableTree
		if t.alive and GameState.is_area_unlocked(t.area_index):
			var d := Fx.xz_distance(t.global_position, player.global_position)
			if d < best_d:
				best_d = d
				best = t
	return best


func _walk_to(target: Vector3, arrive: float) -> void:
	var frames := 0
	while Fx.xz_distance(player.global_position, target) > arrive and frames < 1200:
		var to := target - player.global_position
		player.joystick_vector = Vector2(to.x, to.z).normalized()
		await get_tree().physics_frame
		frames += 1
	player.joystick_vector = Vector2.ZERO
	if frames >= 1200:
		print("  (walk timeout to ", target, " at ", player.global_position, ")")


func _wait(sec: float) -> void:
	var frames := int(sec * 60)
	for i in frames:
		await get_tree().physics_frame
