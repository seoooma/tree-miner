class_name Conveyor
extends Node3D
## 2点間を折れ線でつなぐベルトコンベア。強化で開放し、レベルで1秒あたりに運ぶ数が増える。
## - 送り元から1つずつ載せ（rate_source の本/秒の間隔で）、ベルトの端まで運んだら送り先に渡す
## - room_source で送り先の受け入れを制限できる（既定は常に受け入れる）
## 見た目（フレーム・ベルト・脚）と運ぶ処理の両方を持つ。path は親ノードの座標で指定する。

const BELT_SPEED := 3.0

var path: Array[Vector3] = []
## 1秒あたりに載せる数
var rate_source: Callable = func() -> float: return 1.0
## 送り元から1つ取り出す（取れなければ空文字）
var take_source: Callable = func() -> String: return ""
## 送り先にまだ置けるか（引数はベルトに載っている数）
var room_source: Callable = func(_in_flight: int) -> bool: return true
## 端まで運んだものを送り先に渡す
var deliver: Callable = func(_id: String) -> void: pass
## 載せるものの見た目
var make_mesh: Callable = func(id: String) -> Node3D: return LogDrop.make_log_mesh(id)
## 端に着くたびに増える累計
var delivered := 0

## ベルトに載っているもの {"id", "d": 進んだ距離, "node"}
var items: Array[Dictionary] = []
var _length := 0.0
var _timer := 0.0
var _visual: Node3D
var _stripes: Array[MeshInstance3D] = []
var _scroll := 0.0


func _ready() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	_length = build_visual(_visual, path, _stripes)


func is_active() -> bool:
	return visible


func set_active(on: bool) -> void:
	visible = on
	set_process(on)


func length() -> float:
	return _length


## ベルトに載っている数
func in_flight() -> int:
	return items.size()


func ids_in_flight() -> Array[String]:
	var out: Array[String] = []
	for item in items:
		out.append(str(item["id"]))
	return out


func _process(delta: float) -> void:
	# 送り元から載せる
	_timer -= delta
	if _timer <= 0.0 and room_source.call(items.size()):
		var id: String = take_source.call()
		if id != "":
			var node: Node3D = make_mesh.call(id)
			_visual.add_child(node)
			items.append({"id": id, "d": 0.0, "node": node})
			_timer = 1.0 / maxf(0.01, float(rate_source.call()))
			_place(items[-1])
		else:
			_timer = 0.0
	elif _timer < 0.0:
		_timer = 0.0
	# 運ぶ
	var i := 0
	while i < items.size():
		var item := items[i]
		item["d"] = float(item["d"]) + BELT_SPEED * delta
		if float(item["d"]) >= _length:
			(item["node"] as Node3D).queue_free()
			items.remove_at(i)
			delivered += 1
			deliver.call(str(item["id"]))
			continue
		_place(item)
		i += 1
	# ベルトの継ぎ目が流れて見えるように
	_scroll = fmod(_scroll + BELT_SPEED * delta, 0.5)
	for s in _stripes:
		var base: Vector3 = s.get_meta("base")
		var dir: Vector3 = s.get_meta("dir")
		var seg: float = s.get_meta("seg")
		var off := fmod(float(s.get_meta("off")) + _scroll, seg)
		s.position = base + dir * off


func _place(item: Dictionary) -> void:
	var t := point_at(path, float(item["d"]))
	var node: Node3D = item["node"]
	node.position = t[0] + Vector3(0, 0.44, 0)
	node.rotation.y = t[1]


## 経路上の距離 d の位置と向き（載せたものが進行方向に直角になる角度）
static func point_at(p: Array[Vector3], d: float) -> Array:
	for k in range(1, p.size()):
		var a := p[k - 1]
		var b := p[k]
		var seg := a.distance_to(b)
		if d <= seg or k == p.size() - 1:
			var dir := (b - a).normalized()
			return [a.lerp(b, clampf(d / maxf(seg, 0.001), 0.0, 1.0)), atan2(dir.x, dir.z)]
		d -= seg
	return [p[-1], 0.0]


## コンベアの見た目を root に作り、経路の長さを返す。強化画面のサムネイルでも使う。
## stripes を渡すと、流れる継ぎ目のメッシュを入れて返す。
static func build_visual(root: Node3D, p: Array[Vector3], stripes: Array[MeshInstance3D] = []) -> float:
	var total := 0.0
	for k in range(1, p.size()):
		var a := p[k - 1]
		var b := p[k]
		var seg := a.distance_to(b)
		total += seg
		var mid := (a + b) * 0.5
		var seg_len := seg + 0.8
		var along_x := absf(b.x - a.x) > absf(b.z - a.z)
		var belt_size := Vector3(seg_len, 0.05, 0.62) if along_x else Vector3(0.62, 0.05, seg_len)
		var frame_size := Vector3(seg_len, 0.1, 0.74) if along_x else Vector3(0.74, 0.1, seg_len)
		root.add_child(Fx.box(frame_size, Color("#8c939a"), mid + Vector3(0, 0.25, 0), "metal"))
		root.add_child(Fx.box(belt_size, Color("#3d4247"), mid + Vector3(0, 0.31, 0), "metal"))
		# 脚
		var dir := (b - a).normalized()
		var steps := maxi(1, floori(seg_len / 1.6))
		for j in steps + 1:
			var q := (a - dir * 0.3).lerp(b + dir * 0.3, j / float(steps))
			for side in [-0.38, 0.38]:
				var off := Vector3(0, 0, side * 0.8) if along_x else Vector3(side * 0.8, 0, 0)
				root.add_child(Fx.box(Vector3(0.07, 0.22, 0.07), Color("#5b6168"), q + off + Vector3(0, 0.11, 0), "metal"))
		# ベルトの継ぎ目（動いていることが分かるように流す）
		var stripe_size := Vector3(0.05, 0.012, 0.6) if along_x else Vector3(0.6, 0.012, 0.05)
		var n := maxi(1, floori(seg / 0.5))
		for j in n:
			var s := Fx.box(stripe_size, Color("#5b6168"), a + dir * (j * 0.5) + Vector3(0, 0.34, 0), "metal")
			s.set_meta("base", a + Vector3(0, 0.34, 0))
			s.set_meta("dir", dir)
			s.set_meta("seg", seg)
			s.set_meta("off", j * 0.5)
			root.add_child(s)
			stripes.append(s)
	return total
