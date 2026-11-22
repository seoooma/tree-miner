extends Node
## 客からの注文（納品依頼）と評判。
## - 注文は「木の種類 × 丸太／板 × 本数 × 期限」。開放済みエリアによく生える木から出る
## - 普段どおり売る（販売のトラック、製材ライン前は製材所の投入口）と、合う品は注文に数えられ、割増の代金が入る
## - 本数がそろうと評判が上がる。期限が切れた注文は消えるだけ（罰はない）。空いた枠には少し待つと次の注文が来る
## - 評判は次のエリアを開放する条件になる（balance.json の areas[].rep_required）
## 状態（注文の一覧・評判）は GameState に置き、セーブもそちらで行う。数値は balance.json の orders。

signal orders_changed
## 注文を1つ達成した（評判が上がった）
signal order_completed(order: Dictionary)

## 止めると注文の期限・次の注文までの待ち時間が進まない（テスト・撮影用）
var running := true

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func cfg() -> Dictionary:
	return GameData.orders


## 今の評判で出せる注文の数
func slot_count() -> int:
	var n := int(cfg().get("slots", 2))
	for at in cfg().get("extra_slot_at_rep", []):
		if GameState.reputation >= int(at):
			n += 1
	return n


func _process(delta: float) -> void:
	if not running:
		return
	tick(delta)


## 期限を進め、空いた枠に新しい注文を出す
func tick(delta: float) -> void:
	var changed := false
	for i in range(GameState.orders.size() - 1, -1, -1):
		var o: Dictionary = GameState.orders[i]
		o["time_left"] = float(o.get("time_left", 0.0)) - delta
		if o["time_left"] <= 0.0:
			GameState.orders.remove_at(i)
			changed = true
	if GameState.orders.size() < slot_count():
		GameState.order_cooldown -= delta
		if GameState.order_cooldown <= 0.0:
			var o := make_order()
			if not o.is_empty():
				GameState.orders.append(o)
				changed = true
			GameState.order_cooldown = float(cfg().get("cooldown_sec", 20.0))
	if changed:
		orders_changed.emit()


## 注文に出せる木（開放済みのどれかのエリアで、重みが min_weight 以上の木）。グレード順
func candidate_trees() -> Array[String]:
	var min_w := float(cfg().get("min_weight", 10))
	var out: Array[String] = []
	for t in GameData.trees:
		var id := str(t["id"])
		for i in GameState.unlocked_area_count:
			if float(GameData.areas[i].get("weights", {}).get(id, 0)) >= min_w:
				out.append(id)
				break
	return out


## 注文を1つ作る（まだ一覧には入れない）。出せる組み合わせが無ければ空
func make_order(tree_id := "", kind := "") -> Dictionary:
	var kinds: Array[String] = ["log"]
	if GameState.level("sawmill") > 0:
		kinds = ["plank", "plank", "log"]
	if tree_id == "" or kind == "":
		# 今出ている注文と同じ組み合わせは避ける
		var options: Array = []
		for t in candidate_trees():
			for k in kinds:
				if not _has_order(t, k):
					options.append([t, k])
			# 工房の品（作る設定にしている品だけ）
			var r := _recipe_of_tree(t)
			if GameState.level("workshop") > 0 and not r.is_empty() and GameState.is_recipe_on(str(r["id"])) and not _has_order(t, "goods"):
				options.append([t, "goods"])
		if options.is_empty():
			return {}
		var pick: Array = options[_rng.randi() % options.size()]
		tree_id = pick[0]
		kind = pick[1]
	var grade := maxi(0, GameData.tree_grade(tree_id))
	var c := cfg()
	var base := float(c.get("base_qty", {}).get(kind, 10))
	var grade_scale: Array = c.get("grade_qty", [1.0])
	var g_scale := float(grade_scale[mini(grade, grade_scale.size() - 1)])
	var rep_scale := minf(1.0 + GameState.reputation * float(c.get("qty_per_rep", 0.0)), float(c.get("max_qty_scale", 3.0)))
	var need := maxi(3, roundi(base * g_scale * rep_scale))
	var secs := need * float(c.get("sec_per_item", {}).get(kind, 15)) * (1.0 + grade * float(c.get("time_per_grade", 0.25))) + float(c.get("min_time_sec", 120))
	var rep := int(c.get("rep_base", 1)) + grade * int(c.get("rep_per_grade", 1))
	if kind == "plank":
		rep += int(c.get("rep_plank_bonus", 1))
	elif kind == "goods":
		rep += int(c.get("rep_goods_bonus", 2))
	# 親方の腕前「名声」で上がる評判が増える
	rep = ceili(rep * maxf(1.0, GameState.perk_value("fame")))
	return {
		"tree": tree_id,
		"kind": kind,
		"need": need,
		"done": 0,
		"time_left": secs,
		"time_total": secs,
		"mult": float(c.get("mult", {}).get(kind, 1.5)) + GameState.perk_value("regulars"),
		"rep": rep,
	}


## その木を材料にする工房の品（無ければ空）
static func _recipe_of_tree(tree_id: String) -> Dictionary:
	for r in GameData.recipes:
		if str(r["tree"]) == tree_id:
			return r
	return {}


func _has_order(tree_id: String, kind: String) -> bool:
	for o in GameState.orders:
		if o["tree"] == tree_id and o["kind"] == kind:
			return true
	return false


## 品物を1つ売った。合う注文があれば数えて、割増の代金（売値に足す分）を返す。注文がそろったら評判を上げる
func record_sale(kind: String, tree_id: String, price: int) -> int:
	for i in GameState.orders.size():
		var o: Dictionary = GameState.orders[i]
		if o["tree"] != tree_id or o["kind"] != kind or int(o["done"]) >= int(o["need"]):
			continue
		o["done"] = int(o["done"]) + 1
		var extra := roundi(price * (float(o["mult"]) - 1.0))
		if int(o["done"]) >= int(o["need"]):
			GameState.orders.remove_at(i)
			GameState.add_reputation(int(o["rep"]))
			GameState.order_cooldown = minf(GameState.order_cooldown, float(cfg().get("cooldown_sec", 20.0)))
			order_completed.emit(o)
		orders_changed.emit()
		return extra
	return 0


## 品物の名前（例「マツの板」「マツの丸太」「マツの棚」）
static func item_name(kind: String, tree_id: String) -> String:
	if kind == "goods":
		var r := _recipe_of_tree(tree_id)
		return GameData.recipe_name(str(r["id"])) if not r.is_empty() else GameData.tree_name(tree_id)
	return GameData.tree_name(tree_id) + ("の板" if kind == "plank" else "の丸太")
