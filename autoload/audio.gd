extends Node
## BGM と効果音の再生。Audio.play("chop") のように名前で鳴らす。
## 音量のオン／オフは user://settings.json に保存する。

const SETTINGS_PATH := "user://settings.json"

## 名前 → ファイル。出典は CREDITS.md
const SOUNDS := {
	"chop": "res://assets/audio/chop.ogg",
	"tree_fall": "res://assets/audio/tree_fall.ogg",
	"pickup": "res://assets/audio/placement-a.ogg",
	"sell": "res://assets/audio/coin.ogg",
	"buy": "res://assets/audio/placement-c.ogg",
	"unlock": "res://assets/audio/placement-b.ogg",
	"fuel": "res://assets/audio/toggle.ogg",
	"ui": "res://assets/audio/toggle.ogg",
	"board": "res://assets/audio/impact.ogg",
	"drop": "res://assets/audio/land.ogg",
}
const LOOPS := {
	"engine": "res://assets/audio/engine.ogg",
	"walk": "res://assets/audio/walking.ogg",
}
const MUSIC := "res://assets/audio/bgm_forest.ogg"
## 同じ音を連続で鳴らすときの最短間隔（秒）
const MIN_INTERVAL := 0.045
const POOL_SIZE := 12

var music_enabled := true
var sfx_enabled := true

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _last_played: Dictionary = {}
var _loops: Dictionary = {}
var _music: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	for key in SOUNDS:
		_streams[key] = load(SOUNDS[key])
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	for key in LOOPS:
		var stream: AudioStream = load(LOOPS[key])
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.volume_db = -80.0
		add_child(p)
		_loops[key] = p
	_music = AudioStreamPlayer.new()
	var music_stream: AudioStream = load(MUSIC)
	if music_stream is AudioStreamOggVorbis:
		(music_stream as AudioStreamOggVorbis).loop = true
	_music.stream = music_stream
	_music.volume_db = -9.0
	add_child(_music)
	_apply_music()


## 効果音を鳴らす。pitch_jitter で毎回少し音程を揺らして単調さを避ける。
func play(key: String, volume_db := 0.0, pitch := 1.0, pitch_jitter := 0.08) -> void:
	if not sfx_enabled or not _streams.has(key):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(key, -1.0)) < MIN_INTERVAL:
		return
	_last_played[key] = now
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _streams[key]
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
	p.play()


## ループ音（エンジン・足音）の音量と音程を毎フレーム指定する。active=false でフェードアウト。
func set_loop(key: String, active: bool, volume_db := 0.0, pitch := 1.0) -> void:
	var p: AudioStreamPlayer = _loops.get(key)
	if p == null:
		return
	active = active and sfx_enabled
	if active and not p.playing:
		p.play()
	var target := volume_db if active else -60.0
	p.volume_db = lerpf(p.volume_db, target, 0.15)
	p.pitch_scale = lerpf(p.pitch_scale, pitch, 0.1)
	if not active and p.playing and p.volume_db < -50.0:
		p.stop()


func toggle_music() -> void:
	music_enabled = not music_enabled
	_apply_music()
	_save_settings()


func toggle_sfx() -> void:
	sfx_enabled = not sfx_enabled
	_save_settings()


func _apply_music() -> void:
	if music_enabled and not _music.playing:
		_music.play()
	elif not music_enabled:
		_music.stop()


func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.open(SETTINGS_PATH, FileAccess.READ).get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		music_enabled = bool(parsed.get("music", true))
		sfx_enabled = bool(parsed.get("sfx", true))


func _save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"music": music_enabled, "sfx": sfx_enabled}))
