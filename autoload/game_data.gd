extends Node
## バランス設定 (data/balance.json) を読み込んで、各スクリプトから参照できるようにする。
## 値を変えたいときはコードではなく JSON を編集する。

const BALANCE_PATH := "res://data/balance.json"

var economy: Dictionary = {}
var player: Dictionary = {}
var lumberjack: Dictionary = {}
var sawmill: Dictionary = {}
var dock: Dictionary = {}
var world: Dictionary = {}
var camera: Dictionary = {}
var drops: Dictionary = {}
var fuel: Dictionary = {}
var machines: Dictionary = {}
var orders: Dictionary = {}
var workshop: Dictionary = {}
## 工房で作る品（balance.json の workshop.recipes）
var recipes: Array = []
var prestige: Dictionary = {}
## 山（周回ごとの舞台）。apply_mountain で trees / areas を上書きする
var mountains: Array = []
## いまの山の番号（0 = 最初の山。移るたびに 1 ずつ増える）
var mountain := 0
## 売値に掛ける倍率（山の倍率 x 親方の腕前「目利き」。GameState が設定する）
var price_mult := 1.0
## 山の売値の倍率（apply_mountain で決まる）
var mountain_price_mult := 1.0
## 地面の色に掛ける色
var ground_tint := Color.WHITE
## 上書き前の trees / areas（山を切り替えるたびにここから作り直す）
var _base_trees: Array = []
var _base_areas: Array = []
var trees: Array = []
var areas: Array = []
var upgrades: Array = []
## 強化画面のタブ（{id, name, icon, items}）。_comment だけの要素は除く
var upgrade_groups: Array = []

var _tree_index: Dictionary = {}
var _upgrade_index: Dictionary = {}


func _init() -> void:
	load_balance()


func load_balance() -> void:
	var file := FileAccess.open(BALANCE_PATH, FileAccess.READ)
	if file == null:
		push_error("balance.json を開けません: %s" % BALANCE_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("balance.json の形式が正しくありません")
		return
	var data: Dictionary = parsed
	economy = data.get("economy", {})
	player = data.get("player", {})
	lumberjack = data.get("lumberjack", {})
	sawmill = data.get("sawmill", {})
	dock = data.get("dock", {})
	world = data.get("world", {})
	camera = data.get("camera", {})
	drops = data.get("drops", {})
	fuel = data.get("fuel", {})
	machines = data.get("machines", {})
	orders = data.get("orders", {})
	workshop = data.get("workshop", {})
	recipes = workshop.get("recipes", [])
	_base_trees = data.get("trees", [])
	_base_areas = data.get("areas", [])
	prestige = data.get("prestige", {})
	mountains = data.get("mountains", [])
	upgrades = data.get("upgrades", [])
	upgrade_groups = []
	for g in data.get("upgrade_groups", []):
		if g is Dictionary and g.has("id"):
			upgrade_groups.append(g)

	apply_mountain(mountain)
	_upgrade_index.clear()
	for u in upgrades:
		_upgrade_index[u["id"]] = u


# ---- 山 ----

## 山の番号から mountains の何番目を使うか（最後まで行ったら1番から繰り返す）
func mountain_def_index(n: int) -> int:
	if mountains.is_empty():
		return -1
	if n < mountains.size():
		return n
	var loop := maxi(1, mountains.size() - 1)
	return 1 + (n - 1) % loop if mountains.size() > 1 else 0


func mountain_def(n: int) -> Dictionary:
	var i := mountain_def_index(n)
	return mountains[i] if i >= 0 else {}


## 山の名前。2周目以降は「紅葉の山（2度目）」のように何度目かを付ける
func mountain_name(n: int) -> String:
	var name := str(mountain_def(n).get("name", "山"))
	var times := _visit_count(n)
	return name if times <= 1 else "%s（%d度目）" % [name, times]


func _visit_count(n: int) -> int:
	if mountains.size() <= 1 or n < mountains.size():
		return 1
	return 1 + floori(float(n - 1) / float(mountains.size() - 1))


## 山の売値の倍率（繰り返すたびに repeat_price_growth 倍）
func mountain_price(n: int) -> float:
	return float(mountain_def(n).get("price_mult", 1.0)) * pow(float(prestige.get("repeat_price_growth", 1.25)), _visit_count(n) - 1)


## 山 n の木・エリアにする（名前・色・モデル・生え直す時間を上書き）。見た目のキャッシュも捨てる
func apply_mountain(n: int) -> void:
	mountain = maxi(0, n)
	var m := mountain_def(mountain)
	var tree_over: Dictionary = m.get("trees", {})
	var respawn := float(m.get("respawn_mult", 1.0))
	trees = []
	for t in _base_trees:
		var copy: Dictionary = (t as Dictionary).duplicate(true)
		var over: Dictionary = tree_over.get(str(copy["id"]), {})
		for key in over:
			copy[key] = over[key]
		copy["respawn_sec"] = float(copy.get("respawn_sec", 8.0)) * respawn
		trees.append(copy)
	var area_over: Array = m.get("areas", [])
	areas = []
	for i in _base_areas.size():
		var copy: Dictionary = (_base_areas[i] as Dictionary).duplicate(true)
		if i < area_over.size():
			for key in area_over[i]:
				copy[key] = area_over[i][key]
		areas.append(copy)
	ground_tint = Color(str(m.get("ground_tint", "#ffffff")))
	mountain_price_mult = mountain_price(mountain)
	_tree_index.clear()
	for t in trees:
		_tree_index[t["id"]] = t
	Fx._meshes.clear()


# ---- 木 ----

func tree_def(id: String) -> Dictionary:
	return _tree_index.get(id, {})


func tree_name(id: String) -> String:
	return str(tree_def(id).get("name", id))


## 木のグレード（balance.json の trees の並び順。0 = いちばん安い木）。知らない ID は -1
func tree_grade(id: String) -> int:
	for i in trees.size():
		if str(trees[i]["id"]) == id:
			return i
	return -1


## 製材所で1本を板にする時間の倍率（硬い木ほど大きい）。
func saw_time(id: String) -> float:
	return maxf(0.1, float(tree_def(id).get("saw_time", 1.0)))


## 丸太の売値。硬さに比例する。
func log_price(id: String) -> int:
	var hardness := float(tree_def(id).get("hardness", 1))
	return maxi(1, roundi(hardness * float(economy.get("price_per_hardness", 1.0)) * price_mult))


## 板の売値。丸太の売値 x plank_multiplier。
func plank_price(id: String) -> int:
	var hardness := float(tree_def(id).get("hardness", 1))
	return maxi(1, roundi(hardness * float(economy.get("price_per_hardness", 1.0)) * price_mult * float(economy.get("plank_multiplier", 2.0))))


# ---- 工房 ----

## 品の名前（{tree} を材料の木の名前にする）
func recipe_name(id: String) -> String:
	var r := recipe_def(id)
	return str(r.get("name", id)).replace("{tree}", tree_name(str(r.get("tree", ""))))


func recipe_def(id: String) -> Dictionary:
	for r in recipes:
		if str(r["id"]) == id:
			return r
	return {}


## 材料（"plank" / "log" と木の ID）から作る品。無ければ空
func recipe_for(kind: String, tree_id: String) -> Dictionary:
	for r in recipes:
		if str(r["input"]) == kind and str(r["tree"]) == tree_id:
			return r
	return {}


## 品の売値 = 材料の数 x 材料の売値 x price_mult
func goods_price(recipe_id: String) -> int:
	var r := recipe_def(recipe_id)
	if r.is_empty():
		return 1
	var tree_id := str(r["tree"])
	var hardness := float(tree_def(tree_id).get("hardness", 1)) * float(economy.get("price_per_hardness", 1.0))
	var unit := hardness if str(r["input"]) == "log" else hardness * float(economy.get("plank_multiplier", 2.0))
	return maxi(1, roundi(int(r.get("count", 1)) * unit * float(r.get("price_mult", 1.5)) * price_mult))


# ---- 親方の腕前（周回をまたいで残る強化） ----

func perk_def(id: String) -> Dictionary:
	for p in prestige.get("perks", []):
		if str(p["id"]) == id:
			return p
	return {}


func perk_value(id: String, level: int) -> float:
	var p := perk_def(id)
	return float(p.get("base", 0.0)) + float(p.get("per_level", 0.0)) * level


## 次のレベルの値段（腕前の点）
func perk_cost(id: String, level: int) -> int:
	var p := perk_def(id)
	return int(p.get("cost", 1)) + level * int(p.get("cost_step", 1))


func format_perk_value(id: String, level: int) -> String:
	var p := perk_def(id)
	var decimals := int(p.get("decimals", 0))
	var v := perk_value(id, level)
	var text := ("%d" % roundi(v)) if decimals == 0 else (("%." + str(decimals) + "f") % v)
	var unit := str(p.get("unit", ""))
	if unit == "円":
		return "¥" + text
	if id == "regulars":
		return "+" + text
	return text + unit


## エリアの開放に要る評判
func area_rep_required(index: int) -> int:
	if index < 0 or index >= areas.size():
		return 0
	return int(areas[index].get("rep_required", 0))


## エリアの重み付き抽選で木の種類を決める。
func pick_tree_for_area(area_index: int, rng: RandomNumberGenerator) -> String:
	var weights: Dictionary = areas[area_index].get("weights", {})
	var total := 0.0
	for id in weights:
		total += float(weights[id])
	if total <= 0.0:
		return str(trees[0]["id"])
	var roll := rng.randf() * total
	for id in weights:
		roll -= float(weights[id])
		if roll <= 0.0:
			return str(id)
	return str(weights.keys().back())


# ---- 強化 ----

## 強化（または機械）が入っている強化画面のタブの id。どのタブにも無ければ空文字
func upgrade_group_of(id: String) -> String:
	for g in upgrade_groups:
		if (g.get("items", []) as Array).has(id):
			return str(g["id"])
	return ""


func upgrade_def(id: String) -> Dictionary:
	return _upgrade_index.get(id, {})


func upgrade_value(id: String, level: int) -> float:
	var d := upgrade_def(id)
	return float(d.get("base_value", 0.0)) + float(d.get("per_level", 0.0)) * level


func upgrade_cost(id: String, level: int) -> int:
	var d := upgrade_def(id)
	return roundi(float(d.get("base_cost", 10)) * pow(float(d.get("cost_growth", 1.5)), level))


func upgrade_max_level(id: String) -> int:
	return int(upgrade_def(id).get("max_level", 10))


func format_upgrade_value(id: String, level: int) -> String:
	var d := upgrade_def(id)
	if d.get("locked_at_zero", false) and level == 0:
		return "未開放"
	var decimals := int(d.get("decimals", 0))
	var v := upgrade_value(id, level)
	var text := ("%d" % roundi(v)) if decimals == 0 else (("%." + str(decimals) + "f") % v)
	return text + str(d.get("unit", ""))


# ---- 機械 ----

## kind ("harvester" / "hauler") のランク数
func machine_rank_count(kind: String) -> int:
	return (machines.get(kind, {}).get("ranks", []) as Array).size()


## rank は 1 始まり（0 = 未購入）
func machine_rank(kind: String, rank: int) -> Dictionary:
	var ranks: Array = machines.get(kind, {}).get("ranks", [])
	if rank < 1 or rank > ranks.size():
		return {}
	return ranks[rank - 1]


func machine_name(kind: String) -> String:
	return str(machines.get(kind, {}).get("name", kind))


## 強化画面のカードに出す代表の性能（伐採機は伐採力、運搬車は積載量）。rank 0 は未購入
func machine_stat(kind: String, rank: int) -> float:
	var stat := str(machines.get(kind, {}).get("stat", ""))
	return float(machine_rank(kind, rank).get(stat, 0.0))


func format_machine_value(kind: String, rank: int) -> String:
	if rank <= 0:
		return "未購入"
	return "%d%s" % [roundi(machine_stat(kind, rank)), str(machines.get(kind, {}).get("unit", ""))]
