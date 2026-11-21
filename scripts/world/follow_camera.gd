class_name FollowCamera
extends Camera3D
## プレイヤーを斜め上から追うカメラ。乗車中は少し引き、木が倒れたときなどに軽く揺れる。
## 位置は data/balance.json の camera で調整する。

const FOLLOW_SPEED := 6.0
const ZOOM_SPEED := 2.5

var target: Player

var _zoom := 1.0
var _shake := 0.0


func _ready() -> void:
	fov = float(GameData.camera.get("fov", 50))
	keep_aspect = Camera3D.KEEP_WIDTH
	current = true


func snap() -> void:
	global_position = _desired()
	look_at(_look_point(), Vector3.UP)


func add_shake(strength: float) -> void:
	_shake = minf(0.4, _shake + strength)


func _offset() -> Vector3:
	return Vector3(0, float(GameData.camera.get("height", 7.5)), float(GameData.camera.get("back", 5.0))) * _zoom


func _desired() -> Vector3:
	return target.global_position + _offset()


func _look_point() -> Vector3:
	return target.global_position + Vector3(0, 0.6, -0.6) * _zoom


func _process(delta: float) -> void:
	if target == null:
		return
	var want_zoom := float(GameData.camera.get("drive_zoom", 1.35)) if target.vehicle else 1.0
	_zoom = lerpf(_zoom, want_zoom, minf(1.0, delta * ZOOM_SPEED))
	global_position = global_position.lerp(_desired(), minf(1.0, delta * FOLLOW_SPEED))
	look_at(global_position - _offset() + (_look_point() - target.global_position), Vector3.UP)
	if _shake > 0.0:
		h_offset = randf_range(-_shake, _shake)
		v_offset = randf_range(-_shake, _shake)
		_shake = maxf(0.0, _shake - delta * 1.5)
	else:
		h_offset = 0.0
		v_offset = 0.0
	Mats.set_focus(global_position, target.global_position + Vector3(0, 0.8, 0))
