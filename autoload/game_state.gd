extends Node
## プレイ中に変化する状態（所持金・強化レベル・開放エリア）と、そのセーブ/ロード。

signal money_changed(money: int)
signal upgrade_changed(id: String, level: int)
signal area_unlocked(index: int)

const SAVE_PATH := "user://save.json"
const AUTOSAVE_SEC := 5.0

var money: int = 0
var levels: Dictionary = {}
var unlocked_area_count: int = 1
## エリア開放の支払い途中の金額（途中で離れても続きから払える）
var gate_paid: Dictionary = {}

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


func buy_upgrade(id: String) -> bool:
	if is_maxed(id) or not spend(next_cost(id)):
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


# ---- セーブ ----

func save_game() -> void:
	if not save_enabled:
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"version": 1,
		"money": money,
		"levels": levels,
		"unlocked_area_count": unlocked_area_count,
		"gate_paid": gate_paid,
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


func reset_state() -> void:
	money = int(GameData.economy.get("start_money", 0))
	levels = {}
	unlocked_area_count = 1
	gate_paid = {}


## デバッグ用: セーブを消して最初から。
func reset_game() -> void:
	reset_state()
	save_game()
