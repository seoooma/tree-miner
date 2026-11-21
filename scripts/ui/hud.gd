class_name Hud
extends CanvasLayer
## 画面UI。
## - 左上: 設定（ギア）。BGM / 効果音のオン・オフはここから開く
## - 右上: 所持金のピル
## - 下: 乗る／降りる・強化のタイルボタン
## - 強化画面: 下からせり上がるシート（カード・サムネイル・おすすめ・伐採員の役割チップ）
## - ワールド表示: プレイヤー頭上の積荷バー、機械の燃料・積荷バー、案内先が画面外のときの端のインジケーター
## 表示だけを担当し、ゲームの数値や処理は GameState / 各ノードが持つ。

const SHEET_RATIO := 0.65
const STAT_NAMES := {
	"axe_power": "伐採力",
	"capacity": "積載量",
	"move_speed": "移動速度",
	"sawmill": "加工速度",
	"lumberjack": "人数",
	"lumberjack_capacity": "積載量",
	"river": "流れの速さ",
	"dock": "積み込む速さ",
	"plank_belt": "運ぶ速さ",
	"conveyor": "運ぶ速さ",
	"harvester": "伐採力",
	"hauler": "積載量",
}
## 左上のバッジ: speed（緑 ⏩）/ power（赤 ↑）/ capacity（黄）
const BADGES := {
	"axe_power": "badge_power",
	"capacity": "badge_capacity",
	"move_speed": "badge_speed",
	"sawmill": "badge_speed",
	"lumberjack": "badge_capacity",
	"lumberjack_capacity": "badge_capacity",
	"river": "badge_speed",
	"dock": "badge_speed",
	"plank_belt": "badge_speed",
	"conveyor": "badge_speed",
	"harvester": "badge_power",
	"hauler": "badge_capacity",
}

var player: Player
var guide: GuideArrows

var _root: Control
var _money_label: Label
var _money_pill: Control
var _board_button: Button
var _discard_button: Button
var _upgrade_button: Button
var _gear: TextureButton
var _settings: Control
var _music_button: Button
var _sfx_button: Button
var _dim: ColorRect
var _sheet: Control
var _sheet_open := false
var _sheet_tween: Tween
var _roles_box: HFlowContainer
var _roles_title: Label
var _rows: Dictionary = {}
var _shown_money := 0
var _thumbs: Thumbnails
var _scroll: ScrollContainer
# 強化シートを指でなぞってスクロールする（ボタンの上から始めても動く）
var _drag_id := -99
var _drag_start_y := 0.0
var _drag_start_scroll := 0.0
var _drag_moved := false
var _drag_last_y := 0.0
var _drag_velocity := 0.0
var _fling := 0.0
var _suppress_tap_until := 0

# ワールド表示
var _carry_root: Control
var _carry_bar: UiKit.Bar
var _carry_text: Label
var _carry_count := 0
var _machine_bars: Dictionary = {}  # Machine -> {root, fuel, cargo, warn}
var _edge: Control
var _edge_icon: TextureRect
var _edge_text: Label
var _edge_arrow: TextureRect


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _make_theme()
	add_child(_root)
	_thumbs = Thumbnails.new()
	add_child(_thumbs)

	# スティックは一番下に置き、ボタン類がタッチを優先して受け取れるようにする
	var joystick := VirtualJoystick.new()
	_root.add_child(joystick)
	joystick.vector_changed.connect(func(v: Vector2) -> void:
		if player:
			player.joystick_vector = v)

	_build_world_overlay()
	_build_top_bar()
	_build_bottom_tiles()
	_build_settings()
	_build_sheet()
	joystick.is_blocked = _is_over_ui

	GameState.money_changed.connect(func(_m: int) -> void: _refresh())
	GameState.machine_changed.connect(func(_k: String, _r: int) -> void: _refresh())
	GameState.upgrade_changed.connect(func(_id: String, _l: int) -> void:
		_refresh()
		_rebuild_roles())
	GameState.lumberjack_role_changed.connect(func(_i: int, _r: String) -> void: _rebuild_roles())
	_refresh()
	_rebuild_roles()


func bind_player(p: Player) -> void:
	player = p
	player.carry_changed.connect(_on_carry_changed)


# ================================================================ 上部

func _build_top_bar() -> void:
	_gear = UiKit.icon_button("icon_gear", 88)
	_gear.position = Vector2(20, 20)
	_gear.pressed.connect(func() -> void:
		Audio.play("ui", -4.0)
		_settings.visible = not _settings.visible)
	_root.add_child(_gear)

	# 通貨ピル（暗い角丸＋左にアイコン、右に数字）
	var pill := PanelContainer.new()
	var style := UiKit.flat_box(Color(0.08, 0.08, 0.08, 0.75), 22)
	style.content_margin_left = 10
	style.content_margin_right = 22
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	pill.add_theme_stylebox_override("panel", style)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pill.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pill.offset_right = -20
	pill.offset_top = 30
	pill.custom_minimum_size = Vector2(220, 68)
	_root.add_child(pill)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(row)
	var ic := TextureRect.new()
	ic.texture = UiKit.icon("icon_money")
	ic.custom_minimum_size = Vector2(58, 58)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ic)
	_money_label = UiKit.label("¥0", 38, true)
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_money_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_money_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_money_label)
	_money_pill = pill


func _build_settings() -> void:
	# ギアの下に開く小さなメニュー（BGM / 効果音）
	var panel := PanelContainer.new()
	var style := UiKit.flat_box(Color(0.12, 0.12, 0.13, 0.94), 20, 3, Color(1, 1, 1, 0.25))
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	panel.position = Vector2(20, 122)
	panel.visible = false
	_root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(UiKit.label("設定", 30, true))
	_music_button = _toggle_button(box, func() -> void:
		Audio.toggle_music()
		_update_sound_buttons())
	_sfx_button = _toggle_button(box, func() -> void:
		Audio.toggle_sfx()
		_update_sound_buttons())
	_settings = panel
	_update_sound_buttons()


func _toggle_button(parent: Control, on_press: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(230, 84)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", UiKit.font())
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_constant_override("outline_size", 8)
	b.add_theme_color_override("font_outline_color", UiKit.OUTLINE_DARK)
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


func _update_sound_buttons() -> void:
	_music_button.text = "♪ BGM ON" if Audio.music_enabled else "♪ BGM OFF"
	_sfx_button.text = "SE ON" if Audio.sfx_enabled else "SE OFF"
	UiKit.skin_button(_music_button, "btn_green" if Audio.music_enabled else "btn_gray", "", 18, 12)
	UiKit.skin_button(_sfx_button, "btn_green" if Audio.sfx_enabled else "btn_gray", "", 18, 12)


# ================================================================ 下部のタイルボタン

func _build_bottom_tiles() -> void:
	_board_button = UiKit.tile_button("icon_truck", "乗る", Vector2(140, 140), Color("#3b8fe0"))
	_board_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_board_button.offset_left = 24
	_board_button.offset_top = -164
	_board_button.offset_right = 164
	_board_button.offset_bottom = -24
	_board_button.visible = false
	_board_button.pressed.connect(_toggle_board)
	_root.add_child(_board_button)

	# 燃料缶を捨てる（徒歩で缶を持っているときだけ出る）
	_discard_button = UiKit.tile_button("icon_fuel", "缶を捨てる", Vector2(140, 140), Color("#e8573a"))
	_discard_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_discard_button.offset_left = 24
	_discard_button.offset_top = -324
	_discard_button.offset_right = 164
	_discard_button.offset_bottom = -184
	_discard_button.visible = false
	_discard_button.pressed.connect(func() -> void:
		if player:
			player.discard_fuel())
	_root.add_child(_discard_button)

	_upgrade_button = UiKit.tile_button("icon_upgrade", "強化")
	_upgrade_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_upgrade_button.offset_left = -164
	_upgrade_button.offset_top = -164
	_upgrade_button.offset_right = -24
	_upgrade_button.offset_bottom = -24
	_upgrade_button.pressed.connect(func() -> void:
		Audio.play("ui", -4.0)
		_set_sheet(not _sheet_open))
	_root.add_child(_upgrade_button)


func _process(delta: float) -> void:
	_update_fling(delta)
	if player == null:
		return
	if player.vehicle:
		_board_button.visible = true
		UiKit.set_tile_text(_board_button, "降りる")
	else:
		_board_button.visible = player.nearby_machine() != null
		UiKit.set_tile_text(_board_button, "乗る")
	_discard_button.visible = player.vehicle == null and player.stack.count(Machine.FUEL_KIND) > 0
	_update_world_overlay()


# ---- 強化シートのドラッグスクロール ----

func _input(event: InputEvent) -> void:
	if not _sheet_open or _scroll == null:
		return
	var pressed := false
	var released := false
	var moved := false
	var id := -99
	var pos := Vector2.ZERO
	if event is InputEventScreenTouch:
		id = event.index
		pos = event.position
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventScreenDrag:
		id = event.index
		pos = event.position
		moved = true
	elif event is InputEventMouseButton and event.device != -1 and event.button_index == MOUSE_BUTTON_LEFT:
		id = -2
		pos = event.position
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventMouseMotion and event.device != -1 and _drag_id == -2:
		id = -2
		pos = event.position
		moved = true
	else:
		return
	if pressed and _drag_id == -99 and _scroll.get_global_rect().has_point(pos):
		_drag_id = id
		_drag_start_y = pos.y
		_drag_last_y = pos.y
		_drag_start_scroll = _scroll.scroll_vertical
		_drag_moved = false
		_drag_velocity = 0.0
		_fling = 0.0
	elif moved and id == _drag_id:
		if absf(pos.y - _drag_start_y) > 14.0:
			_drag_moved = true
		if _drag_moved:
			_scroll.scroll_vertical = int(_drag_start_scroll - (pos.y - _drag_start_y))
			_drag_velocity = lerpf(_drag_velocity, (_drag_last_y - pos.y) * 60.0, 0.5)
		_drag_last_y = pos.y
	elif released and id == _drag_id:
		_drag_id = -99
		if _drag_moved:
			# なぞった直後の指離れで、ボタンが押されたことにならないようにする
			_suppress_tap_until = Time.get_ticks_msec() + 150
			_fling = _drag_velocity


func _update_fling(delta: float) -> void:
	if absf(_fling) < 20.0 or _scroll == null:
		_fling = 0.0
		return
	_scroll.scroll_vertical += int(_fling * delta)
	_fling = move_toward(_fling, 0.0, 2600.0 * delta)


func _tap_suppressed() -> bool:
	return _drag_moved and Time.get_ticks_msec() < _suppress_tap_until or _drag_id != -99 and _drag_moved


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


## スティックを出さない場所（ボタン・開いているシートやメニューの上）
func _is_over_ui(pos: Vector2) -> bool:
	if _sheet_open:
		return true
	for c in [_upgrade_button, _board_button, _discard_button, _gear, _settings]:
		var ctl := c as Control
		if ctl.visible and ctl.get_global_rect().has_point(pos):
			return true
	return false


func _make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = UiKit.font()
	theme.default_font_size = 30
	theme.set_color("font_outline_color", "Label", UiKit.OUTLINE_DARK)
	theme.set_constant("outline_size", "Label", 8)
	theme.set_color("font_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", Color.WHITE)
	return theme


# ================================================================ 強化シート

func _build_sheet() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.5)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	_dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_set_sheet(false))
	_root.add_child(_dim)

	_sheet = Control.new()
	_sheet.anchor_left = 0.0
	_sheet.anchor_right = 1.0
	_sheet.anchor_top = 1.0
	_sheet.anchor_bottom = 1.0
	_sheet.visible = false
	_root.add_child(_sheet)

	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style := UiKit.flat_box(Color("#3b3e42"), 0)
	bg.add_theme_stylebox_override("panel", bg_style)
	_sheet.add_child(bg)

	# 見出しの帯（黄〜オレンジのグラデーション、傷のある金属っぽい質感）
	var header := Panel.new()
	header.add_theme_stylebox_override("panel", UiKit.tex_box("header_bar", 14, 0))
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.offset_bottom = 112
	header.offset_top = -8
	_sheet.add_child(header)
	var bolt := Panel.new()
	bolt.add_theme_stylebox_override("panel", UiKit.flat_box(Color("#3a3a3a"), 14, 4, Color("#9a9a9a")))
	bolt.position = Vector2(30, 46)
	bolt.size = Vector2(28, 28)
	header.add_child(bolt)
	var title := UiKit.label("強化", 52, true, Color.WHITE, 14)
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title)
	var close := UiKit.icon_button("icon_close", 92)
	close.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	close.offset_left = -112
	close.offset_right = -20
	close.offset_top = -46
	close.offset_bottom = 46
	close.pressed.connect(func() -> void:
		Audio.play("ui", -4.0)
		_set_sheet(false))
	header.add_child(close)

	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 124
	scroll.offset_left = 4
	scroll.offset_right = -12
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sheet.add_child(scroll)
	# 左にバッジがはみ出す分の余白
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 8)
	scroll.add_child(margin)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 26)
	margin.add_child(list)
	var top_pad := Control.new()
	top_pad.custom_minimum_size = Vector2(0, 4)
	list.add_child(top_pad)

	for def in GameData.upgrades:
		_build_card(list, def)
	# 機械（伐採機・運搬車）もほかの強化と同じカードで買う。Lv = ランク
	for kind in GameData.machines:
		if str(kind).begins_with("_"):
			continue
		var m: Dictionary = GameData.machines[kind]
		_build_card(list, {"id": kind, "name": m.get("name", kind), "desc": m.get("desc", "")})

	_roles_title = UiKit.label("伐採員の役割（タップで切り替え）", 26)
	list.add_child(_roles_title)
	_roles_box = HFlowContainer.new()
	_roles_box.add_theme_constant_override("h_separation", 12)
	_roles_box.add_theme_constant_override("v_separation", 12)
	list.add_child(_roles_box)
	var bottom_pad := Control.new()
	bottom_pad.custom_minimum_size = Vector2(0, 30)
	list.add_child(bottom_pad)


func _build_card(list: Control, def: Dictionary) -> void:
	var id := str(def["id"])
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.tex_box("card_metal", 14, 10))
	card.custom_minimum_size = Vector2(0, 176)
	list.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)

	# 左: サムネイル（暗めの画像パネル）と、角に重なる丸いバッジ
	var img_panel := PanelContainer.new()
	img_panel.add_theme_stylebox_override("panel", UiKit.flat_box(Color("#9fa2a6"), 8))
	img_panel.custom_minimum_size = Vector2(150, 150)
	row.add_child(img_panel)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(150, 150)
	img_panel.add_child(holder)
	var thumb := TextureRect.new()
	thumb.texture = _thumbs.texture_for(id)
	thumb.set_anchors_preset(Control.PRESET_FULL_RECT)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	holder.add_child(thumb)
	var badge := TextureRect.new()
	badge.texture = UiKit.icon(BADGES.get(id, "badge_capacity"))
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.size = Vector2(56, 56)
	badge.position = Vector2(-30, -30)
	holder.add_child(badge)

	# 中: 名前・ステータス名・Lv と値（現在 → 次）・説明
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.custom_minimum_size = Vector2(10, 0)
	info.add_theme_constant_override("separation", 0)
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(info)
	var name_label := UiKit.label(str(def.get("name", id)), 30, false, Color("#1f1f1f"), 0, UiKit.OUTLINE_DARK, false)
	name_label.clip_text = true
	name_label.custom_minimum_size = Vector2(10, 0)
	info.add_child(name_label)
	var stat := UiKit.label(STAT_NAMES.get(id, ""), 22, false, Color("#7a7a7a"), 0, UiKit.OUTLINE_DARK, false)
	info.add_child(stat)
	# 「Lv.5 ▶ Lv.6」「6 ▶ 7」の2行。現在の値は濃い色、次の値は黄色＋縁取り
	var cells := []
	for r in 2:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.add_child(line)
		var cur := UiKit.label("", 23, true, Color("#222222"), 0, UiKit.OUTLINE_DARK, false)
		cur.custom_minimum_size = Vector2(112, 0)
		cur.clip_text = true
		line.add_child(cur)
		var arrow := UiKit.label("▶", 18, false, Color("#333333"), 0, UiKit.OUTLINE_DARK, false)
		line.add_child(arrow)
		var nxt := UiKit.label("", 23, true, UiKit.NEXT_YELLOW, 9, UiKit.NEXT_OUTLINE, false)
		nxt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nxt.custom_minimum_size = Vector2(10, 0)
		nxt.clip_text = true
		line.add_child(nxt)
		cells.append_array([cur, arrow, nxt])
	var desc := UiKit.label(str(def.get("desc", "")), 18, false, Color("#6e6e6e"), 0, UiKit.OUTLINE_DARK, false)
	desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	desc.clip_text = true
	desc.custom_minimum_size = Vector2(10, 0)
	info.add_child(desc)

	# 右: 価格ボタン（買えるなら緑、買えないなら灰色で価格が赤）
	var price_col := VBoxContainer.new()
	price_col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(price_col)
	var button := Button.new()
	button.custom_minimum_size = Vector2(196, 96)
	button.focus_mode = Control.FOCUS_NONE
	button.icon = UiKit.icon("icon_money")
	button.expand_icon = false
	button.add_theme_constant_override("icon_max_width", 52)
	button.add_theme_constant_override("h_separation", 8)
	button.add_theme_font_override("font", UiKit.font(true))
	button.add_theme_font_size_override("font_size", 34)
	button.add_theme_constant_override("outline_size", 10)
	button.pressed.connect(func() -> void:
		if _tap_suppressed():
			return
		var bought := GameState.buy_machine(id) if GameData.machines.has(id) else GameState.buy_upgrade(id)
		if bought:
			Audio.play("buy", -2.0)
			if player:
				Fx.burst(player, player.global_position + Vector3(0, 1.2, 0), [Color("#ffd84a"), Color("#8fe07a"), Color("#6bc4ff")], 24, 5.0, 0.09, 1.0))
	price_col.add_child(button)
	# おすすめのリボン（ボタンの上に重ねる）
	var ribbon := Label.new()
	ribbon.text = "おすすめ"
	UiKit.style_label(ribbon, 20, false, Color.WHITE, 6, Color("#6a0d0a"), false)
	var rs := UiKit.flat_box(Color("#E03A30"), 4)
	rs.corner_radius_bottom_left = 14
	rs.content_margin_left = 14
	rs.content_margin_right = 10
	ribbon.add_theme_stylebox_override("normal", rs)
	ribbon.position = Vector2(64, -40)
	ribbon.visible = false
	button.add_child(ribbon)

	_rows[id] = {"cells": cells, "button": button, "ribbon": ribbon}


func _set_sheet(open: bool) -> void:
	if open == _sheet_open:
		return
	_sheet_open = open
	_settings.visible = false
	if _sheet_tween:
		_sheet_tween.kill()
	var h := _root.get_viewport_rect().size.y * SHEET_RATIO
	_sheet_tween = create_tween().set_parallel()
	if open:
		_refresh()
		_dim.visible = true
		_sheet.visible = true
		_dim.modulate.a = 0.0
		_sheet.offset_top = 0
		_sheet.offset_bottom = h
		_sheet_tween.tween_property(_dim, "modulate:a", 1.0, 0.18)
		_sheet_tween.tween_property(_sheet, "offset_top", -h, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_sheet_tween.tween_property(_sheet, "offset_bottom", 0.0, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		_sheet_tween.tween_property(_dim, "modulate:a", 0.0, 0.16)
		_sheet_tween.tween_property(_sheet, "offset_top", 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_sheet_tween.tween_property(_sheet, "offset_bottom", h, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_sheet_tween.chain().tween_callback(func() -> void:
			_dim.visible = false
			_sheet.visible = false)


func _refresh() -> void:
	if GameState.money > _shown_money and _money_pill.is_inside_tree():
		_money_pill.pivot_offset = _money_pill.size * 0.5
		var tw := _money_pill.create_tween()
		tw.tween_property(_money_pill, "scale", Vector2.ONE * 1.1, 0.06)
		tw.tween_property(_money_pill, "scale", Vector2.ONE, 0.12)
	_shown_money = GameState.money
	_money_label.text = "¥%d" % GameState.money

	var best_id := _recommended()
	for id in _rows:
		var row: Dictionary = _rows[id]
		var is_machine := GameData.machines.has(id)
		var lv := GameState.machine_rank(id) if is_machine else GameState.level(id)
		var cells: Array = row["cells"]
		var button: Button = row["button"]
		(cells[0] as Label).text = "Lv.%d" % lv
		(cells[3] as Label).text = _format_value(id, lv)
		button.add_theme_font_size_override("font_size", 34)
		button.add_theme_font_override("font", UiKit.font(true))
		if not is_machine and not GameState.is_available(id):
			# 先に開放が必要な強化がある（例: 集積所コンベアは川流しのあと）
			(cells[1] as Label).visible = false
			(cells[2] as Label).text = ""
			(cells[4] as Label).visible = false
			(cells[5] as Label).text = ""
			var req := str(GameData.upgrade_def(id).get("requires", ""))
			button.text = "%sが先" % str(GameData.upgrade_def(req).get("name", req))
			button.icon = null
			button.disabled = true
			# 見出し用フォントは数字と一部の文字しか入っていないので、本文用のフォントで出す
			button.add_theme_font_override("font", UiKit.font(false))
			button.add_theme_font_size_override("font_size", 24)
			UiKit.skin_button(button, "btn_gray", "", 18, 10)
			_price_color(button, Color.WHITE, Color("#555555"))
		elif _card_maxed(id):
			(cells[1] as Label).visible = false
			(cells[2] as Label).text = ""
			(cells[4] as Label).visible = false
			(cells[5] as Label).text = ""
			button.text = "MAX"
			button.icon = null
			button.disabled = true
			UiKit.skin_button(button, "btn_gray", "", 18, 10)
			_price_color(button, Color.WHITE, Color("#555555"))
		else:
			(cells[1] as Label).visible = true
			(cells[4] as Label).visible = true
			(cells[2] as Label).text = "Lv.%d" % (lv + 1)
			(cells[5] as Label).text = _format_value(id, lv + 1)
			var cost := _card_cost(id)
			var affordable := GameState.money >= cost
			button.text = "%d" % cost
			button.icon = UiKit.icon("icon_money")
			button.disabled = false
			if affordable:
				UiKit.skin_button(button, "btn_green", "btn_green_pressed", 18, 10)
				_price_color(button, Color.WHITE, Color("#1d4a12"))
			else:
				UiKit.skin_button(button, "btn_gray", "", 18, 10)
				_price_color(button, UiKit.PRICE_RED, Color(1, 1, 1, 0.9))
		(row["ribbon"] as Label).visible = id == best_id


static func _price_color(b: Button, color: Color, outline: Color) -> void:
	for key in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color", "font_disabled_color", "font_focus_color"]:
		b.add_theme_color_override(key, color)
	b.add_theme_color_override("font_outline_color", outline)


## カードの値の表示（強化と機械で共通の形）
static func _format_value(id: String, lv: int) -> String:
	if GameData.machines.has(id):
		return GameData.format_machine_value(id, lv)
	return GameData.format_upgrade_value(id, lv)


static func _card_maxed(id: String) -> bool:
	return GameState.machine_is_maxed(id) if GameData.machines.has(id) else GameState.is_maxed(id)


static func _card_cost(id: String) -> int:
	return GameState.machine_next_cost(id) if GameData.machines.has(id) else GameState.next_cost(id)


## 「おすすめ」: 今買える強化（機械を含む）のうち、値段あたりの伸び（相対的な上がり幅）がいちばん大きいもの。表示だけ。
func _recommended() -> String:
	var best := ""
	var best_score := 0.0
	for id in _rows:
		var is_machine := GameData.machines.has(id)
		if _card_maxed(id) or (not is_machine and not GameState.is_available(id)):
			continue
		var cost := _card_cost(id)
		if cost <= 0 or GameState.money < cost:
			continue
		var lv := GameState.machine_rank(id) if is_machine else GameState.level(id)
		var now := GameData.machine_stat(id, lv) if is_machine else GameData.upgrade_value(id, lv)
		var next := GameData.machine_stat(id, lv + 1) if is_machine else GameData.upgrade_value(id, lv + 1)
		var gain := (next - now) / maxf(absf(now), absf(next - now))
		if lv == 0 and (is_machine or GameData.upgrade_def(id).get("locked_at_zero", false)):
			gain = 1.0
		var score := gain / float(cost)
		if score > best_score:
			best_score = score
			best = id
	return best


func _rebuild_roles() -> void:
	if _roles_box == null:
		return
	for child in _roles_box.get_children():
		child.queue_free()
	var count := roundi(GameState.value("lumberjack"))
	_roles_title.visible = count > 0
	for i in count:
		var role := GameState.lumberjack_role(i)
		var chip := Button.new()
		chip.custom_minimum_size = Vector2(150, 84)
		chip.focus_mode = Control.FOCUS_NONE
		chip.text = "%d: %s" % [i + 1, "伐採" if role == "chop" else "運搬"]
		var color := Color("#4e9e34") if role == "chop" else Color("#3a6fc8")
		var normal := UiKit.flat_box(color, 42, 3, color.lightened(0.35))
		normal.border_width_bottom = 7
		normal.border_color = color.darkened(0.35)
		normal.content_margin_left = 18
		normal.content_margin_right = 18
		var pressed := normal.duplicate() as StyleBoxFlat
		pressed.border_width_bottom = 2
		pressed.content_margin_top = 6
		chip.add_theme_stylebox_override("normal", normal)
		chip.add_theme_stylebox_override("hover", normal)
		chip.add_theme_stylebox_override("pressed", pressed)
		chip.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		chip.add_theme_constant_override("outline_size", 8)
		chip.add_theme_color_override("font_outline_color", UiKit.OUTLINE_DARK)
		chip.add_theme_font_size_override("font_size", 28)
		var idx := i
		chip.pressed.connect(func() -> void:
			if _tap_suppressed():
				return
			Audio.play("ui", -4.0)
			GameState.set_lumberjack_role(idx, "haul" if GameState.lumberjack_role(idx) == "chop" else "chop"))
		_roles_box.add_child(chip)


# ================================================================ ワールド表示（頭上のバー・画面端の案内）

func _build_world_overlay() -> void:
	# プレイヤー頭上の積荷バー「積荷 (5/19)」。満杯で赤くなり「最大」
	_carry_root = Control.new()
	_carry_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_carry_root.size = Vector2(160, 28)
	_root.add_child(_carry_root)
	_carry_bar = UiKit.Bar.new(Color("#F2C230"), Vector2(160, 28))
	_carry_root.add_child(_carry_bar)
	_carry_text = UiKit.label("", 19, false, Color.WHITE, 7)
	_carry_text.position = Vector2.ZERO
	_carry_text.size = Vector2(160, 28)
	_carry_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_carry_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_carry_root.add_child(_carry_text)

	# 案内先が画面外のときの端のインジケーター（アイコン・距離・矢印）
	_edge = Control.new()
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge.size = Vector2(110, 130)
	_edge.visible = false
	_root.add_child(_edge)
	_edge_icon = TextureRect.new()
	_edge_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_edge_icon.size = Vector2(58, 58)
	_edge_icon.position = Vector2(26, 0)
	_edge.add_child(_edge_icon)
	_edge_text = UiKit.label("", 26, true, Color.WHITE, 8)
	_edge_text.size = Vector2(110, 34)
	_edge_text.position = Vector2(0, 56)
	_edge_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_edge.add_child(_edge_text)
	_edge_arrow = TextureRect.new()
	_edge_arrow.texture = UiKit.icon("icon_arrow")
	_edge_arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_edge_arrow.size = Vector2(44, 44)
	_edge_arrow.pivot_offset = Vector2(22, 22)
	_edge_arrow.position = Vector2(33, 92)
	_edge.add_child(_edge_arrow)


func _on_carry_changed(count: int, cap: int) -> void:
	_carry_count = count
	_carry_bar.fill = float(count) / maxf(1.0, float(cap))
	var full := count >= cap
	_carry_bar.color = Color("#E04040") if full else Color("#F2C230")
	_carry_text.text = "最大" if full else "積荷 (%d/%d)" % [count, cap]


func _update_world_overlay() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# 積荷バー
	var head := player.global_position + Vector3(0, 2.35, 0)
	# 何も持っていないときは出さない（地面の受け渡し場所の文字と重ならないように）
	_carry_root.visible = player.vehicle == null and _carry_count > 0 and not cam.is_position_behind(head)
	if _carry_root.visible:
		_carry_root.position = (cam.unproject_position(head) - Vector2(_carry_root.size.x * 0.5, 0)).round()

	# 機械の燃料（オレンジ）・積荷（黄色）のバー
	for node in get_tree().get_nodes_in_group("machines"):
		var m := node as Machine
		if not _machine_bars.has(m):
			_machine_bars[m] = _make_machine_bars(m)
		var bars: Dictionary = _machine_bars[m]
		var top := m.global_position + Vector3(0, 2.2, 0)
		var root: Control = bars["root"]
		root.visible = not cam.is_position_behind(top)
		root.position = (cam.unproject_position(top) - Vector2(root.size.x * 0.5, root.size.y)).round()
		(bars["fuel"] as UiKit.Bar).fill = m.fuel / maxf(1.0, m.fuel_max())
		(bars["warn"] as Label).visible = m.fuel <= 0.0
		if m.stack:
			(bars["cargo"] as UiKit.Bar).fill = float(m.stack.size()) / maxf(1.0, float(m.stack.capacity()))
	for m in _machine_bars.keys():
		if not is_instance_valid(m):
			(_machine_bars[m]["root"] as Control).queue_free()
			_machine_bars.erase(m)

	_update_edge_indicator(cam)


func _make_machine_bars(m: Machine) -> Dictionary:
	var root := VBoxContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override("separation", 4)
	_root.add_child(root)
	_root.move_child(root, _carry_root.get_index())
	var warn := UiKit.label("燃料切れ", 22, false, Color("#ff8a7a"), 8)
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(warn)
	var fuel := _mini_bar(root, "燃料", Color("#F08A2C"))
	var cargo: UiKit.Bar = null
	if m.stack:
		cargo = _mini_bar(root, "積荷", Color("#F2C230"))
	root.size = Vector2(190, 0)
	root.reset_size()
	return {"root": root, "fuel": fuel, "cargo": cargo, "warn": warn}


func _mini_bar(parent: Control, text: String, color: Color) -> UiKit.Bar:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var l := UiKit.label(text, 18, false, Color.WHITE, 6)
	l.custom_minimum_size = Vector2(44, 0)
	row.add_child(l)
	var bar := UiKit.Bar.new(color, Vector2(140, 18))
	bar.radius = 6
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	return bar


func _update_edge_indicator(cam: Camera3D) -> void:
	if guide == null or guide.goal == Vector3.INF or player.vehicle != null:
		_edge.visible = false
		return
	var goal := guide.goal + Vector3(0, 0.5, 0)
	var view := _root.get_viewport_rect().size
	var margin := Vector2(70, 150)
	var screen := cam.unproject_position(goal)
	var behind := cam.is_position_behind(goal)
	var inside := Rect2(margin, view - margin * 2.0).has_point(screen)
	if inside and not behind:
		_edge.visible = false
		return
	_edge.visible = true
	_edge_icon.texture = UiKit.icon("icon_home" if guide.goal_kind == "home" else "icon_tree")
	_edge_text.text = "%dm" % roundi(Fx.xz_distance(guide.goal, player.global_position))
	# プレイヤーの画面位置から案内先へ向かう方向で、画面の端に貼り付ける
	var center := cam.unproject_position(player.global_position + Vector3(0, 1, 0))
	var dir := (screen - center)
	if behind:
		dir = -dir
	if dir.length() < 1.0:
		dir = Vector2.UP
	dir = dir.normalized()
	var half := view * 0.5 - margin
	var t := INF
	if absf(dir.x) > 0.001:
		t = minf(t, half.x / absf(dir.x))
	if absf(dir.y) > 0.001:
		t = minf(t, half.y / absf(dir.y))
	var pos := view * 0.5 + dir * t
	_edge.position = (pos - _edge.size * 0.5).round()
	_edge_arrow.rotation = dir.angle()
