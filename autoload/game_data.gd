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
var trees: Array = []
var areas: Array = []
var upgrades: Array = []

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
	trees = data.get("trees", [])
	areas = data.get("areas", [])
	upgrades = data.get("upgrades", [])

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


## 丸太の売値。硬さに比例する。
func log_price(id: String) -> int:
	var hardness := float(tree_def(id).get("hardness", 1))
	return maxi(1, roundi(hardness * float(economy.get("price_per_hardness", 1.0))))


## 板の売値。丸太の売値 x plank_multiplier。
func plank_price(id: String) -> int:
	return maxi(1, roundi(log_price(id) * float(economy.get("plank_multiplier", 2.0))))


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
