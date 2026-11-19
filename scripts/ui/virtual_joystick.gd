class_name VirtualJoystick
extends Control
## 画面のどこを触ってもその位置を中心に出るフローティング型スティック。
## スマホ（ブラウザ含む）はタッチイベント、PC はマウスドラッグで動く。
## ボタンやパネルの上で始まったタッチは無視する（is_blocked で判定）。

signal vector_changed(value: Vector2)

## タッチ位置が UI の上かどうかを返す関数。HUD から設定する。
var is_blocked: Callable = func(_pos: Vector2) -> bool: return false

@export var radius := 110.0
@export var knob_radius := 46.0

const MOUSE_ID := -2

var value := Vector2.ZERO
var _active := false
var _pointer := -1  # 操作中のタッチ番号。マウス操作中は MOUSE_ID
var _origin := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 入力は _input で直接拾うので、GUI のクリックは邪魔しない
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and not _active and not is_blocked.call(event.position):
			_begin(event.index, event.position)
		elif not event.pressed and _active and event.index == _pointer:
			_end()
	elif event is InputEventScreenDrag:
		if _active and event.index == _pointer:
			_drag(event.position)
	# タッチから自動生成されたマウスイベント (device == -1) は二重処理になるので無視
	elif event is InputEventMouseButton and event.device != -1 and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not _active and not is_blocked.call(event.position):
			_begin(MOUSE_ID, event.position)
		elif not event.pressed and _active and _pointer == MOUSE_ID:
			_end()
	elif event is InputEventMouseMotion and event.device != -1:
		if _active and _pointer == MOUSE_ID:
			_drag(event.position)


func _begin(pointer: int, pos: Vector2) -> void:
	_active = true
	_pointer = pointer
	_origin = pos
	_set_value(Vector2.ZERO)


func _end() -> void:
	_active = false
	_pointer = -1
	_set_value(Vector2.ZERO)


func _drag(pos: Vector2) -> void:
	_set_value((pos - _origin).limit_length(radius) / radius)


func _set_value(v: Vector2) -> void:
	value = v
	vector_changed.emit(value)
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	draw_circle(_origin, radius, Color(1, 1, 1, 0.14))
	draw_arc(_origin, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.4), 3.0)
	draw_circle(_origin + value * radius, knob_radius, Color(1, 1, 1, 0.55))
