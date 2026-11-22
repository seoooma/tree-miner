extends Node
## 重さの確認用（tools/cloud/probe.sh）。後半の状態を作り、10秒ごとに描画の統計・ノード数・施設ごとのメッシュ数を出す。
var main: Node3D
func _ready() -> void:
	GameState.save_enabled = false
	GameState.reset_game()
	seed(4)
	GameState.add_money(5000000)
	GameState.reputation = 200
	for i in 5:
		GameState.unlock_area(i)
	for i in 5:
		GameState.unlock_river_point(i)
	for id in ["sawmill", "river", "conveyor", "lumberjack", "lumberjack", "lumberjack", "lumberjack", "dock", "plank_belt", "workshop", "harvester", "hauler"]:
		GameState.buy_upgrade(id)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	var t0 := Time.get_ticks_msec()
	for k in 3:
		await get_tree().create_timer(10.0).timeout
		_report(k)
	get_tree().quit()
func _count(n: Node, d: Dictionary) -> void:
	d["all"] = d.get("all", 0) + 1
	if n is MeshInstance3D: d["mesh"] = d.get("mesh", 0) + 1
	if n is CPUParticles3D: d["particles"] = d.get("particles", 0) + 1
	if n is SubViewport: d["subvp"] = d.get("subvp", 0) + 1
	if n is Light3D: d["light"] = d.get("light", 0) + 1
	for c in n.get_children(): _count(c, d)
func _report(k: int) -> void:
	var by := {}
	for c in main.get_children():
		var d2 := {}
		_count(c, d2)
		var key: String = c.get_script().get_global_name() if c.get_script() else c.get_class()
		by[key] = by.get(key, 0) + d2.get("mesh", 0)
	print(by)
	var d := {}
	_count(get_tree().root, d)
	print("t=%ds fps=%d draws=%d objs=%d prims=%d vmem=%.1fMB tex=%.1fMB nodes=%s" % [(k+1)*10, Engine.get_frames_per_second(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)/1048576.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)/1048576.0, d])
