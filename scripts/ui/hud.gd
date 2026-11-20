class_name Hud
extends CanvasLayer
## 画面UI: 所持金・積荷数・燃料・乗り降りボタン・強化パネル（伐採員の役割切り替えを含む）・バーチャルスティック。

var player: Player

var _money_label: Label
var _carry_label: Label
var _panel: PanelContainer
var _upgrade_button: Button
var _board_button: Button
var _fuel_chip: Control
var _fuel_label: Label
var _roles_box: HFlowContainer
var _music_button: Button
var _sfx_button: Button
var _shown_money := 0
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

	var second := HBoxContainer.new()
	second.set_anchors_preset(Control.PRESET_TOP_WIDE)
	second.offset_left = 24
	second.offset_right = -24
	second.offset_top = 100
	second.mouse_filter = Control.MOUSE_FILTER_IGNORE
	second.add_theme_constant_override("separation", 10)
	root.add_child(second)
	_music_button = _small_button(second, "", func() -> void:
		Audio.toggle_music()
		_update_sound_buttons())
	_sfx_button = _small_button(second, "", func() -> void:
		Audio.toggle_sfx()
		_update_sound_buttons())
	_update_sound_buttons()
	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	second.add_child(spacer2)
	_fuel_label = _chip_label(second, "")
	_fuel_chip = _fuel_label.get_parent()
	_fuel_chip.visible = false

	_board_button = Button.new()
	_board_button.custom_minimum_size = Vector2(200, 110)
	_board_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_board_button.offset_left = 24
	_board_button.offset_top = -134
	_board_button.offset_right = 224
	_board_button.offset_bottom = -24
	_board_button.add_theme_font_size_override("font_size", 40)
	_style_button(_board_button, Color("#f08a2c"))
	_board_button.visible = false
	_board_button.pressed.connect(_toggle_board)
	root.add_child(_board_button)

	var upgrade_button := Button.new()
	upgrade_button.text = "強化"
	upgrade_button.custom_minimum_size = Vector2(200, 110)
	upgrade_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	upgrade_button.offset_left = -224
	upgrade_button.offset_top = -134
	upgrade_button.offset_right = -24
	upgrade_button.offset_bottom = -24
	upgrade_button.add_theme_font_size_override("font_size", 40)
	_style_button(upgrade_button, Color("#3fa34d"))
	upgrade_button.pressed.connect(func() -> void:
		Audio.play("ui", -4.0)
		_panel.visible = not _panel.visible)
	root.add_child(upgrade_button)
	_upgrade_button = upgrade_button

	_build_upgrade_panel(root)
	joystick.is_blocked = _is_over_ui

	GameState.money_changed.connect(func(_m: int) -> void: _refresh())
	GameState.upgrade_changed.connect(func(_id: String, _l: int) -> void:
		_refresh()
		_rebuild_roles())
	GameState.lumberjack_role_changed.connect(func(_i: int, _r: String) -> void: _rebuild_roles())
	_refresh()
	_rebuild_roles()


func _process(_delta: float) -> void:
	if player == null:
		return
	if player.vehicle:
		_board_button.visible = true
		_board_button.text = "降りる"
		var m := player.vehicle
		_fuel_chip.visible = true
		_fuel_label.text = "燃料 %d/%d" % [ceili(m.fuel), roundi(m.fuel_max())]
		_fuel_label.modulate = Color("#ff8a7a") if m.fuel <= 0.0 else Color.WHITE
	else:
		_fuel_chip.visible = false
		_board_button.visible = player.nearby_machine() != null
		_board_button.text = "乗る"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_E:
		_toggle_board()


func _toggle_board() -> void:
	if player == null:
		return
	if player.vehicle:
		player.exit_vehicle()
	else:
		player.board(player.nearby_machine())


func bind_player(p: Player) -> void:
	player = p
	player.carry_changed.connect(func(count: int, cap: int) -> void:
		_carry_label.text = "積荷 %d/%d" % [count, cap]
		_carry_label.modulate = Color("#ff8a7a") if count >= cap else Color.WHITE)


## スティックを出さない場所（ボタン・開いている強化パネルの上）
func _is_over_ui(pos: Vector2) -> bool:
	if _upgrade_button.get_global_rect().has_point(pos):
		return true
	for b in [_board_button, _music_button, _sfx_button]:
		if (b as Control).visible and (b as Control).get_global_rect().has_point(pos):
			return true
	return _panel.visible and _panel.get_global_rect().has_point(pos)


func _make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 30
	theme.set_stylebox("normal", "Button", _box(Color("#4a5a48")))
	theme.set_stylebox("hover", "Button", _box(Color("#566a54")))
	theme.set_stylebox("pressed", "Button", _box(Color("#3a4838"), true))
	theme.set_stylebox("disabled", "Button", _box(Color(0.3, 0.32, 0.3, 0.7)))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.45))
	theme.set_color("font_outline_color", "Label", Color(0.1, 0.07, 0.03, 0.6))
	theme.set_constant("outline_size", "Label", 6)
	return theme


static func _box(color: Color, pressed := false) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = color
	b.set_corner_radius_all(20)
	b.border_width_bottom = 2 if pressed else 7
	b.border_color = color.darkened(0.35)
	b.content_margin_left = 16
	b.content_margin_right = 16
	b.content_margin_top = 8
	b.content_margin_bottom = 8 if pressed else 12
	b.shadow_color = Color(0, 0, 0, 0.25)
	b.shadow_size = 4
	b.shadow_offset = Vector2(0, 3)
	return b


func _style_button(b: Button, color: Color) -> void:
	b.add_theme_stylebox_override("normal", _box(color))
	b.add_theme_stylebox_override("hover", _box(color.lightened(0.08)))
	b.add_theme_stylebox_override("pressed", _box(color.darkened(0.12), true))


func _small_button(parent: Control, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(96, 64)
	b.add_theme_font_size_override("font_size", 26)
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


func _update_sound_buttons() -> void:
	_music_button.text = "♪ ON" if Audio.music_enabled else "♪ OFF"
	_sfx_button.text = "SE ON" if Audio.sfx_enabled else "SE OFF"
	_music_button.modulate = Color.WHITE if Audio.music_enabled else Color(1, 1, 1, 0.6)
	_sfx_button.modulate = Color.WHITE if Audio.sfx_enabled else Color(1, 1, 1, 0.6)


func _chip_label(parent: Control, text: String) -> Label:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.06, 0.55)
	style.set_corner_radius_all(18)
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
	style.bg_color = Color(0.13, 0.16, 0.12, 0.95)
	style.border_width_top = 4
	style.border_color = Color("#3fa34d")
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
		_style_button(button, Color("#e0a92c"))
		button.pressed.connect(func() -> void:
			if GameState.buy_upgrade(id):
				Audio.play("buy", -2.0)
				if player:
					Fx.burst(player, player.global_position + Vector3(0, 1.2, 0), [Color("#ffd84a"), Color("#8fe07a"), Color("#6bc4ff")], 24, 5.0, 0.09, 1.0))
		row.add_child(button)
		_rows[id] = {"name": name_label, "button": button}

	var roles_title := Label.new()
	roles_title.text = "伐採員の役割（タップで切り替え）"
	roles_title.add_theme_font_size_override("font_size", 26)
	vbox.add_child(roles_title)
	_roles_box = HFlowContainer.new()
	_roles_box.add_theme_constant_override("h_separation", 10)
	_roles_box.add_theme_constant_override("v_separation", 10)
	vbox.add_child(_roles_box)

	var close := Button.new()
	close.text = "閉じる"
	close.custom_minimum_size = Vector2(0, 80)
	close.pressed.connect(func() -> void:
		Audio.play("ui", -4.0)
		_panel.visible = false)
	vbox.add_child(close)


func _refresh() -> void:
	if GameState.money > _shown_money and _money_label.is_inside_tree():
		var chip := _money_label.get_parent() as Control
		chip.pivot_offset = chip.size * 0.5
		var tw := chip.create_tween()
		tw.tween_property(chip, "scale", Vector2.ONE * 1.12, 0.06)
		tw.tween_property(chip, "scale", Vector2.ONE, 0.12)
	_shown_money = GameState.money
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


func _rebuild_roles() -> void:
	if _roles_box == null:
		return
	for child in _roles_box.get_children():
		child.queue_free()
	var count := roundi(GameState.value("lumberjack"))
	_roles_box.get_parent().get_child(_roles_box.get_index() - 1).visible = count > 0
	for i in count:
		var role := GameState.lumberjack_role(i)
		var button := Button.new()
		button.custom_minimum_size = Vector2(190, 64)
		button.text = "%d: %s" % [i + 1, "伐採" if role == "chop" else "運搬"]
		button.modulate = Color("#9fe0a8") if role == "chop" else Color("#9fc4ff")
		var idx := i
		button.pressed.connect(func() -> void:
			Audio.play("ui", -4.0)
			GameState.set_lumberjack_role(idx, "haul" if GameState.lumberjack_role(idx) == "chop" else "chop"))
		_roles_box.add_child(button)
