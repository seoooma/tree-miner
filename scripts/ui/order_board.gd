class_name OrderBoard
extends VBoxContainer
## 画面左上（設定ボタンの下）の注文の一覧と評判。タッチは受け取らない（下のスティックに通す）。
## 1件ごとに「品物・そろった数のゲージ・残り時間・割増・もらえる評判」を出す。達成すると画面中央に知らせる。

const WIDTH := 300.0

var _rep_label: Label
var _list: VBoxContainer
## 注文1件ごとの表示 {bar, count, info}（GameState.orders と同じ並び）
var _rows: Array = []
var _shown_signature := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 8)
	custom_minimum_size.x = WIDTH

	var head := PanelContainer.new()
	var hs := UiKit.flat_box(Color(0.08, 0.08, 0.08, 0.72), 16)
	hs.content_margin_left = 14
	hs.content_margin_right = 14
	hs.content_margin_top = 4
	hs.content_margin_bottom = 4
	head.add_theme_stylebox_override("panel", hs)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(head)
	var head_row := HBoxContainer.new()
	head_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(head_row)
	var title := UiKit.label("注文", 26, false, UiKit.WHITE, 8)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(title)
	_rep_label = UiKit.label("", 26, false, UiKit.NEXT_YELLOW, 8, UiKit.NEXT_OUTLINE)
	head_row.add_child(_rep_label)

	_list = VBoxContainer.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_theme_constant_override("separation", 6)
	add_child(_list)

	Orders.orders_changed.connect(_rebuild)
	Orders.order_completed.connect(_on_completed)
	GameState.reputation_changed.connect(func(_r: int) -> void: _update_rep())
	_rebuild()
	_update_rep()


func _update_rep() -> void:
	_rep_label.text = "★ 評判 %d" % GameState.reputation


## 注文の顔ぶれ（木・種類・本数）。変わったときだけ作り直す
func _signature() -> String:
	var parts: Array[String] = []
	for o in GameState.orders:
		parts.append("%s:%s:%d" % [o["tree"], o["kind"], int(o["need"])])
	return ",".join(parts)


func _rebuild() -> void:
	var sig := _signature()
	if sig != _shown_signature:
		_shown_signature = sig
		for child in _list.get_children():
			child.queue_free()
		_rows.clear()
		for o in GameState.orders:
			_rows.append(_make_row(o))
	_update_rows()


func _make_row(o: Dictionary) -> Dictionary:
	var grade_color := Color(str(GameData.tree_def(str(o["tree"])).get("grade_color", "#ffffff")))
	var panel := PanelContainer.new()
	var ps := UiKit.flat_box(Color(0.08, 0.08, 0.08, 0.72), 16, 3, grade_color.darkened(0.15))
	ps.content_margin_left = 12
	ps.content_margin_right = 12
	ps.content_margin_top = 6
	ps.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", ps)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)
	var icon := TextureRect.new()
	icon.texture = UiKit.icon({"log": "icon_log", "plank": "icon_tree", "goods": "icon_home"}.get(str(o["kind"]), "icon_tree"))
	icon.custom_minimum_size = Vector2(30, 30)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(icon)
	var name_label := UiKit.label(Orders.item_name(str(o["kind"]), str(o["tree"])), 24, false, UiKit.WHITE, 8)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	var count := UiKit.label("", 24, false, UiKit.WHITE, 8)
	top.add_child(count)

	var bar := UiKit.Bar.new(grade_color, Vector2(WIDTH - 24, 16))
	bar.radius = 6
	box.add_child(bar)
	var info := UiKit.label("", 19, false, Color("#e8e2d6"), 6)
	box.add_child(info)
	return {"bar": bar, "count": count, "info": info}


func _update_rows() -> void:
	for i in mini(_rows.size(), GameState.orders.size()):
		var o: Dictionary = GameState.orders[i]
		var row: Dictionary = _rows[i]
		var need := int(o["need"])
		var done := int(o["done"])
		(row["bar"] as UiKit.Bar).fill = float(done) / float(maxi(1, need))
		(row["count"] as Label).text = "%d/%d" % [done, need]
		var left := maxi(0, ceili(float(o["time_left"])))
		var info := row["info"] as Label
		info.text = "残り %d:%02d ・ 代金x%.1f ・ 評判+%d" % [left / 60, left % 60, float(o["mult"]), int(o["rep"])]
		info.add_theme_color_override("font_color", Color("#ff8a7a") if left <= 30 else Color("#e8e2d6"))


func _process(_delta: float) -> void:
	_update_rows()


## 達成したとき、画面の中央に「注文達成」を出す
func _on_completed(o: Dictionary) -> void:
	Audio.play("unlock", -6.0)
	var root := get_parent() as Control
	if root == null:
		return
	var l := UiKit.label("注文達成！ 評判 +%d" % int(o["rep"]), 46, false, UiKit.NEXT_YELLOW, 12, UiKit.NEXT_OUTLINE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(l)
	l.size = Vector2(root.size.x, 70)
	l.position = Vector2(0, root.size.y * 0.28)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", root.size.y * 0.28 - 50.0, 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.5).set_delay(1.1)
	tw.tween_callback(l.queue_free)
