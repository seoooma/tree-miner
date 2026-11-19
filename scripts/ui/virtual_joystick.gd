class_name VirtualJoystick
extends Control
## 画面のどこを触ってもその位置を中心に出るフローティング型スティック。
## タッチはマウスイベントとしてエミュレートされるので、PCのマウスドラッグでも動く。

signal vector_changed(value: Vector2)

@export var radius := 110.0
@export var knob_radius := 46.0

var value := Vector2.ZERO
var _active := false
var _origin := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_active = true
			_origin = event.position
			_set_value(Vector2.ZERO)
		else:
			_active = false
			_set_value(Vector2.ZERO)
	elif event is InputEventMouseMotion and _active:
		_set_value((event.position - _origin).limit_length(radius) / radius)


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
