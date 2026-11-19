class_name Station
extends Node3D
## 売却ポイントなど「上に立つと一定間隔で受け渡しが起きる場所」の共通処理。

var _timers: Dictionary = {}


## 指定位置から半径内にいる運搬者（プレイヤー・伐採員）を返す。
func carriers_near(pos: Vector3, radius: float, player_only := false) -> Array[Node]:
	var result: Array[Node] = []
	var group := "player" if player_only else "carriers"
	for node in get_tree().get_nodes_in_group(group):
		if Fx.xz_distance((node as Node3D).global_position, pos) <= radius:
			result.append(node)
	return result


## 運搬者ごとの受け渡し間隔を管理する。受け渡してよいフレームなら true。
func tick(carrier: Node, key: String, delta: float, interval := -1.0) -> bool:
	if interval < 0.0:
		interval = float(GameData.player.get("transfer_interval", 0.08))
	var k := "%d:%s" % [carrier.get_instance_id(), key]
	var t: float = _timers.get(k, 0.0) - delta
	if t <= 0.0:
		_timers[k] = interval
		return true
	_timers[k] = t
	return false
