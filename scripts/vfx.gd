class_name Vfx
## パーティクル演出（木くず・葉・土ぼこり・おがくず・火花・煙・きらめき・水しぶき）。
## Web 版は Compatibility レンダラーでスマホでも動くので、すべて CPUParticles3D で作り、
## メッシュ・マテリアル・テクスチャは種類ごとに1つだけ作って使い回す（演出ごとに作るのは粒子のノード1つだけ）。
## ふわっとした煙やきらめきはライティングなしのビルボード、木くずや葉は光の当たる小さな板にしている。

static var _cache: Dictionary = {}


static func _res(key: String, make: Callable) -> Variant:
	if not _cache.has(key):
		_cache[key] = make.call()
	return _cache[key]


# ---- テクスチャ（コードで作る。外部素材なし） ----

## 中心が白く、外側へ透明になる丸（煙・土ぼこり・光）
static func soft_texture() -> Texture2D:
	return _res("tex/soft", func() -> Texture2D:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		return t)


## 十字に光るきらめき
static func star_texture() -> Texture2D:
	return _res("tex/star", func() -> Texture2D:
		var n := 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var u := (x + 0.5) / n * 2.0 - 1.0
				var v := (y + 0.5) / n * 2.0 - 1.0
				var cross := maxf(exp(-absf(v) * 18.0) * (1.0 - absf(u)), exp(-absf(u) * 18.0) * (1.0 - absf(v)))
				var glow := exp(-(u * u + v * v) * 9.0) * 0.7
				img.set_pixel(x, y, Color(1, 1, 1, clampf(cross + glow, 0.0, 1.0)))
		return ImageTexture.create_from_image(img))


## 葉っぱの形（先のとがった楕円に葉脈）。
static func leaf_texture() -> Texture2D:
	return _res("tex/leaf", func() -> Texture2D:
		var n := 32
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var u := (x + 0.5) / n * 2.0 - 1.0
				var v := (y + 0.5) / n * 2.0 - 1.0
				# 縦長の葉。上下の先をとがらせる
				var w := 0.62 * (1.0 - v * v) * (1.0 - 0.25 * v)
				var inside := absf(u) < w
				var vein := 0.82 if absf(u) < 0.06 else 1.0
				var shade := 0.85 + 0.15 * (1.0 - absf(u) / maxf(w, 0.01))
				img.set_pixel(x, y, Color(shade * vein, shade * vein, shade * vein, 1.0 if inside else 0.0))
		img.generate_mipmaps()
		return ImageTexture.create_from_image(img))


# ---- マテリアル・メッシュ ----

## ビルボードのスプライト（additive なら加算合成で光って見える）
static func _sprite_mat(kind: String, additive := false) -> StandardMaterial3D:
	return _res("mat/sprite/%s/%s" % [kind, additive], func() -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
		m.albedo_texture = star_texture() if kind == "star" else soft_texture()
		m.disable_receive_shadows = true
		return m)


static func _sprite_mesh(kind: String, additive := false) -> QuadMesh:
	return _res("mesh/sprite/%s/%s" % [kind, additive], func() -> QuadMesh:
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		q.material = _sprite_mat(kind, additive)
		return q)


## 光の当たる小さな破片（木くず・紙吹雪）。色は粒子ごとの色（頂点カラー）で付ける
static func _chip_mesh(size: Vector3) -> BoxMesh:
	return _res("mesh/chip/%s" % size, func() -> BoxMesh:
		var b := BoxMesh.new()
		b.size = size
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.85
		b.material = m
		return b)


## 葉っぱ（両面・アルファで切り抜き）
static func _leaf_mesh() -> QuadMesh:
	return _res("mesh/leaf", func() -> QuadMesh:
		var q := QuadMesh.new()
		q.size = Vector2(0.11, 0.16)
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = leaf_texture()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		# 裏返った葉が真っ黒にならないよう、ライティングなしで少し暗めの色にする
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		q.material = m
		return q)


## 紙吹雪（両面の薄い四角）
static func _confetti_mesh() -> QuadMesh:
	return _res("mesh/confetti", func() -> QuadMesh:
		var q := QuadMesh.new()
		q.size = Vector2(0.12, 0.07)
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.6
		q.material = m
		return q)


static func _curve(points: Array) -> Curve:
	var key := "curve/%s" % [points]
	return _res(key, func() -> Curve:
		var c := Curve.new()
		c.max_value = 4.0
		for p in points:
			c.add_point(p)
		return c)


## 時間とともに色・透明度が変わるグラデーション（粒子の寿命の 0..1）
static func _ramp(colors: Array, offsets: Array) -> Gradient:
	var key := "ramp/%s/%s" % [colors, offsets]
	return _res(key, func() -> Gradient:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array(offsets)
		g.colors = PackedColorArray(colors)
		return g)


## 粒子ごとに色をばらつかせる（colors から1色を選ぶのに近い）
static func _palette(colors: Array) -> Gradient:
	var key := "pal/%s" % [colors]
	return _res(key, func() -> Gradient:
		var g := Gradient.new()
		g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
		var offs := PackedFloat32Array()
		var cols := PackedColorArray()
		for i in colors.size():
			offs.append(float(i) / colors.size())
			cols.append(colors[i])
		g.offsets = offs
		g.colors = cols
		return g)


# ---- 粒子の発生 ----

## 1回だけ出して、出し終えたら消える粒子を作る。
static func _one_shot(context: Node, pos: Vector3, amount: int, lifetime: float) -> CPUParticles3D:
	var tree := context.get_tree()
	if tree == null or tree.current_scene == null:
		return null
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = maxi(1, amount)
	p.lifetime = lifetime
	p.explosiveness = 0.92
	p.randomness = 0.5
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tree.current_scene.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	# 念のため（finished が来なかったとき用）
	tree.create_timer(lifetime + 1.0).timeout.connect(p.queue_free)
	return p


## 小さな破片を飛び散らせる（紙吹雪など色とりどりのものは confetti=true で薄い四角がひらひら舞う）。
static func burst(context: Node, pos: Vector3, colors: Array, amount := 10, speed := 3.0, size := 0.09, lifetime := 0.7, gravity := -9.0, confetti := false) -> void:
	var p := _one_shot(context, pos, amount, lifetime)
	if p == null:
		return
	p.mesh = _confetti_mesh() if confetti else _chip_mesh(Vector3.ONE * 0.09)
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, gravity, 0)
	p.damping_min = 0.5 if confetti else 0.0
	p.damping_max = 2.5 if confetti else 0.0
	p.particle_flag_rotate_y = true
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.scale_amount_min = size / 0.09 * 0.7
	p.scale_amount_max = size / 0.09 * 1.3
	p.scale_amount_curve = _curve([Vector2(0, 1), Vector2(0.75, 0.9), Vector2(1, 0)])
	p.color_initial_ramp = _palette(colors)
	p.emitting = true


## 斧やノコギリで削れた木くず。away は飛ばす向き（水平）。
static func wood_chips(context: Node, pos: Vector3, away: Vector3, colors: Array, amount := 9) -> void:
	var p := _one_shot(context, pos, amount, 0.65)
	if p == null:
		return
	p.mesh = _chip_mesh(Vector3(0.11, 0.025, 0.06))
	var dir := (away.normalized() if away.length() > 0.01 else Vector3.FORWARD) + Vector3(0, 0.9, 0)
	p.direction = dir.normalized()
	p.spread = 38.0
	p.initial_velocity_min = 2.2
	p.initial_velocity_max = 4.6
	p.gravity = Vector3(0, -13.0, 0)
	p.particle_flag_rotate_y = true
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.scale_amount_curve = _curve([Vector2(0, 1), Vector2(0.8, 1), Vector2(1, 0)])
	p.color_initial_ramp = _palette(colors)
	p.emitting = true


## 葉が舞い落ちる。radius の範囲（樹冠）から、ゆっくり回りながら落ちる。
static func leaves(context: Node, pos: Vector3, color: Color, amount := 6, radius := 0.7, burst_speed := 0.8) -> void:
	var p := _one_shot(context, pos, amount, 1.9)
	if p == null:
		return
	p.mesh = _leaf_mesh()
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = burst_speed * 0.3
	p.initial_velocity_max = burst_speed
	p.gravity = Vector3(0, -1.8, 0)
	p.damping_min = 0.8
	p.damping_max = 1.6
	# ひらひら（横にふらつきながら回る）
	p.tangential_accel_min = -1.5
	p.tangential_accel_max = 1.5
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -260.0
	p.angular_velocity_max = 260.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.4
	p.scale_amount_curve = _curve([Vector2(0, 1), Vector2(0.85, 1), Vector2(1, 0)])
	p.color_initial_ramp = _palette([color.darkened(0.1), color.lightened(0.05), color.darkened(0.25)])
	p.explosiveness = 0.75
	p.emitting = true


## もくもくと広がって消える土ぼこり・煙。ring=true なら水平に輪になって広がる（倒木の着地など）。
static func dust(context: Node, pos: Vector3, color: Color, amount := 6, size := 0.6, speed := 1.2, ring := false, lifetime := 0.9) -> void:
	var p := _one_shot(context, pos, amount, lifetime)
	if p == null:
		return
	p.mesh = _sprite_mesh("soft")
	if ring:
		p.direction = Vector3.RIGHT
		p.spread = 180.0
		p.flatness = 1.0
	else:
		p.direction = Vector3.UP
		p.spread = 60.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, 0.6, 0)
	p.damping_min = speed * 1.2
	p.damping_max = speed * 2.0
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.scale_amount_min = size * 0.7
	p.scale_amount_max = size * 1.3
	p.scale_amount_curve = _curve([Vector2(0, 0.45), Vector2(0.4, 1.0), Vector2(1, 1.35)])
	p.color = color
	p.color_ramp = _ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)], [0.0, 0.15, 1.0])
	p.emitting = true


## キラッと光る（売れたとき・強化したとき）
static func sparkles(context: Node, pos: Vector3, color := Color("#ffe38a"), amount := 8, speed := 2.6) -> void:
	var p := _one_shot(context, pos, amount, 0.7)
	if p == null:
		return
	p.mesh = _sprite_mesh("star", true)
	p.direction = Vector3.UP
	p.spread = 75.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -3.0, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.angle_min = -45.0
	p.angle_max = 45.0
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.5
	p.scale_amount_curve = _curve([Vector2(0, 0.2), Vector2(0.15, 1.2), Vector2(0.6, 0.8), Vector2(1, 0)])
	p.color = color
	p.emitting = true


## 一瞬ふわっと光る輪（売却・購入の手応え）
static func flash(context: Node, pos: Vector3, color := Color("#ffd75a"), size := 1.6) -> void:
	var p := _one_shot(context, pos, 1, 0.35)
	if p == null:
		return
	p.mesh = _sprite_mesh("soft", true)
	p.explosiveness = 1.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.0
	p.scale_amount_min = size
	p.scale_amount_max = size
	p.scale_amount_curve = _curve([Vector2(0, 0.3), Vector2(0.3, 1.0), Vector2(1, 1.3)])
	p.color = color
	p.color_ramp = _ramp([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)], [0.0, 1.0])
	p.emitting = true


## 火花（ノコギリが節に当たったとき・機械の刃）
static func sparks(context: Node, pos: Vector3, away: Vector3, amount := 6) -> void:
	var p := _one_shot(context, pos, amount, 0.35)
	if p == null:
		return
	p.mesh = _sprite_mesh("soft", true)
	p.direction = (away.normalized() + Vector3(0, 0.8, 0)).normalized() if away.length() > 0.01 else Vector3.UP
	p.spread = 45.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -9.0, 0)
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.12
	p.scale_amount_curve = _curve([Vector2(0, 1), Vector2(1, 0.2)])
	p.color = Color("#ffc25a")
	p.color_ramp = _ramp([Color(1, 1, 0.85, 1), Color(1, 0.55, 0.2, 0.9), Color(0.9, 0.3, 0.1, 0)], [0.0, 0.5, 1.0])
	p.emitting = true


## 水しぶき（丸太が川に落ちたとき）
static func splash(context: Node, pos: Vector3, amount := 8) -> void:
	var p := _one_shot(context, pos, amount, 0.6)
	if p == null:
		return
	p.mesh = _sprite_mesh("soft")
	p.direction = Vector3.UP
	p.spread = 40.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.2
	p.gravity = Vector3(0, -9.0, 0)
	p.scale_amount_min = 0.15
	p.scale_amount_max = 0.35
	p.scale_amount_curve = _curve([Vector2(0, 0.6), Vector2(1, 1.3)])
	p.color = Color(0.93, 0.97, 1.0)
	p.color_ramp = _ramp([Color(1, 1, 1, 0.85), Color(1, 1, 1, 0)], [0.3, 1.0])
	p.emitting = true
	dust(context, pos, Color(0.9, 0.96, 1.0), 3, 0.5, 1.2, true, 0.6)


# ---- 出しっぱなしの粒子（呼んだ側が emitting を切り替える） ----

## 排気の煙。parent の子として付ける（位置は呼んだ側で決める）。
static func make_smoke(rate := 8, size := 0.35, color := Color(0.42, 0.42, 0.42)) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = rate
	p.lifetime = 1.2
	p.local_coords = false
	p.mesh = _sprite_mesh("soft")
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.1
	p.gravity = Vector3(0.25, 0.35, 0.1)
	p.damping_min = 0.4
	p.damping_max = 0.8
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.scale_amount_min = size * 0.8
	p.scale_amount_max = size * 1.2
	p.scale_amount_curve = _curve([Vector2(0, 0.35), Vector2(1, 2.0)])
	p.color = color
	p.color_ramp = _ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)], [0.0, 0.12, 1.0])
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## ノコギリから吹き出すおがくず（細かい粒と、ふわっとした粉）。direction はローカルの向き。
static func make_sawdust(direction: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 26
	p.lifetime = 0.7
	p.local_coords = false
	p.mesh = _chip_mesh(Vector3(0.04, 0.04, 0.04))
	p.direction = direction
	p.spread = 28.0
	p.initial_velocity_min = 1.6
	p.initial_velocity_max = 3.2
	p.gravity = Vector3(0, -6.0, 0)
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	p.scale_amount_curve = _curve([Vector2(0, 1), Vector2(0.8, 0.9), Vector2(1, 0)])
	p.color_initial_ramp = _palette([Color("#f0d6a4"), Color("#d9b47a"), Color("#e8c99a")])
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## 粉っぽいおがくずの煙（make_sawdust と一緒に使う）
static func make_sawdust_haze(direction: Vector3) -> CPUParticles3D:
	var p := make_smoke(6, 0.3, Color("#ecd7b0"))
	p.direction = direction
	p.spread = 30.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0, -0.2, 0)
	p.lifetime = 0.9
	return p


## 川の水しぶき・白い泡（流れ着く所や岸）
static func make_splash(width := 2.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 14
	p.lifetime = 0.8
	p.local_coords = false
	p.mesh = _sprite_mesh("soft")
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(width * 0.5, 0.02, 0.15)
	p.direction = Vector3(0, 1, 0.6)
	p.spread = 25.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0, -3.0, 0)
	p.scale_amount_min = 0.18
	p.scale_amount_max = 0.35
	p.scale_amount_curve = _curve([Vector2(0, 0.5), Vector2(1, 1.4)])
	p.color = Color(0.95, 0.98, 1.0)
	p.color_ramp = _ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)], [0.0, 0.2, 1.0])
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p
