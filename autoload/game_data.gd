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
	trees = data.get("trees", [])
	areas = data.get("areas", [])
	upgrades = data.get("upgrades", [])
	upgrade_groups = []
	for g in data.get("upgrade_groups", []):
		if g is Dictionary and g.has("id"):
			upgrade_groups.append(g)

	_tree_index.clear()
	for t in trees:
		_tree_index[t["id"]] = t
	_upgrade_index.clear()
	for u in upgrades:
		_upgrade_index[u["id"]] = u


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
	return maxi(1, roundi(hardness * float(economy.get("price_per_hardness", 1.0))))


## 板の売値。丸太の売値 x plank_multiplier。
func plank_price(id: String) -> int:
	return maxi(1, roundi(log_price(id) * float(economy.get("plank_multiplier", 2.0))))


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
