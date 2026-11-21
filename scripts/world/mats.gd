class_name Mats
## 質感付きマテリアル（地面・木・建物・人物・トラック）。
## 地面・樹皮・板材は Poly Haven（CC0）の写真素材（tools/import_polyhaven.py で 512px に縮小）、
## 金属・塗装・葉のノイズは tools/make_textures.py で生成したもの。
## 同じ設定のマテリアルはキャッシュして使い回す。

const TEX := "res://assets/textures/"

static var _cache: Dictionary = {}

## 写真素材の色を、ゲームの明るい色調に合わせるための掛け率（1 より大きいと明るくなる）。
## leafy_grass は枯れ草寄りなので緑を強め、土は少し明るくする。
const GROUND_GAIN := {
	"grass": Color(0.6, 0.93, 0.6),
	"forest": Color(0.62, 0.86, 0.56),
	"yard": Color(1.12, 1.05, 0.95),
	"road": Color(1.4, 1.34, 1.28),
}


static func tex(name: String) -> Texture2D:
	return load(TEX + name) as Texture2D


static func _cached_mat(key: String, make: Callable) -> Material:
	if not _cache.has(key):
		_cache[key] = make.call()
	return _cache[key]


## 地面（草地 grass / 作業場 yard / 道 road）。ワールド座標でタイルする。tile は 1 枚が何 m か。
## 写真素材は同じ模様の繰り返しが目立つので、向きと大きさを変えた2回のサンプルを大きなノイズで混ぜ、
## 草地にはさらに林床（落ち葉と土）のパッチを混ぜて、広い面でも単調にならないようにする。
static func ground(kind: String, tint := Color.WHITE, tile := -1.0) -> ShaderMaterial:
	if tile <= 0.0:
		tile = GROUND_TILE.get(kind, 4.0)
	return _cached_mat("ground/%s/%s/%.1f" % [kind, tint.to_html(), tile], func() -> Material:
		var sh := Shader.new()
		sh.code = GROUND_SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		var second := "forest" if kind == "grass" else kind
		m.set_shader_parameter("albedo_a", tex(kind + "_albedo.png"))
		m.set_shader_parameter("normal_a", tex(kind + "_normal.png"))
		m.set_shader_parameter("albedo_b", tex(second + "_albedo.png"))
		m.set_shader_parameter("normal_b", tex(second + "_normal.png"))
		m.set_shader_parameter("macro_noise", tex("leaf_noise.png"))
		m.set_shader_parameter("tint", tint)
		m.set_shader_parameter("gain_a", _gain(kind))
		m.set_shader_parameter("gain_b", _gain(second))
		m.set_shader_parameter("tile", tile)
		m.set_shader_parameter("patch_amount", 0.55 if kind == "grass" else 0.0)
		return m)


## 地面のテクスチャ 1 枚が何 m 四方か（小石の大きさが人物に対して自然に見えるように）
const GROUND_TILE := {"grass": 4.0, "yard": 2.6, "road": 3.0}


static func _gain(kind: String) -> Vector3:
	var c: Color = GROUND_GAIN.get(kind, Color.WHITE)
	return Vector3(c.r, c.g, c.b)


const GROUND_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform sampler2D albedo_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D albedo_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec3 gain_a = vec3(1.0);
uniform vec3 gain_b = vec3(1.0);
uniform float tile = 4.0;
uniform float patch_amount = 0.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = wpos.xz / tile;
	// 回転・拡大した2回目のサンプル（繰り返し模様を崩す）
	vec2 uv2 = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80)) * uv * 0.73 + vec2(0.37, 0.11);
	float n1 = texture(macro_noise, wpos.xz * 0.021).r;
	float n2 = texture(macro_noise, wpos.xz * 0.053 + vec2(0.3, 0.7)).r;
	float w = smoothstep(0.35, 0.65, n1);
	vec3 ca = mix(texture(albedo_a, uv).rgb, texture(albedo_a, uv2).rgb, w) * gain_a;
	vec3 na = mix(texture(normal_a, uv).rgb, texture(normal_a, uv2).rgb, w);
	// 林床のパッチ（草地のみ）
	float p = smoothstep(0.58, 0.78, n2 * 0.7 + n1 * 0.3) * patch_amount;
	vec3 cb = texture(albedo_b, uv * 1.1).rgb * gain_b;
	vec3 nb = texture(normal_b, uv * 1.1).rgb;
	vec3 col = mix(ca, cb, p);
	// 大きな明暗のムラ
	col *= 0.86 + 0.28 * n2;
	ALBEDO = col * tint.rgb;
	NORMAL_MAP = mix(na, nb, p);
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = 0.95;
	SPECULAR = 0.25;
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
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile = 3.0;
uniform float edge = 0.32;
uniform int mode = 0;
uniform vec3 gain = vec3(1.0);
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = wpos.xz / tile;
	ALBEDO = texture(albedo_tex, uv).rgb * gain;
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	ROUGHNESS = 0.95;
	float n = texture(albedo_tex, uv * 0.37).g;
	float d = mode == 0 ? min(UV.x, 1.0 - UV.x) : UV.y;
	float e = d / edge + (n - 0.5) * 0.9;
	// 道は拠点（z > 0 の作業場）に入るところで、地面になじむように消す
	float fade = mode == 0 ? 1.0 - smoothstep(-1.0, 1.8, wpos.z + (n - 0.5) * 1.2) : 1.0;
	ALPHA = clamp(e, 0.0, 1.0) * fade;
}
"""
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("albedo_tex", tex(kind + "_albedo.png"))
		m.set_shader_parameter("normal_tex", tex(kind + "_normal.png"))
		m.set_shader_parameter("mode", mode)
		m.set_shader_parameter("gain", _gain(kind))
		m.set_shader_parameter("edge", 0.32 if mode == 0 else 0.9)
		m.set_shader_parameter("tile", 3.0 if kind == "road" else 4.0)
		return m)


## 木（幹は樹皮テクスチャ、葉は濃いめの緑にノイズと1本ごとの色ムラ）。
## メッシュの頂点カラー: rgb = 基本色、a = 0 なら樹皮・0.5 なら木口（切り口）・1 なら葉。
## MultiMesh のインスタンスカラーで1本ごとに葉の色を変える（頂点カラーに掛け合わされて COLOR に入る）。
static func tree(use_custom := true) -> ShaderMaterial:
	return _cached_mat("tree/%s" % use_custom, func() -> Material:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode cull_back;
uniform sampler2D bark_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D bark_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D leaf_noise : filter_linear_mipmap, repeat_enable;
uniform bool use_custom = true;
uniform float wind = 1.0;
varying vec3 lpos;
varying float leaf;
varying vec3 tint;
varying float ao;
void vertex() {
	lpos = VERTEX;
	leaf = COLOR.a;
	tint = vec3(1.0);
	// 葉のかたまりの下側・内側は暗く（簡易的な環境遮蔽）。幹は根元と樹冠の下を少し暗く
	if (leaf > 0.75) {
		ao = mix(0.62, 1.06, smoothstep(-0.7, 0.85, NORMAL.y));
	} else {
		ao = mix(0.72, 1.0, smoothstep(0.0, 0.35, VERTEX.y));
	}
	if (use_custom) {
		// 風で揺れる（高い所ほど大きく。木ごとに位相をずらす）。風向きはワールドの +X 寄り
		vec3 origin = MODEL_MATRIX[3].xyz;
		float ph = origin.x * 0.37 + origin.z * 0.23;
		float t = TIME * 1.25 + ph;
		float h = max(VERTEX.y, 0.0);
		float bend = (sin(t) * 0.65 + sin(t * 2.17 + 1.3) * 0.25 + 0.35) * h * h * 0.016 * wind;
		vec3 wdir = (vec4(1.0, 0.0, 0.4, 0.0) * MODEL_MATRIX).xyz;
		wdir /= max(dot(wdir, wdir), 0.0001);
		VERTEX += wdir * bend;
		// 葉のさざめき（位置だけで決めるので、面のつなぎ目は離れない）
		if (leaf > 0.75) {
			VERTEX.xz += sin(TIME * 3.7 + dot(VERTEX, vec3(4.1, 5.3, 3.7)) + ph) * 0.018 * wind;
		}
	}
}
void fragment() {
	if (leaf > 0.25 && leaf < 0.75) {
		// 木口（年輪）
		float r = length(lpos.xz);
		ALBEDO = COLOR.rgb * (0.88 + 0.12 * sin(r * 90.0));
		ROUGHNESS = 0.9;
	} else if (leaf <= 0.25) {
		vec2 uv = vec2(atan(lpos.x, lpos.z) * 0.477, lpos.y * 0.9);
		ALBEDO = COLOR.rgb * texture(bark_tex, uv).rgb * 1.15 * ao;
		NORMAL_MAP = texture(bark_nrm, uv).rgb;
		ROUGHNESS = 0.92;
	} else {
		float n = texture(leaf_noise, lpos.xz * 0.6 + vec2(lpos.y * 0.45)).r;
		float n2 = texture(leaf_noise, lpos.xz * 2.1 - vec2(lpos.y * 1.3)).r;
		vec3 col = COLOR.rgb * tint * (0.74 + 0.36 * n + 0.14 * (n2 - 0.5)) * ao;
		ALBEDO = col;
		ROUGHNESS = 0.8;
		SPECULAR = 0.3;
		// 輪郭がうっすら明るい（逆光で葉が透ける感じ）
		float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		EMISSION = col * rim * vec3(0.45, 0.5, 0.25);
	}
}
"""
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("bark_tex", tex("bark_albedo.png"))
		m.set_shader_parameter("bark_nrm", tex("bark_normal.png"))
		m.set_shader_parameter("leaf_noise", tex("leaf_noise.png"))
		m.set_shader_parameter("use_custom", use_custom)
		return m)


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
	vec3 origin = MODEL_MATRIX[3].xyz;
	float ph = origin.x * 0.9 + origin.z * 0.6;
	float sway = sin(TIME * 2.1 + ph) * 0.6 + sin(TIME * 3.3 + ph * 1.7) * 0.3 + 0.3;
	vec3 wdir = (vec4(0.93, 0.0, 0.37, 0.0) * MODEL_MATRIX).xyz;
	wdir /= max(dot(wdir, wdir), 0.0001);
	VERTEX += wdir * sway * h * h * 0.07;
}
void fragment() {
	vec3 c = base_color.a > 0.0 ? base_color.rgb : COLOR.rgb;
	ALBEDO = c * mix(0.55, 1.08, h);
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
}
"""
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("base_color", color)
		return m)


## 建物・小物用。kind: "paint"（塗装・プラスチック）/ "wood"（板材）/ "metal"（塗装金属）/ "roof"（波板）
static func surface(color: Color, kind := "paint", roughness := 0.8) -> StandardMaterial3D:
	return _cached_mat("surf/%s/%s/%.2f" % [color.to_html(), kind, roughness], func() -> Material:
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = roughness
		m.uv1_triplanar = true
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		match kind:
			"wood":
				m.albedo_texture = tex("wood_albedo.png")
				m.normal_enabled = true
				m.normal_texture = tex("wood_normal.png")
				m.normal_scale = 0.8
				m.uv1_scale = Vector3.ONE * 0.6
				m.roughness = 0.85
			"roof":
				# 塗装した波板（Poly Haven の corrugated_iron）。波は U 方向（X）に並ぶので、切妻屋根の斜面を流れる向きになる。
				# 屋根はまとめたメッシュで接線が無く法線マップが乱れるため、凹凸の陰影はカラーに焼き込んである
				m.albedo_texture = tex("roof_albedo.png")
				m.uv1_triplanar_sharpness = 12.0
				m.metallic = 0.4
				m.metallic_specular = 0.6
				m.uv1_scale = Vector3.ONE * 0.28
			"metal":
				m.albedo_texture = tex("paint_detail.png")
				m.roughness_texture = tex("metal_detail.png")
				m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
				m.roughness = 1.0
				m.metallic = 0.45
				m.metallic_specular = 0.6
				m.uv1_scale = Vector3.ONE * 0.8
			_:
				m.albedo_texture = tex("paint_detail.png")
				m.uv1_scale = Vector3.ONE * 0.5
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


## トラック: 元のカラーマップに、塗装金属らしいツヤとラフネスのムラを足す。
static func truck(texture: Texture2D) -> StandardMaterial3D:
	return _cached_mat("truck/%s" % texture.resource_path, func() -> Material:
		var m := StandardMaterial3D.new()
		m.albedo_texture = texture
		m.metallic = 0.35
		m.metallic_specular = 0.6
		m.roughness = 1.0
		m.roughness_texture = tex("metal_detail.png")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
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
