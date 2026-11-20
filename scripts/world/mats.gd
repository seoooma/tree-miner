class_name Mats
## 質感付きマテリアル（地面・木・建物・人物・トラック）。テクスチャは tools/make_textures.py で生成したもの。
## 同じ設定のマテリアルはキャッシュして使い回す。

const TEX := "res://assets/textures/"

static var _cache: Dictionary = {}


static func tex(name: String) -> Texture2D:
	return load(TEX + name) as Texture2D


static func _cached_mat(key: String, make: Callable) -> Material:
	if not _cache.has(key):
		_cache[key] = make.call()
	return _cache[key]


## 地面（草地 grass / 作業場 yard / 道 road）。ワールド座標でタイルする。tile は 1 枚が何 m か。
static func ground(kind: String, tint := Color.WHITE, tile := 4.0) -> StandardMaterial3D:
	return _cached_mat("ground/%s/%s/%.1f" % [kind, tint.to_html(), tile], func() -> Material:
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex(kind + "_albedo.png")
		m.albedo_color = tint
		m.normal_enabled = true
		m.normal_texture = tex(kind + "_normal.png")
		m.normal_scale = 0.9
		m.roughness = 0.95
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE / tile
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		return m)


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
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = wpos.xz / tile;
	ALBEDO = texture(albedo_tex, uv).rgb;
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	ROUGHNESS = 0.95;
	float n = texture(albedo_tex, uv * 0.37).g;
	float d = mode == 0 ? min(UV.x, 1.0 - UV.x) : UV.y;
	float e = d / edge + (n - 0.5) * 0.9;
	ALPHA = clamp(e, 0.0, 1.0);
}
"""
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("albedo_tex", tex(kind + "_albedo.png"))
		m.set_shader_parameter("normal_tex", tex(kind + "_normal.png"))
		m.set_shader_parameter("mode", mode)
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
varying vec3 lpos;
varying float leaf;
varying vec3 tint;
void vertex() {
	lpos = VERTEX;
	leaf = COLOR.a;
	tint = vec3(1.0);
}
void fragment() {
	if (leaf > 0.25 && leaf < 0.75) {
		float r = length(lpos.xz);
		ALBEDO = COLOR.rgb * (0.9 + 0.1 * sin(r * 90.0));
		ROUGHNESS = 0.9;
	} else if (leaf <= 0.25) {
		vec2 uv = vec2(atan(lpos.x, lpos.z) * 0.477, lpos.y * 0.9);
		ALBEDO = COLOR.rgb * texture(bark_tex, uv).rgb * 1.15;
		NORMAL_MAP = texture(bark_nrm, uv).rgb;
		ROUGHNESS = 0.92;
	} else {
		float n = texture(leaf_noise, lpos.xz * 0.6 + vec2(lpos.y * 0.45)).r;
		ALBEDO = COLOR.rgb * tint * (0.78 + 0.42 * n);
		ROUGHNESS = 0.8;
		SPECULAR = 0.3;
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


## 建物・小物用。kind: "paint"（塗装・プラスチック）/ "wood"（木目）/ "metal"（塗装金属）
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
				m.uv1_scale = Vector3.ONE * 0.9
				m.roughness = 0.85
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


## Kenney のキャラクター（紫のロボット風）を作業着の配色に塗り替えるシェーダー。
## part: 0 = 胴体（上は白シャツ、下はデニムのオーバーオール）, 1 = 腕（白シャツ）, 2 = 脚（デニム＋茶色のブーツ）
static func worker(texture: Texture2D, part: int) -> ShaderMaterial:
	return _cached_mat("worker/%d" % part, func() -> Material:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
uniform sampler2D tex : source_color, filter_linear;
uniform int part = 0;
varying vec3 lpos;
void vertex() { lpos = VERTEX; }
void fragment() {
	vec3 c = texture(tex, UV).rgb;
	float lum = dot(c, vec3(0.3, 0.55, 0.15));
	bool purple = c.b > c.g + 0.15 && c.r > c.g + 0.05;
	bool yellow = c.r > 0.8 && c.g > 0.5 && c.b < 0.45;
	vec3 shirt = vec3(0.93, 0.93, 0.9);
	vec3 denim = vec3(0.16, 0.27, 0.5);
	vec3 boots = vec3(0.32, 0.2, 0.11);
	vec3 skin = vec3(0.93, 0.72, 0.55);
	vec3 col = c;
	float shade = clamp(lum / 0.55, 0.6, 1.15);
	if (yellow) {
		col = skin * clamp(lum / 0.75, 0.7, 1.1);
	} else if (part == 0) {
		bool low = lpos.y < 0.27;
		if (purple || low) col = denim * shade;
		else if (lum > 0.6) col = shirt * clamp(lum, 0.8, 1.0);
	} else if (part == 1) {
		if (purple) col = shirt * clamp(lum * 1.6, 0.7, 1.0);
		else if (lum > 0.6) col = shirt * clamp(lum, 0.8, 1.0);
	} else {
		col = lpos.y < -0.11 ? boots * shade : denim * shade;
	}
	ALBEDO = col;
	ROUGHNESS = part == 2 && lpos.y < -0.11 ? 0.55 : 0.85;
}
"""
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("tex", texture)
		m.set_shader_parameter("part", part)
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
