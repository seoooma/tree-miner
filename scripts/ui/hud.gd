class_name Hud
extends CanvasLayer
## 画面UI: 所持金・積荷数・強化パネル・バーチャルスティック。

var player: Player

var _money_label: Label
var _carry_label: Label
var _panel: PanelContainer
var _rows: Dictionary = {}


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)

	# スティックは一番下に置き、ボタン類がタッチを優先して受け取れるようにする
	var joystick := VirtualJoystick.new()
	root.add_child(joystick)
	joystick.vector_changed.connect(func(v: Vector2) -> void:
		if player:
			player.joystick_vector = v)

	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 24
	top.offset_right = -24
	top.offset_top = 24
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	_money_label = _chip_label(top, "¥0")
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	_carry_label = _chip_label(top, "積荷 0/0")

	var upgrade_button := Button.new()
	upgrade_button.text = "強化"
	upgrade_button.custom_minimum_size = Vector2(200, 110)
	upgrade_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	upgrade_button.offset_left = -224
	upgrade_button.offset_top = -134
	upgrade_button.offset_right = -24
	upgrade_button.offset_bottom = -24
	upgrade_button.add_theme_font_size_override("font_size", 40)
	upgrade_button.pressed.connect(func() -> void: _panel.visible = not _panel.visible)
	root.add_child(upgrade_button)

	_build_upgrade_panel(root)

	GameState.money_changed.connect(func(_m: int) -> void: _refresh())
	GameState.upgrade_changed.connect(func(_id: String, _l: int) -> void: _refresh())
	_refresh()


func bind_player(p: Player) -> void:
	player = p
	player.carry_changed.connect(func(count: int, cap: int) -> void:
		_carry_label.text = "積荷 %d/%d" % [count, cap]
		_carry_label.modulate = Color("#ff8a7a") if count >= cap else Color.WHITE)


func _make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 30
	return theme


func _chip_label(parent: Control, text: String) -> Label:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.45)
	style.set_corner_radius_all(16)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 38)
	panel.add_child(label)
	return label


func _build_upgrade_panel(root: Control) -> void:
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = 24
	_panel.offset_right = -24
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.1, 0.94)
	style.set_corner_radius_all(24)
	style.set_content_margin_all(24)
	_panel.add_theme_stylebox_override("panel", style)
	root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	_panel.add_child(vbox)
	var title := Label.new()
	title.text = "強化"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	vbox.add_child(title)

	for def in GameData.upgrades:
		var id := str(def["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		vbox.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var name_label := Label.new()
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(name_label)
		var desc := Label.new()
		desc.text = str(def.get("desc", ""))
		desc.add_theme_font_size_override("font_size", 22)
		desc.modulate = Color(1, 1, 1, 0.7)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(desc)
		var button := Button.new()
		button.custom_minimum_size = Vector2(180, 80)
		button.pressed.connect(func() -> void: GameState.buy_upgrade(id))
		row.add_child(button)
		_rows[id] = {"name": name_label, "button": button}

	var close := Button.new()
	close.text = "閉じる"
	close.custom_minimum_size = Vector2(0, 80)
	close.pressed.connect(func() -> void: _panel.visible = false)
	vbox.add_child(close)


func _refresh() -> void:
	_money_label.text = "¥%d" % GameState.money
	for id in _rows:
		var row: Dictionary = _rows[id]
		var lv := GameState.level(id)
		var def := GameData.upgrade_def(id)
		var now := GameData.format_upgrade_value(id, lv)
		var name_label: Label = row["name"]
		var button: Button = row["button"]
		if GameState.is_maxed(id):
			name_label.text = "%s  Lv%d  (%s)" % [def.get("name", id), lv, now]
			button.text = "MAX"
			button.disabled = true
		else:
			var next := GameData.format_upgrade_value(id, lv + 1)
			name_label.text = "%s  Lv%d  %s → %s" % [def.get("name", id), lv, now, next]
			var cost := GameState.next_cost(id)
			button.text = "¥%d" % cost
			button.disabled = GameState.money < cost
