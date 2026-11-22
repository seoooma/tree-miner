class_name MasterPage
extends VBoxContainer
## 強化画面の「親方」タブの中身。いまの山と親方の腕前、別の山へ移るボタン、腕前で買う強化（ずっと残る）。
## 移るボタンは取り消せないので、1回目は「もう一度押すと移る」に変わり、続けて押したときだけ移る。

## 別の山へ移ったあとに呼ぶ（HUD がメインの場面を作り直す）
var on_moved: Callable = func() -> void: pass
## なぞってスクロールした直後の指離れでボタンが押されないようにする（HUD の判定）
var tap_suppressed: Callable = func() -> bool: return false

var _mountain_label: Label
var _points_label: Label
var _move_desc: Label
var _move_button: Button
var _confirm_until := 0
## 強化ごとの表示 {id: {lv, value, button}}
var _perk_rows: Dictionary = {}


func _ready() -> void:
	add_theme_constant_override("separation", 26)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# いまの山と腕前、移るボタン
	var card := _card()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	_mountain_label = _dark_label("", 30)
	box.add_child(_mountain_label)
	_points_label = _dark_label("", 26, Color("#8a5a10"))
	box.add_child(_points_label)
	_move_desc = _dark_label("", 20, Color("#5e5e5e"))
	_move_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_move_desc)
	_move_button = Button.new()
	_move_button.custom_minimum_size = Vector2(0, 92)
	_move_button.focus_mode = Control.FOCUS_NONE
	_move_button.add_theme_font_size_override("font_size", 30)
	_move_button.add_theme_constant_override("outline_size", 10)
	_move_button.pressed.connect(_on_move_pressed)
	box.add_child(_move_button)

	var title := UiKit.label("親方の腕前で覚える（別の山へ移っても残る）", 26)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(title)
	for p in GameData.prestige.get("perks", []):
		_build_perk(p)

	GameState.perks_changed.connect(_refresh)
	GameState.area_unlocked.connect(func(_i: int) -> void: _refresh())
	GameState.reputation_changed.connect(func(_r: int) -> void: _refresh())
	_refresh()


func _card() -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.tex_box("card_metal", 14, 16))
	add_child(card)
	return card


static func _dark_label(text: String, size: int, color := Color("#1f1f1f")) -> Label:
	return UiKit.label(text, size, false, color, 0, UiKit.OUTLINE_DARK, false)


func _build_perk(p: Dictionary) -> void:
	var id := str(p["id"])
	var card := _card()
	card.custom_minimum_size = Vector2(0, 150)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.custom_minimum_size = Vector2(10, 0)
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(info)
	info.add_child(_dark_label(str(p.get("name", id)), 30))
	var lv := _dark_label("", 23)
	info.add_child(lv)
	var value := UiKit.label("", 23, false, UiKit.NEXT_YELLOW, 9, UiKit.NEXT_OUTLINE, false)
	info.add_child(value)
	var desc := _dark_label(str(p.get("desc", "")), 18, Color("#6e6e6e"))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(desc)
	var button := Button.new()
	button.custom_minimum_size = Vector2(196, 96)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 28)
	button.add_theme_constant_override("outline_size", 10)
	button.pressed.connect(func() -> void:
		if tap_suppressed.call():
			return
		if GameState.buy_perk(id):
			Audio.play("buy", -4.0)
		else:
			Audio.play("ui", -8.0, 0.8))
	row.add_child(button)
	_perk_rows[id] = {"lv": lv, "value": value, "button": button}


func _refresh() -> void:
	var m := GameState.mountain
	_mountain_label.text = "いまの山: %s（%d つ目）" % [GameData.mountain_name(m), m + 1]
	_points_label.text = "親方の腕前: %d 点" % GameState.skill_points
	var next_name := GameData.mountain_name(m + 1)
	var next_price := GameData.mountain_price(m + 1)
	if GameState.can_move_mountain():
		_move_desc.text = "%s へ移れます。お金・強化・機械・エリア・評判は最初から。評判が高いほど腕前を多くもらえます（いま評判 %d）。%s は売値 x%.1f。" % [next_name, GameState.reputation, next_name, next_price]
	else:
		_move_desc.text = "いまの山のエリアをすべて開放すると、%s（売値 x%.1f）へ移れます。移るとお金・強化・エリア・評判は最初からになり、親方の腕前をもらえます。" % [next_name, next_price]
	_update_move_button()
	for id in _perk_rows:
		var row: Dictionary = _perk_rows[id]
		var lv := GameState.perk_level(id)
		var button: Button = row["button"]
		if GameState.perk_is_maxed(id):
			(row["lv"] as Label).text = "Lv.%d（最大）" % lv
			(row["value"] as Label).text = GameData.format_perk_value(id, lv)
			button.text = "MAX"
			button.disabled = true
			UiKit.skin_button(button, "btn_gray", "", 18, 10)
			continue
		(row["lv"] as Label).text = "Lv.%d ▶ Lv.%d" % [lv, lv + 1]
		(row["value"] as Label).text = "%s ▶ %s" % [GameData.format_perk_value(id, lv), GameData.format_perk_value(id, lv + 1)]
		var cost := GameState.perk_next_cost(id)
		button.text = "腕前 %d" % cost
		button.disabled = false
		if GameState.skill_points >= cost:
			UiKit.skin_button(button, "btn_green", "btn_green_pressed", 18, 10)
			button.add_theme_color_override("font_color", Color.WHITE)
		else:
			UiKit.skin_button(button, "btn_gray", "", 18, 10)
			button.add_theme_color_override("font_color", UiKit.PRICE_RED)


func _update_move_button() -> void:
	var can := GameState.can_move_mountain()
	_move_button.disabled = not can
	if not can:
		_move_button.text = "まだ移れない"
		UiKit.skin_button(_move_button, "btn_gray", "", 18, 10)
		return
	if Time.get_ticks_msec() < _confirm_until:
		_move_button.text = "もう一度押すと移る"
		UiKit.skin_button(_move_button, "btn_green", "btn_green_pressed", 18, 10)
		_move_button.add_theme_color_override("font_color", UiKit.NEXT_YELLOW)
	else:
		_move_button.text = "新しい山へ移る（腕前 +%d 点）" % GameState.move_points()
		UiKit.skin_button(_move_button, "btn_green", "btn_green_pressed", 18, 10)
		_move_button.add_theme_color_override("font_color", Color.WHITE)


func _process(_delta: float) -> void:
	# 「もう一度押すと移る」は少し待つと元に戻す
	if _confirm_until > 0 and Time.get_ticks_msec() >= _confirm_until:
		_confirm_until = 0
		_update_move_button()


func _on_move_pressed() -> void:
	if tap_suppressed.call() or not GameState.can_move_mountain():
		return
	if Time.get_ticks_msec() >= _confirm_until:
		_confirm_until = Time.get_ticks_msec() + 3000
		Audio.play("ui", -4.0)
		_update_move_button()
		return
	_confirm_until = 0
	if GameState.move_mountain():
		Audio.play("unlock", 0.0)
		on_moved.call()
