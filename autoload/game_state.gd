extends Node
## プレイ中に変化する状態（所持金・強化レベル・開放エリア）と、そのセーブ/ロード。

signal money_changed(money: int)
signal upgrade_changed(id: String, level: int)
signal area_unlocked(index: int)
signal machine_changed(kind: String, rank: int)
signal lumberjack_role_changed(index: int, role: String)
## セーブの直前。施設（集積所・製材所・出荷場）が在庫を stock に書き込む
signal saving

const SAVE_PATH := "user://save.json"
const AUTOSAVE_SEC := 5.0

var money: int = 0
var levels: Dictionary = {}
var unlocked_area_count: int = 1
## エリア開放の支払い途中の金額（途中で離れても続きから払える）
var gate_paid: Dictionary = {}
## 機械のランク（0 = 未購入）。例 {"harvester": 1}
var machine_ranks: Dictionary = {}
## 機械購入パッドの支払い途中の金額
var shop_paid: Dictionary = {}
## 機械の燃料・位置（機械自身が毎フレーム書き込む）
var machine_state: Dictionary = {}
## 伐採員ごとの役割 "chop" / "haul"
var lumberjack_roles: Array = []
## 施設に溜まっている丸太・板（木のIDの配列）。例 {"yard": [...], "sawmill_queue": [...], "sawmill_output": [...], "dock": [...]}
var stock: Dictionary = {}

## false にするとセーブしない（テスト用）
var save_enabled := true

var _autosave_timer := 0.0


func _ready() -> void:
	load_game()


func _process(delta: float) -> void:
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_SEC:
		_autosave_timer = 0.0
		save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_game()


# ---- お金 ----

func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)


func spend(amount: int) -> bool:
	if amount > money:
		return false
	money -= amount
	money_changed.emit(money)
	return true


# ---- 強化 ----

func level(id: String) -> int:
	return int(levels.get(id, 0))


func value(id: String) -> float:
	return GameData.upgrade_value(id, level(id))


func is_maxed(id: String) -> bool:
	return level(id) >= GameData.upgrade_max_level(id)


func next_cost(id: String) -> int:
	return GameData.upgrade_cost(id, level(id))


## 先に開放が必要な強化（requires）が済んでいるか
func is_available(id: String) -> bool:
	var req := str(GameData.upgrade_def(id).get("requires", ""))
	return req == "" or level(req) > 0


func buy_upgrade(id: String) -> bool:
	if is_maxed(id) or not is_available(id) or not spend(next_cost(id)):
		return false
	levels[id] = level(id) + 1
	upgrade_changed.emit(id, levels[id])
	save_game()
	return true


# ---- エリア ----

func is_area_unlocked(index: int) -> bool:
	return index < unlocked_area_count


func gate_remaining(index: int) -> int:
	var cost := int(GameData.areas[index].get("unlock_cost", 0))
	return maxi(0, cost - int(gate_paid.get(str(index), 0)))


## エリア開放に向けて最大 amount だけ支払う。実際に払った額を返す。
func pay_toward_area(index: int, amount: int) -> int:
	var pay := mini(amount, mini(money, gate_remaining(index)))
	if pay <= 0:
		return 0
	spend(pay)
	gate_paid[str(index)] = int(gate_paid.get(str(index), 0)) + pay
	if gate_remaining(index) == 0:
		unlock_area(index)
	return pay


func unlock_area(index: int) -> void:
	if is_area_unlocked(index):
		return
	unlocked_area_count = index + 1
	gate_paid.erase(str(index))
	area_unlocked.emit(index)
	save_game()


# ---- 機械 ----

func machine_rank(kind: String) -> int:
	return int(machine_ranks.get(kind, 0))


func machine_next_cost(kind: String) -> int:
	return int(GameData.machine_rank(kind, machine_rank(kind) + 1).get("cost", 0))


func machine_is_maxed(kind: String) -> bool:
	return machine_rank(kind) >= GameData.machine_rank_count(kind)


func shop_remaining(kind: String) -> int:
	if machine_is_maxed(kind):
		return 0
	return maxi(0, machine_next_cost(kind) - int(shop_paid.get(kind, 0)))


## 機械の購入に向けて最大 amount だけ支払う。払い終わるとランクが上がる。
func pay_toward_machine(kind: String, amount: int) -> int:
	if machine_is_maxed(kind):
		return 0
	var pay := mini(amount, mini(money, shop_remaining(kind)))
	if pay <= 0:
		return 0
	spend(pay)
	shop_paid[kind] = int(shop_paid.get(kind, 0)) + pay
	if shop_remaining(kind) == 0:
		shop_paid.erase(kind)
		machine_ranks[kind] = machine_rank(kind) + 1
		machine_changed.emit(kind, machine_ranks[kind])
		save_game()
	return pay


# ---- 伐採員の役割 ----

func lumberjack_role(index: int) -> String:
	if index < lumberjack_roles.size():
		return str(lumberjack_roles[index])
	# 未設定なら 伐採, 運搬, 伐採, ... の順
	return "chop" if index % 2 == 0 else "haul"


func set_lumberjack_role(index: int, role: String) -> void:
	while lumberjack_roles.size() <= index:
		lumberjack_roles.append(lumberjack_role(lumberjack_roles.size()))
	lumberjack_roles[index] = role
	lumberjack_role_changed.emit(index, role)
	save_game()


# ---- セーブ ----

## 施設の在庫（木のIDの配列）
func stock_list(key: String) -> Array[String]:
	var out: Array[String] = []
	for id in stock.get(key, []):
		if GameData.tree_def(str(id)).is_empty():
			continue
		out.append(str(id))
	return out


func save_game(collect := true) -> void:
	if not save_enabled:
		return
	if collect:
		saving.emit()
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"version": 1,
		"money": money,
		"levels": levels,
		"unlocked_area_count": unlocked_area_count,
		"gate_paid": gate_paid,
		"machine_ranks": machine_ranks,
		"shop_paid": shop_paid,
		"machine_state": machine_state,
		"lumberjack_roles": lumberjack_roles,
		"stock": stock,
	}))


func load_game() -> void:
	reset_state()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	money = int(parsed.get("money", money))
	var saved_levels: Dictionary = parsed.get("levels", {})
	for id in saved_levels:
		levels[id] = int(saved_levels[id])
	unlocked_area_count = clampi(int(parsed.get("unlocked_area_count", 1)), 1, GameData.areas.size())
	gate_paid = parsed.get("gate_paid", {})
	var ranks: Dictionary = parsed.get("machine_ranks", {})
	for kind in ranks:
		machine_ranks[kind] = int(ranks[kind])
	shop_paid = parsed.get("shop_paid", {})
	machine_state = parsed.get("machine_state", {})
	lumberjack_roles = parsed.get("lumberjack_roles", [])
	var saved_stock: Variant = parsed.get("stock", {})
	if typeof(saved_stock) == TYPE_DICTIONARY:
		stock = saved_stock


func reset_state() -> void:
	money = int(GameData.economy.get("start_money", 0))
	levels = {}
	unlocked_area_count = 1
	gate_paid = {}
	machine_ranks = {}
	shop_paid = {}
	machine_state = {}
	lumberjack_roles = []
	stock = {}


## デバッグ用: セーブを消して最初から。
func reset_game() -> void:
	reset_state()
	save_game(false)
