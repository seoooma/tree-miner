class_name Mats
## マテリアル（地面・木・建物・人物・トラック）。
## 画風はフラットカラーのローポリ（Kenney / Quaternius のモデルと同じ）にそろえる。写真のテクスチャは使わず、
## 色は PALETTE の少ない色から選び、陰影はライト（太陽＋青紫の環境光）とメッシュの面の向きで出す。
## 同じ設定のマテリアルはキャッシュして使い回す。

const TEX := "res://assets/textures/"

## 色の設計: 背景（地面・木・建物）は明るく彩度控えめ、触れる物（丸太・板・お金・パッド）だけ彩度を高くする。
const PALETTE := {
	"grass": Color("#93c95b"),
	"grass_dark": Color("#7bb84e"),
	"grass_light": Color("#a5d466"),
	"yard": Color("#ecd39c"),
	"yard_dark": Color("#dfc086"),
	"road": Color("#ecd39c"),
	"outer": Color("#86bd55"),
}

static var _cache: Dictionary = {}
## 拠点の土の作業場（草地の中に、施設のまわりだけ土を敷く）。Vector4(中心x, 中心z, 半幅x, 半幅z) の角丸長方形
static var sand_rects: Array[Vector4] = []
const SAND_RADIUS := 1.6


## 地面のその場所が拠点の土の作業場か（草や花を生やさないため）。margin だけ外側も含める。
static func is_sand(pos: Vector3, margin := 0.0) -> bool:
	for r in sand_rects:
		var q := Vector2(absf(pos.x - r.x) - r.z + SAND_RADIUS, absf(pos.z - r.y) - r.w + SAND_RADIUS)
		var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - SAND_RADIUS
		if d < margin:
			return true
	return false


static func tex(name: String) -> Texture2D:
	return load(TEX + name) as Texture2D


static func _cached_mat(key: String, make: Callable) -> Material:
	if not _cache.has(key):
		_cache[key] = make.call()
	return _cache[key]


## 地面（草地 grass / 作業場 yard / 道 road）。単色に、大きくゆるやかな明暗のムラだけを付ける。
## tint は奥のエリアほど少し色を変えるのに使う。
static func ground(kind: String, tint := Color.WHITE, _tile := -1.0) -> ShaderMaterial:
	return _cached_mat("ground/%s/%s" % [kind, tint.to_html()], func() -> Material:
		var sh := Shader.new()
		sh.code = GROUND_SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		var base: Color = PALETTE.get(kind, PALETTE["grass"])
		var dark: Color = PALETTE.get(kind + "_dark", base.darkened(0.08))
		var light: Color = PALETTE.get(kind + "_light", base.lightened(0.05))
		m.set_shader_parameter("base_color", base * tint)
		m.set_shader_parameter("dark_color", dark * tint)
		m.set_shader_parameter("light_color", light * tint)
		m.set_shader_parameter("macro_noise", tex("leaf_noise.png"))
		if kind == "grass" and not sand_rects.is_empty():
			var arr: Array = []
			for r in sand_rects:
				arr.append(r)
			while arr.size() < 8:
				arr.append(Vector4.ZERO)
			m.set_shader_parameter("rect_count", sand_rects.size())
			m.set_shader_parameter("rects", arr)
			m.set_shader_parameter("rect_radius", SAND_RADIUS)
			m.set_shader_parameter("sand_color", PALETTE["yard"])
			m.set_shader_parameter("sand_dark", PALETTE["yard_dark"])
			m.set_shader_parameter("edge_color", PALETTE["grass_dark"].darkened(0.05))
		return m)


const GROUND_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform vec4 base_color : source_color;
uniform vec4 dark_color : source_color;
uniform vec4 light_color : source_color;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
// 草地の中の土の作業場（角丸長方形の集まり）
uniform int rect_count = 0;
uniform vec4 rects[8];
uniform float rect_radius = 1.6;
uniform vec4 sand_color : source_color;
uniform vec4 sand_dark : source_color;
uniform vec4 edge_color : source_color;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float sand_sdf(vec2 p) {
	float d = 1e5;
	for (int i = 0; i < rect_count; i++) {
		vec2 q = abs(p - rects[i].xy) - rects[i].zw + vec2(rect_radius);
		d = min(d, length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rect_radius);
	}
	return d;
}
void fragment() {
	// 大きなまだら（色の境目はやわらかく、ただし段がわかる程度にくっきり）
	float n1 = texture(macro_noise, wpos.xz * 0.006).r;
	float n2 = texture(macro_noise, wpos.xz * 0.011 + vec2(0.3, 0.7)).r;
	float d = smoothstep(0.5, 0.58, n1 * 0.6 + n2 * 0.4);
	float l = smoothstep(0.56, 0.64, n2 * 0.7 + (1.0 - n1) * 0.3);
	vec3 col = mix(base_color.rgb, dark_color.rgb, d);
	col = mix(col, light_color.rgb, l * (1.0 - d));
	if (rect_count > 0) {
		float n3 = texture(macro_noise, wpos.xz * 0.09).r;
		float sd = sand_sdf(wpos.xz) + (n3 - 0.5) * 0.7;
		vec3 sand = mix(sand_color.rgb, sand_dark.rgb, d * 0.8);
		// 草の縁は少し濃い緑で縁取る
		col = mix(col, edge_color.rgb, 1.0 - smoothstep(0.0, 0.35, sd));
		col = mix(col, sand, 1.0 - smoothstep(-0.04, 0.04, sd));
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
"""


## 道や境目の帯。端が地面になじむように透明度でぼかす。
## mode 0: PlaneMesh の UV.x の両端をぼかす（道）。mode 1: UV.y の小さい側（奥）だけぼかす（作業場と草地の境目）
static func strip(kind := "road", mode := 0) -> ShaderMaterial:
	return _cached_mat("strip/%s/%d" % [kind, mode], func() -> Material:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
uniform vec4 base_color : source_color;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform float edge = 0.32;
uniform int mode = 0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	ALBEDO = base_color.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	float n = texture(macro_noise, wpos.xz * 0.15).r;
	float d = mode == 0 ? min(UV.x, 1.0 - UV.x) : UV.y;
	// 端は少しだけ波打たせて、くっきり切る（フラットな画風に合わせ、ぼかしは狭く）
	float e = smoothstep(0.0, 0.12, d / edge + (n - 0.5) * 0.5 - 0.35);
	// 道は拠点（z > 0 の作業場）に入るところで、地面になじむように消す
	float fade = mode == 0 ? 1.0 - smoothstep(-1.0, 1.2, wpos.z + (n - 0.5) * 1.2) : 1.0;
	ALPHA = e * fade;
}
"""
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("base_color", PALETTE.get(kind, PALETTE["road"]))
		m.set_shader_parameter("macro_noise", tex("leaf_noise.png"))
		m.set_shader_parameter("mode", mode)
		m.set_shader_parameter("edge", 0.32 if mode == 0 else 0.9)
		return m)


## 木（フラットカラー。幹・切り口・葉の色は頂点カラー、陰影は面の向き）。
## メッシュの頂点カラー: rgb = 基本色、a = 0 なら幹・0.5 なら木口（切り口）・1 なら葉。
## MultiMesh のインスタンスカラーで1本ごとに葉の色を少し変える（頂点カラーに掛け合わされて COLOR に入る）。
static func tree(use_custom := true) -> ShaderMaterial:
	return _cached_mat("tree/%s" % use_custom, func() -> Material:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode cull_back;
uniform bool use_custom = true;
uniform float wind = 1.0;
// カメラとプレイヤーの間にある木は網目状に抜いて、プレイヤーを隠さないようにする
uniform vec3 cam_pos = vec3(0.0, -100.0, 0.0);
uniform vec3 focus_pos = vec3(0.0, -100.0, 0.0);
uniform float fade_radius = 1.5;
varying float leaf;
varying float ao;
varying vec3 wpos;
void vertex() {
	leaf = COLOR.a;
	// 葉の下側は少し暗く、幹は根元を少し暗く（簡易的な環境遮蔽）
	if (leaf > 0.75) {
		ao = mix(0.78, 1.0, smoothstep(-0.6, 0.6, NORMAL.y));
	} else {
		ao = mix(0.8, 1.0, smoothstep(0.0, 0.3, VERTEX.y));
	}
	if (use_custom) {
		// 風で揺れる（高い所ほど大きく。木ごとに位相をずらす）。風向きはワールドの +X 寄り
		vec3 origin = MODEL_MATRIX[3].xyz;
		float ph = origin.x * 0.37 + origin.z * 0.23;
		float t = TIME * 1.25 + ph;
		float h = max(VERTEX.y, 0.0);
		float bend = (sin(t) * 0.65 + sin(t * 2.17 + 1.3) * 0.25 + 0.35) * h * h * 0.012 * wind;
		vec3 wdir = (vec4(1.0, 0.0, 0.4, 0.0) * MODEL_MATRIX).xyz;
		wdir /= max(dot(wdir, wdir), 0.0001);
		VERTEX += wdir * bend;
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 seg = focus_pos - cam_pos;
	float t = dot(wpos - cam_pos, seg) / max(dot(seg, seg), 0.001);
	float dist = length(wpos - (cam_pos + seg * clamp(t, 0.0, 1.0)));
	if (t < 0.96 && dist < fade_radius) {
		vec2 fc = floor(FRAGCOORD.xy);
		if (mod(fc.x, 2.0) + mod(fc.y, 2.0) > 0.5) {
			discard;
		}
	}
	ALBEDO = COLOR.rgb * ao;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	if (leaf > 0.75) {
		// 輪郭がうっすら明るい（葉に日が回る感じ）
		float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		EMISSION = COLOR.rgb * rim * 0.25;
	}
}
"""
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("use_custom", use_custom)
		return m)


## 木の網目抜き（カメラとプレイヤーの間の木を透かす）の位置を更新する。カメラが毎フレーム呼ぶ。
static func set_focus(cam: Vector3, focus: Vector3) -> void:
	var key := "tree/true"
	if _cache.has(key):
		var m: ShaderMaterial = _cache[key]
		m.set_shader_parameter("cam_pos", cam)
		m.set_shader_parameter("focus_pos", focus)


## 草・花（風でそよぐ）。color を指定すると単色、Color(0,0,0,0) なら頂点カラーを使う。
## 根元ほど暗くして、地面から生えている感じを出す。
static func foliage(color := Color(0, 0, 0, 0)) -> ShaderMaterial:
	return _cached_mat("foliage/%s" % color.to_html(), func() -> Material:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 base_color : source_color = vec4(0.0);
uniform float height = 0.3;
varying float h;
void vertex() {
	h = clamp(VERTEX.y / height, 0.0, 1.0);
	// 細い葉は裏表で明暗が割れるとちらつくので、上向きの面として光を受ける
	NORMAL = (vec4(0.0, 1.0, 0.0, 0.0) * MODEL_MATRIX).xyz;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float ph = origin.x * 0.9 + origin.z * 0.6;
	float sway = sin(TIME * 2.1 + ph) * 0.6 + sin(TIME * 3.3 + ph * 1.7) * 0.3 + 0.3;
	vec3 wdir = (vec4(0.93, 0.0, 0.37, 0.0) * MODEL_MATRIX).xyz;
	wdir /= max(dot(wdir, wdir), 0.0001);
	VERTEX += wdir * sway * h * h * 0.07;
}
void fragment() {
	vec3 c = base_color.a > 0.0 ? base_color.rgb : COLOR.rgb;
	ALBEDO = c * mix(0.78, 1.05, h);
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
}
"""
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("base_color", color)
		return m)


## 建物・小物用の単色マテリアル。kind: "paint"（塗装・プラスチック）/ "wood"（板材）/ "metal"（塗装金属）/ "roof"（屋根）。
## どれもフラットカラーで、質感の違いはツヤの強さだけで出す。
static func surface(color: Color, kind := "paint", roughness := 0.8) -> StandardMaterial3D:
	return _cached_mat("surf/%s/%s/%.2f" % [color.to_html(), kind, roughness], func() -> Material:
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		match kind:
			"metal":
				m.roughness = 0.55
				m.metallic_specular = 0.45
			"roof":
				m.roughness = 0.7
				m.metallic_specular = 0.35
			"wood":
				m.roughness = 1.0
				m.metallic_specular = 0.15
			_:
				m.roughness = clampf(roughness, 0.6, 1.0)
				m.metallic_specular = 0.25
		return m)


## 作業員の肌。ひざ下（モデルの足元）は茶色の革のブーツにする。
static func worker_skin() -> ShaderMaterial:
	return _cached_mat("worker_skin", func() -> Material:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
uniform vec3 skin : source_color = vec3(0.86, 0.64, 0.5);
uniform vec3 boots : source_color = vec3(0.36, 0.22, 0.12);
varying float h;
void vertex() { h = VERTEX.y; }
void fragment() {
	float b = 1.0 - smoothstep(0.42, 0.5, h);
	ALBEDO = mix(skin, boots, b);
	ROUGHNESS = mix(0.7, 0.5, b);
	SPECULAR = mix(0.35, 0.5, b);
}
"""
		var m := ShaderMaterial.new()
		m.shader = sh
		return m)


## 服（布地）。denim を true にすると少し青みのツヤを抑えた厚手の生地にする。
static func cloth(color: Color, roughness := 0.85, denim := false) -> StandardMaterial3D:
	return _cached_mat("cloth/%s/%.2f/%s" % [color.to_html(), roughness, denim], func() -> Material:
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = roughness
		m.metallic_specular = 0.3 if denim else 0.4
		m.rim_enabled = true
		m.rim = 0.25
		m.rim_tint = 0.6
		return m)


## トラック: Kenney のカラーマップそのまま（フラットカラー）に、塗装らしい弱いツヤだけ足す。
static func truck(texture: Texture2D) -> StandardMaterial3D:
	return _cached_mat("truck/%s" % texture.resource_path, func() -> Material:
		var m := StandardMaterial3D.new()
		m.albedo_texture = texture
		m.roughness = 0.6
		m.metallic_specular = 0.4
		return m)


## 地面に描く白い印（ゾーン枠・ガイド矢印）用の、ライティングなしのマテリアル。
static func ground_paint(color: Color) -> StandardMaterial3D:
	return _cached_mat("paint/%s" % color.to_html(), func() -> Material:
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if color.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		return m)
