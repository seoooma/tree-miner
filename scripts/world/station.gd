class_name Station
extends Node3D
## 売却ポイントなど「上に立つと一定間隔で受け渡しが起きる場所」の共通処理。

var _timers: Dictionary = {}


## 指定位置から半径内にいるグループのメンバーを返す。
## group: "carriers"（丸太を運ぶ全員）/ "plank_carriers"（板も運べる: プレイヤー・運搬車）/ "player"
## 大きな機械は meta "pad_reach" の分だけ遠くからでも乗っている扱いにする。
func carriers_near(pos: Vector3, radius: float, group := "carriers") -> Array[Node]:
	var result: Array[Node] = []
	for node in get_tree().get_nodes_in_group(group):
		var reach := float(node.get_meta("pad_reach", 0.0))
		if Fx.xz_distance((node as Node3D).global_position, pos) <= radius + reach:
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
