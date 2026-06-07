extends Node2D
## 等距菱形网格地图渲染器 — 三国志11风格3D地形 v3
##
## 全程序化：山脉·森林·平原·沙漠·湿地·水域
## 3D光照模型 + 多层噪声 + 256px城堡模型 + 样条河流

# 渲染层
@onready var terrain_layer: Node2D = $TerrainLayer
@onready var overlay_layer: Node2D = $OverlayLayer
@onready var feature_layer: Node2D = $FeatureLayer
@onready var unit_layer: Node2D = $UnitLayer
@onready var ui_layer: Node2D = $UILayer
@onready var camera: Camera2D = $Camera2D

# 网格工具
var grid_utils: GridUtils = GridUtils.new()

# 纹理缓存
var _texture_cache: Dictionary = {}

# 渲染质量
const TEX_MUL: int = 2
const STEP: int = 2

# ============================================================
# 大地色板 — 低饱和自然色
# ============================================================

const TERRAIN_BASE: Dictionary = {
	"plain":        Color(0.588, 0.612, 0.353),
	"grassland":    Color(0.522, 0.576, 0.302),
	"forest":       Color(0.165, 0.341, 0.141),
	"dense_forest": Color(0.102, 0.251, 0.086),
	"hill":         Color(0.533, 0.482, 0.318),
	"mountain":     Color(0.424, 0.373, 0.290),
	"high_mountain":Color(0.396, 0.353, 0.306),
	"desert":       Color(0.753, 0.694, 0.459),
	"wetland":      Color(0.267, 0.420, 0.282),
	"water":        Color(0.137, 0.333, 0.522),
	"ocean":        Color(0.075, 0.239, 0.478),
}

const LIGHT_DIR_X: float = -0.577
const LIGHT_DIR_Y: float = -0.577
const AMBIENT: float = 0.30
const DIFFUSE: float = 0.70

var _terrain_sprites: Array = []
var _city_sprites: Dictionary = {}
var _army_sprites: Dictionary = {}
var _pass_sprites: Array = []
var _harbor_sprites: Array = []
var _county_overlay_sprites: Array = []


# ============================================================
# 初始化
# ============================================================

func _ready() -> void:
	_setup_layers()

	# 地图中心 ≈ 洛阳 (88, 65)，计算合适的原点使地图居中于视口
	var center_x = 88
	var center_y = 65
	# 先算未偏移的屏幕坐标
	var raw_cx = (center_x - center_y) * grid_utils.tile_half_w
	var raw_cy = (center_x + center_y) * grid_utils.tile_half_h
	# 目标是让这个点落在视口中央 (1920/2=960, 1080/2=540)
	grid_utils.setup(960 - raw_cx, 540 - raw_cy, DataManager.map_width, DataManager.map_height)

	if camera:
		camera.enabled = true
		# 相机位置 = 视口中心对应的世界坐标
		camera.position = Vector2(960, 540)
		camera.zoom = Vector2(1.0, 1.0)
	_connect_signals()


func _connect_signals() -> void:
	EventBus.map_city_clicked.connect(_on_city_clicked)
	EventBus.map_army_clicked.connect(_on_army_clicked)
	EventBus.map_vertex_clicked.connect(_on_vertex_clicked)


func _setup_layers() -> void:
	for layer_name in ["TerrainLayer", "OverlayLayer", "FeatureLayer", "UnitLayer", "UILayer"]:
		var layer = get_node_or_null(layer_name)
		if not layer:
			layer = Node2D.new()
			layer.name = layer_name
			add_child(layer)


# ============================================================
# 主渲染入口
# ============================================================

func render_full_map() -> void:
	print("MapRenderer: Rendering full 3D map v3...")
	var t0 = Time.get_ticks_msec()
	render_terrain()
	print("  Terrain: %dms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	render_county_overlays()
	render_rivers()
	render_roads()
	print("  Features: %dms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	render_cities()
	render_passes()
	render_harbors()
	render_resources()
	print("  Markers: %dms" % (Time.get_ticks_msec() - t0))
	print("MapRenderer: Done.")


# ============================================================
# 地形渲染
# ============================================================

func render_terrain() -> void:
	_clear_layer(terrain_layer)
	_terrain_sprites.clear()

	# 海洋大块背景
	var ocean_tex = _get_terrain_texture("ocean", 0)
	var ocean_step = 8
	for x in range(0, DataManager.map_width, ocean_step):
		for y in range(0, DataManager.map_height, ocean_step):
			if DataManager.get_terrain_at(x, y) != "ocean":
				continue
			var screen_pos = grid_utils.grid_to_screen(x, y, 0)
			var sprite = Sprite2D.new()
			sprite.texture = ocean_tex
			sprite.position = screen_pos
			sprite.z_index = -100
			sprite.scale = Vector2(ocean_step, ocean_step)
			terrain_layer.add_child(sprite)

	# 陆地地形
	for x in range(0, DataManager.map_width, STEP):
		for y in range(0, DataManager.map_height, STEP):
			var terrain = DataManager.get_terrain_at(x, y)
			if terrain == "ocean":
				continue

			var height = DataManager.get_height_at(x, y)
			var texture = _get_terrain_texture(terrain, height)
			var screen_pos = grid_utils.grid_to_screen(x, y, height)

			var sprite = Sprite2D.new()
			sprite.texture = texture
			sprite.position = screen_pos
			sprite.z_index = y + height * 2
			if STEP > 1:
				sprite.scale = Vector2(STEP, STEP)
			terrain_layer.add_child(sprite)
			_terrain_sprites.append(sprite)

	print("MapRenderer: %d terrain sprites (step=%d)" % [_terrain_sprites.size(), STEP])


func _get_terrain_texture(terrain: String, height: int) -> ImageTexture:
	var key = "%s_h%d" % [terrain, height]
	if key in _texture_cache:
		return _texture_cache[key]
	var texture = _make_terrain_texture(terrain, height)
	_texture_cache[key] = texture
	return texture


# ============================================================
# 核心：3D地形纹理生成 (v3 — 多层噪声 + 自然纹理)
# ============================================================

func _make_terrain_texture(terrain: String, height: int) -> ImageTexture:
	var hw = int(grid_utils.tile_half_w)
	var hh = int(grid_utils.tile_half_h)

	var tw = (hw * 2 + 8) * TEX_MUL
	var th = (hh * 2 + 8) * TEX_MUL
	var image = Image.create(tw, th, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)

	var cx = float(tw) / 2.0
	var cy = float(th) / 2.0
	var rx = float(hw) * TEX_MUL
	var ry = float(hh) * TEX_MUL

	# 确定性随机种子
	var rng = RandomNumberGenerator.new()
	rng.seed = terrain.hash() + height * 131

	# 多层噪声LUT
	var nsize = tw * th
	var n0: Array = []; n0.resize(nsize)  # 粗噪声
	var n1: Array = []; n1.resize(nsize)  # 细噪声
	var n2: Array = []; n2.resize(nsize)  # 微粒噪声
	for i in range(nsize):
		n0[i] = rng.randf()
		n1[i] = rng.randf()
		n2[i] = rng.randf()

	# 山峰数据（仅山地类使用）
	var peaks: Array = []
	if terrain in ["mountain", "high_mountain"]:
		var np = 5 + rng.randi() % 4
		for pi in range(np):
			peaks.append({
				px = cx + (rng.randf() - 0.5) * rx * 1.7,
				py = cy + (rng.randf() - 0.5) * ry * 1.7,
				size = rng.randf_range(0.22, 0.65),
				sharp = rng.randf_range(0.7, 1.6),
			})
	elif terrain in ["hill"]:
		var np = 2 + rng.randi() % 3
		for pi in range(np):
			peaks.append({
				px = cx + (rng.randf() - 0.5) * rx * 0.9,
				py = cy + (rng.randf() - 0.5) * ry * 0.9,
				size = rng.randf_range(0.3, 0.6),
				sharp = rng.randf_range(0.35, 0.75),
			})

	var hbright = clampf(height * 0.02, 0.0, 0.2)

	for px in range(tw):
		for py in range(th):
			var dx = abs(px - cx) / rx
			var dy = abs(py - cy) / ry
			var dist = dx + dy
			if dist > 1.0: continue

			var edge = 1.0 - smoothstep(0.85, 1.0, dist)
			var nx = (px - cx) / rx
			var ny = (py - cy) / ry

			var i0 = (px * 13 + py * 29) % nsize
			var i1 = (px * 37 + py * 17) % nsize
			var i2 = (px * 53 + py * 41) % nsize
			var nc = n0[i0]       # coarse
			var nf = n1[i1]       # fine
			var ng = n2[i2]       # grain

			var col: Color

			match terrain:
				"mountain", "high_mountain":
					col = _mtn(px, py, nx, ny, nc, nf, ng, peaks, rng, terrain, rx, ry)
				"hill":
					col = _hill(px, py, nx, ny, nc, nf, peaks, rng, rx, ry)
				"forest", "dense_forest":
					col = _forest(px, py, dist, nc, nf, ng, rng, terrain)
				"plain", "grassland":
					col = _plain(px, py, dist, nx, ny, nc, nf, rng, terrain)
				"water":
					col = _water(px, py, nx, ny, nc, nf, edge)
				"ocean":
					col = _ocean(px, py, nx, ny, nc, nf, edge)
				"desert":
					col = _desert(px, py, nx, ny, nc, nf, ng)
				"wetland":
					col = _wetland(px, py, nc, nf, ng, rng)
				_:
					col = TERRAIN_BASE.get(terrain, Color.GRAY)

			if hbright > 0 and terrain not in ["water", "ocean"]:
				col = col.lightened(hbright)
			col.a = edge
			image.set_pixel(px, py, col)

	return ImageTexture.create_from_image(image)


# ============================================================
# 像素着色函数 (v3 — 更自然，更少塑料感)
# ============================================================

func _mtn(px: float, py: float, nx: float, ny: float,
		nc: float, nf: float, ng: float, peaks: Array,
		rng: RandomNumberGenerator, terrain: String,
		rx: float, ry: float) -> Color:

	var peak_h = 0.0
	var gx = 0.0; var gy = 0.0
	for pi in range(peaks.size()):
		var pk = peaks[pi]
		var pdx = (px - pk.px) / (rx * pk.size)
		var pdy = (py - pk.py) / (ry * pk.size)
		var pkd = sqrt(pdx * pdx + pdy * pdy)
		var pkv = 1.0 - clampf(pkd, 0.0, 1.0)
		pkv = pow(pkv, pk.sharp)
		if pkv > peak_h:
			peak_h = pkv
			if pkd > 0.005:
				gx = pdx / pkd
				gy = pdy / pkd

	# 岩石基色
	var rock: Color
	if terrain == "high_mountain":
		rock = Color(0.44, 0.40, 0.35).lerp(Color(0.52, 0.47, 0.38), nc * 0.45)
	else:
		rock = Color(0.48, 0.42, 0.32).lerp(Color(0.55, 0.49, 0.37), nc * 0.45)

	# 细噪岩纹
	var grain = (nf - 0.5) * 0.10 + (ng - 0.5) * 0.06
	rock = Color(
		clampf(rock.r + grain, 0, 1),
		clampf(rock.g + grain, 0, 1),
		clampf(rock.b + grain * 0.7, 0, 1)
	)

	# 3D光照
	var light = _light(gx, gy, peak_h) * 0.55 + 0.45 * peak_h
	var col = rock.darkened(0.38).lerp(rock.lightened(0.22), clampf(light, 0.0, 1.0))

	# 雪顶
	if peak_h > 0.62:
		var snow = clampf((peak_h - 0.62) / 0.38, 0.0, 1.0)
		var flat = 1.0 - clampf(abs(gx) + abs(gy), 0.0, 1.0)
		snow *= 0.35 + flat * 0.65
		var sc = Color(0.90, 0.88, 0.92)
		var sl = _light(gx, gy, 1.0)
		sc = sc.darkened(0.2).lerp(sc.lightened(0.08), sl)
		col = col.lerp(sc, snow)

	# 山脊暗线
	if peak_h > 0.40 and peak_h < 0.55 and ng > 0.78:
		col = col.darkened(0.22)

	# 岩裂缝
	if peak_h < 0.28 and nf > 0.72 and ng < 0.28:
		col = col.darkened(0.30)

	# 山脚绿意
	if peak_h < 0.18:
		var gmix = (0.18 - peak_h) / 0.18
		col = col.lerp(Color(0.38, 0.50, 0.24), gmix * 0.35)

	return col


func _hill(px: float, py: float, nx: float, ny: float,
		nc: float, nf: float, peaks: Array,
		rng: RandomNumberGenerator, rx: float, ry: float) -> Color:

	var hh = 0.0; var gx = 0.0; var gy = 0.0
	for pi in range(peaks.size()):
		var pk = peaks[pi]
		var pdx = (px - pk.px) / (rx * pk.size)
		var pdy = (py - pk.py) / (ry * pk.size)
		var pkd = sqrt(pdx * pdx + pdy * pdy)
		var pkv = 1.0 - clampf(pkd, 0.0, 1.0)
		pkv = pow(pkv, pk.sharp * 1.1)
		if pkv > hh:
			hh = pkv
			if pkd > 0.005:
				gx = pdx / pkd
				gy = pdy / pkd

	var green = Color(0.50, 0.56, 0.32)
	var brown = Color(0.48, 0.40, 0.26)
	var mixed = green.lerp(brown, hh * 0.55)
	mixed = mixed.lerp(Color(0.46, 0.52, 0.34), nc * 0.3)

	var light = _light(gx, gy, hh) * 0.45 + 0.55
	var col = mixed.darkened(0.18).lerp(mixed.lightened(0.12), light)
	col = col.lightened((nf - 0.5) * 0.05)
	return col


func _forest(px: float, py: float, dist: float,
		nc: float, nf: float, ng: float,
		rng: RandomNumberGenerator, terrain: String) -> Color:

	var dg = Color(0.10, 0.24, 0.08)
	var mg = Color(0.16, 0.33, 0.13)
	var lg = Color(0.23, 0.42, 0.18)
	if terrain == "dense_forest":
		dg = Color(0.07, 0.18, 0.06)
		mg = Color(0.12, 0.27, 0.10)
		lg = Color(0.17, 0.32, 0.12)

	var cs = 5.5 if terrain == "dense_forest" else 7.0
	var ci = int(px / cs)
	var cj = int(py / cs)
	var tr = RandomNumberGenerator.new()
	tr.seed = ci * 997 + cj

	var tx = ci * cs + tr.randf() * cs
	var ty = cj * cs + tr.randf() * cs
	var tr_r = cs * (0.45 + tr.randf() * 0.55)
	var td = sqrt((px - tx) * (px - tx) + (py - ty) * (py - ty)) / tr_r
	var th = 0.0
	if td < 1.0:
		th = 1.0 - td * td

	var col = dg
	if th > 0.55:
		var tl = 0.5
		if th > 0.3:
			var tdx = (px - tx) / tr_r
			var tdy = (py - ty) / tr_r
			tl = clampf(-(tdx * 0.55 + tdy * 0.45) + 0.5, 0.0, 1.0)
		col = mg.lerp(lg, (th - 0.55) / 0.45)
		col = col.darkened(0.22).lerp(col.lightened(0.28), tl)
	elif th > 0.15:
		col = dg.lerp(mg, (th - 0.15) / 0.40)
	else:
		col = dg
		if nc > 0.88:
			col = col.lightened(0.12)

	# 全局微噪
	col = col.lightened((nf - 0.5) * 0.07)
	# 偶尔枯树
	if ng > 0.94:
		col = col.lerp(Color(0.35, 0.25, 0.12), 0.3)

	return col


func _plain(px: float, py: float, dist: float, nx: float, ny: float,
		nc: float, nf: float, rng: RandomNumberGenerator,
		terrain: String) -> Color:

	var base = TERRAIN_BASE.get(terrain, Color(0.55, 0.60, 0.32))

	# 田埂纹理
	var field = sin(px * 0.10 + py * 0.03) * 0.025 + sin(px * 0.05 - py * 0.08) * 0.03
	# 作物色块
	var patch = floor(px / 18.0) * 11.0 + floor(py / 18.0) * 7.0
	var pr = RandomNumberGenerator.new()
	pr.seed = int(patch)
	var pv = pr.randf_range(-0.035, 0.035)

	var col = base.lightened(field + pv)
	# 细微噪点（模拟草丛）
	col = col.lightened((nf - 0.5) * 0.04)

	# 柔和光照
	var lg = clampf(-(nx * 0.10 + ny * 0.10) + 0.5, 0.0, 1.0)
	col = col.darkened(0.03).lerp(col.lightened(0.03), lg)

	return col


func _water(px: float, py: float, nx: float, ny: float,
		nc: float, nf: float, edge: float) -> Color:
	var deep = Color(0.09, 0.24, 0.44)
	var mid = Color(0.13, 0.32, 0.52)
	var shallow = Color(0.18, 0.40, 0.60)

	var w1 = sin(px * 0.05 + py * 0.035) * 0.5
	var w2 = sin(px * 0.09 - py * 0.07) * 0.3
	var w3 = sin(px * 0.035 + py * 0.06) * cos(py * 0.025) * 0.2
	var wave = (w1 + w2 + w3) * 0.4 + 0.5

	var col = deep.lerp(mid, clampf(wave + 0.25, 0.0, 1.0))
	col = col.lerp(shallow, clampf((wave - 0.45) * 2.5, 0.0, 1.0))

	var shore = clampf((1.0 - (abs(nx) + abs(ny))) * 0.55, 0.0, 1.0)
	col = col.lerp(shallow, shore * 0.25)

	if nf > 0.93:
		col = col.lightened(0.13)

	return col


func _ocean(px: float, py: float, nx: float, ny: float,
		nc: float, nf: float, edge: float) -> Color:

	var abyss = Color(0.04, 0.16, 0.36)
	var deep = Color(0.06, 0.22, 0.44)
	var mid = Color(0.09, 0.28, 0.50)

	var s1 = sin(px * 0.012 + py * 0.010) * 0.5
	var s2 = sin(px * 0.022 - py * 0.018) * 0.3
	var s3 = sin(px * 0.007 + py * 0.016) * cos(py * 0.008) * 0.2
	var swell = (s1 + s2 + s3) * 0.4 + 0.5

	var col = abyss.lerp(deep, swell)
	col = col.lerp(mid, clampf((swell - 0.45) * 2.0, 0.0, 1.0))

	var shore = clampf((1.0 - (abs(nx) + abs(ny))) * 0.5, 0.0, 1.0)
	col = col.lerp(mid, shore * 0.22)

	if nf > 0.945:
		col = col.lightened(0.10)

	return col


func _desert(px: float, py: float, nx: float, ny: float,
		nc: float, nf: float, ng: float) -> Color:

	var sl = Color(0.82, 0.76, 0.50)
	var sm = Color(0.74, 0.67, 0.40)
	var sd = Color(0.66, 0.58, 0.34)

	var d1 = sin(px * 0.025 + py * 0.04) * 0.5
	var d2 = sin(px * 0.05 - py * 0.025) * 0.3
	var dune = (d1 + d2) * 0.4 + 0.5

	var col = sd.lerp(sm, dune)
	col = col.lerp(sl, clampf((dune - 0.55) * 3.0, 0.0, 1.0))

	# 沙粒纹理
	col = col.lightened((ng - 0.5) * 0.07)
	# 风吹纹
	var ripple = sin(px * 0.07 + py * 0.07) * 0.02
	col = col.lightened(ripple)

	var light = clampf(-(nx * 0.18 + ny * 0.18) + 0.5, 0.0, 1.0)
	col = col.darkened(0.08).lerp(col.lightened(0.08), light)

	return col


func _wetland(px: float, py: float, nc: float, nf: float, ng: float,
		rng: RandomNumberGenerator) -> Color:

	var land = Color(0.22, 0.36, 0.24)
	var water = Color(0.14, 0.26, 0.38)
	var reed = Color(0.28, 0.42, 0.20)

	var wp = sin(px * 0.04 + py * 0.025) * 0.5 + sin(px * 0.07 - py * 0.05) * 0.3
	var wet = clampf((wp + nc * 0.3), 0.0, 1.0)

	var col = land.lerp(water, wet * 0.65)
	if nf > 0.55:
		col = col.lerp(reed, (nf - 0.55) * 0.45)
	if wet > 0.45 and ng > 0.91:
		col = col.lightened(0.08)

	return col


# ============================================================
# 光照
# ============================================================

func _light(gx: float, gy: float, h: float) -> float:
	var hs = h * 2.8
	var nx_n = -gx * hs
	var ny_n = -gy * hs
	var nz_n = 1.0
	var mag = sqrt(nx_n * nx_n + ny_n * ny_n + nz_n * nz_n)
	if mag < 0.001: return 0.5
	nx_n /= mag; ny_n /= mag; nz_n /= mag
	var diff = nx_n * LIGHT_DIR_X + ny_n * LIGHT_DIR_Y + nz_n * 0.35
	return AMBIENT + maxf(diff, 0.0) * DIFFUSE


# ============================================================
# 城堡模型 — 256x256 大型城池 (v3)
# ============================================================

func _make_castle_texture(color: Color, importance: int = 0) -> ImageTexture:
	# 率土之滨风格 — 自然材质、等距建筑、多层屋顶、石材城墙
	var S = 384
	var img = Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var cx = S / 2.0
	var cy = S / 2.0 + 24

	# === 自然色板 (中国传统建筑色) ===
	var roof_main = Color(0.22, 0.24, 0.30)      # 青灰瓦顶
	var roof_light = Color(0.28, 0.30, 0.36)      # 亮面瓦
	var roof_dark = Color(0.16, 0.18, 0.24)        # 暗面瓦
	var wall_stone = Color(0.52, 0.50, 0.46)       # 灰石城墙
	var wall_dark = Color(0.40, 0.38, 0.35)
	var wall_light = Color(0.62, 0.60, 0.55)
	var plaster = Color(0.78, 0.74, 0.68)          # 白灰墙
	var plaster_d = Color(0.68, 0.64, 0.58)
	var wood_d = Color(0.28, 0.18, 0.10)           # 深木色
	var wood_l = Color(0.38, 0.26, 0.15)
	var gate_c = Color(0.50, 0.18, 0.12)           # 朱红门
	var ground = Color(0.28, 0.24, 0.18)           # 土地
	var path_c = Color(0.45, 0.40, 0.32)           # 石板路
	var water_c = Color(0.08, 0.20, 0.38, 0.7)     # 护城河
	var green_t = Color(0.25, 0.45, 0.22)          # 庭院树
	var bronze = Color(0.55, 0.42, 0.22)           # 青铜色

	# 城池规模
	var sc = 0.85 + importance * 0.3
	var TW = int(22 * sc)    # 塔宽
	var TH = int(36 * sc)    # 塔高
	var WW = int(72 * sc)    # 城墙宽
	var WH = int(20 * sc)    # 城墙高

	var wall_l = cx - WW / 2.0
	var wall_r = cx + WW / 2.0
	var wall_t = cy - TH * 0.8
	var wall_b = cy + WH * 0.3

	# 角楼位置
	var towers = [
		[wall_l + TW / 2.0, wall_t + TW / 3.0],
		[wall_r - TW / 2.0, wall_t + TW / 3.0],
		[wall_l + TW / 2.0, wall_b - TW / 3.0],
		[wall_r - TW / 2.0, wall_b - TW / 3.0],
	]

	# ===== PASS 1: 护城河 + 地面 =====
	for px in range(S):
		for py in range(S):
			# 护城河
			var mdx = (px - cx) / float(WW * 0.82)
			var mdy = (py - cy - 10) / float(WH * 2.2)
			var md = sqrt(mdx * mdx + mdy * mdy)
			if md > 0.90 and md < 1.12 and py > cy - TH * 0.3:
				var ma = (1.0 - abs(md - 1.01) / 0.11) * 0.65
				img.set_pixel(px, py, Color(water_c.r, water_c.g, water_c.b, ma))

			# 城外地面
			var odx = (px - cx) / float(WW * 0.95)
			var ody = (py - cy - 8) / float(WH * 2.6)
			var od = sqrt(odx * odx + ody * ody)
			if od < 0.88 and py > cy - 20:
				img.set_pixel(px, py, ground.lightened(0.1))

	# ===== PASS 2: 建筑 =====
	for px in range(S):
		for py in range(S):
			var col = Color.TRANSPARENT

			# 地面阴影
			var gdx = (px - cx) / float(WW * 0.72)
			var gdy = (py - cy - 15) / float(WH * 1.8)
			var gd = sqrt(gdx * gdx + gdy * gdy)
			if gd < 1.0 and py > cy - 15:
				var ga = (1.0 - gd) * 0.4
				col = Color(0.08, 0.06, 0.04, ga)

			# === 四座角楼 (双层屋顶) ===
			for t in towers:
				var tx = t[0]; var ty = t[1]
				if abs(px - tx) < TW / 2.0 and py >= ty - TH * 0.1 and py < ty + TH * 0.85:
					var rx0 = (px - tx) / (TW / 2.0)
					var ry0 = (py - ty + TH * 0.1) / (TH * 0.95)

					if ry0 < 0.18:
						# 上层屋顶
						var arc = 1.0 - abs(rx0) * 1.2
						if ry0 > (0.18 - arc * 0.18):
							var rl = clampf(0.5 - rx0 * 0.5, 0.0, 1.0)
							col = roof_dark.lerp(roof_light, rl)
					elif ry0 < 0.24:
						# 屋顶下檐
						col = wood_d
					elif ry0 < 0.40:
						# 下层屋顶
						var arc = 1.0 - abs(rx0) * 1.3
						if ry0 > (0.40 - arc * 0.16):
							var rl = clampf(0.5 - rx0 * 0.5, 0.0, 1.0)
							col = roof_dark.lerp(roof_light, rl)
					elif ry0 < 0.75:
						# 塔身
						var sl = clampf(0.5 - rx0 * 0.35, 0.0, 1.0)
						col = wall_dark.lerp(wall_light, sl)
						# 垛口
						if ry0 < 0.46 and int((px - tx + TW / 2.0) / 3.0) % 2 == 0:
							col = wall_stone
						# 箭窗
						if ry0 > 0.52 and ry0 < 0.62 and abs(rx0) < 0.22:
							col = Color(0.04, 0.02, 0.01)
					else:
						col = wall_dark.darkened(0.15)

			# === 城墙 (上/下两段) ===
			# 上城墙
			if px >= wall_l + TW / 2.0 and px <= wall_r - TW / 2.0 and py >= wall_t and py < wall_t + WH * 0.55:
				var ry0 = (py - wall_t) / (WH * 0.55)
				if ry0 < 0.40:
					var m = int((px - wall_l) / 4.0) % 3
					if m == 0: col = wall_stone
					elif m == 1: col = wall_dark
					else: col = wall_light
				else:
					col = wall_stone
			# 下城墙
			if px >= wall_l + TW / 2.0 and px <= wall_r - TW / 2.0 and py >= wall_b - WH * 0.45 and py < wall_b:
				col = wall_stone.darkened(0.08)

			# === 前门楼 (下方中央) ===
			var gw = TW * 1.4; var gh = WH * 1.6
			var gx = cx; var gy = wall_b - gh * 0.3
			if abs(px - gx) < gw / 2.0 and py >= gy and py < gy + gh:
				var rx0 = (px - gx) / (gw / 2.0)
				var ry0 = (py - gy) / gh
				if ry0 < 0.22:
					var arc = 1.0 - abs(rx0) * 1.4
					if ry0 > (0.22 - arc * 0.22):
						var rl = clampf(0.5 - rx0 * 0.5, 0.0, 1.0)
						col = roof_dark.lerp(roof_light, rl)
				elif ry0 < 0.35:
					col = wood_d
				elif abs(rx0) < 0.42 and ry0 < 0.72:
					col = Color(0.03, 0.02, 0.01)
				elif abs(rx0) < 0.55 and ry0 < 0.38:
					col = gate_c
				else:
					var sl = clampf(0.5 - rx0 * 0.35, 0.0, 1.0)
					col = wall_dark.lerp(wall_light, sl)

			# === 后门楼 ===
			var bgx = cx; var bgy = wall_t - gh * 0.3
			if abs(px - bgx) < gw * 0.65 / 2.0 and py >= bgy and py < bgy + gh * 0.65:
				var rx0 = (px - bgx) / (gw * 0.65 / 2.0)
				var ry0 = (py - bgy) / (gh * 0.65)
				if ry0 < 0.25:
					var arc = 1.0 - abs(rx0) * 1.3
					if ry0 > (0.25 - arc * 0.25):
						var rl = clampf(0.5 - rx0 * 0.5, 0.0, 1.0)
						col = roof_dark.lerp(roof_light, rl)
				elif abs(rx0) < 0.38 and ry0 < 0.65:
					col = Color(0.03, 0.02, 0.01)

			# === 庭院石板路 ===
			var cy_top = wall_t + WH * 0.6
			var cy_bot = wall_b - WH * 0.5
			if abs(px - cx) < TW * 0.35 and py >= cy_top and py < cy_bot:
				col = path_c

			# === 主殿 (中央偏上, 最大建筑) ===
			var mx = cx - TW * 1.2
			var mw = TW * 2.4
			var mh = TH * 0.7
			var my = cy_top - mh * 0.8
			if px >= mx and px < mx + mw and py >= my and py < my + mh:
				var rx0 = (px - mx) / mw
				var ry0 = (py - my) / mh
				if ry0 < 0.26:
					# 屋顶 — 宽大青灰瓦
					var rl = clampf(0.5 - (rx0 - 0.5) * 0.65, 0.0, 1.0)
					col = roof_dark.lerp(roof_light, rl)
					# 屋脊
					if ry0 > 0.16 and ry0 < 0.30 and abs(rx0 - 0.5) < 0.40:
						col = bronze
					# 鸱吻 (屋脊两端装饰)
					if ry0 < 0.22 and (abs(rx0 - 0.08) < 0.06 or abs(rx0 - 0.92) < 0.06):
						col = bronze.lightened(0.15)
				elif ry0 < 0.80:
					var sl = clampf(0.5 - (rx0 - 0.5) * 0.35, 0.0, 1.0)
					col = plaster_d.lerp(plaster, sl)
					# 红柱
					if (abs(rx0 - 0.10) < 0.025 or abs(rx0 - 0.90) < 0.025) and ry0 > 0.26:
						col = gate_c
					# 窗
					if abs(rx0 - 0.35) < 0.05 and ry0 > 0.45 and ry0 < 0.62:
						col = Color(0.05, 0.03, 0.02)
					if abs(rx0 - 0.65) < 0.05 and ry0 > 0.45 and ry0 < 0.62:
						col = Color(0.05, 0.03, 0.02)
				else:
					col = wall_stone.darkened(0.15)

			# 台基
			if px >= mx - 6 and px < mx + mw + 6 and py >= my + mh - 4 and py < my + mh + 6:
				col = wall_stone

			# === 左配殿 ===
			var lx = mx - TW * 1.0
			var lw = TW * 0.9
			var lh = TH * 0.45
			var ly = my + mh * 0.3
			if px >= lx and px < lx + lw and py >= ly and py < ly + lh:
				var rx0 = (px - lx) / lw
				var ry0 = (py - ly) / lh
				if ry0 < 0.26:
					var rl = clampf(0.5 - (rx0 - 0.5) * 0.5, 0.0, 1.0)
					col = roof_dark.lerp(roof_light, rl)
				elif ry0 < 0.78:
					var sl = clampf(0.5 - (rx0 - 0.5) * 0.3, 0.0, 1.0)
					col = plaster_d.lerp(plaster, sl)

			# === 右配殿 ===
			var rrx = mx + mw + TW * 0.1
			if px >= rrx and px < rrx + lw and py >= ly and py < ly + lh:
				var rx0 = (px - rrx) / lw
				var ry0 = (py - ly) / lh
				if ry0 < 0.26:
					var rl = clampf(0.5 - (rx0 - 0.5) * 0.5, 0.0, 1.0)
					col = roof_dark.lerp(roof_light, rl)
				elif ry0 < 0.78:
					var sl = clampf(0.5 - (rx0 - 0.5) * 0.3, 0.0, 1.0)
					col = plaster_d.lerp(plaster, sl)

			# === 后殿 ===
			var bx3 = cx - TW * 1.0
			var bw3 = TW * 2.0
			var bh3 = TH * 0.32
			var by3 = my - bh3 * 1.2
			if px >= bx3 and px < bx3 + bw3 and py >= by3 and py < by3 + bh3:
				var rx0 = (px - bx3) / bw3
				var ry0 = (py - by3) / bh3
				if ry0 < 0.30:
					var rl = clampf(0.5 - (rx0 - 0.5) * 0.5, 0.0, 1.0)
					col = roof_dark.lerp(roof_light, rl)
				else:
					col = plaster_d

			# === 庭院树 (两棵, 左右对称) ===
			for tree in [[cx - TW * 0.8, my + mh * 0.15], [cx + TW * 0.8, my + mh * 0.15]]:
				var tcx = tree[0]; var tcy = tree[1]
				var tr = TW * 0.35
				if sqrt((px - tcx) * (px - tcx) + (py - tcy) * (py - tcy)) < tr:
					var td = sqrt((px - tcx) * (px - tcx) + (py - tcy) * (py - tcy)) / tr
					if td < 0.6:
						col = green_t.lightened(0.2)
					elif td < 0.85:
						col = green_t
					else:
						col = green_t.darkened(0.3)
				# 树干
				if abs(px - tcx) < 2.5 and py >= tcy and py < tcy + tr * 0.6:
					col = wood_d

			# === 旗杆 + 旗 (角楼顶) ===
			for t in towers:
				var fx = t[0]; var fy = t[1] - TH * 0.15
				# 旗杆
				if abs(px - fx) < 1.5 and py >= fy - 16 and py < fy + 4:
					col = wood_d
				# 红旗
				if abs(px - fx) < 4 and py >= fy - 15 and py < fy - 2:
					if px >= fx - 1:
						col = gate_c

			# 应用
			if col.a > 0:
				var ex = img.get_pixel(px, py)
				if ex.a > 0:
					col = ex.lerp(col, col.a)
					col.a = maxf(ex.a, col.a)
				img.set_pixel(px, py, col)

	return ImageTexture.create_from_image(img)


# ============================================================
# 菱形标记
# ============================================================

func _make_diamond_texture(color: Color, _height: int) -> ImageTexture:
	var hw = int(grid_utils.tile_half_w)
	var hh = int(grid_utils.tile_half_h)
	var w = hw * 2 + 4
	var h = hh * 2 + 4
	var image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var cx = float(w) / 2.0
	var cy = float(h) / 2.0
	var rx = float(hw)
	var ry = float(hh)
	for px in range(w):
		for py in range(h):
			var dx = abs(px - cx) / rx
			var dy = abs(py - cy) / ry
			var dist = dx + dy
			if dist > 1.0: continue
			var edge = 1.0 - smoothstep(0.82, 1.0, dist)
			var col = color
			col.a = edge * color.a
			image.set_pixel(px, py, col)
	return ImageTexture.create_from_image(image)


# ============================================================
# 郡域覆盖
# ============================================================

func render_county_overlays() -> void:
	_clear_layer(overlay_layer)
	_county_overlay_sprites.clear()
	for city in GameManager.cities.values():
		if not city.is_owned(): continue
		var faction = GameManager.get_faction(city.faction_id)
		if not faction: continue
		var fc = faction.color
		var oc = Color(fc.r, fc.g, fc.b, 0.15)
		for county in city.counties:
			var center = county.center if county.center != Vector2i.ZERO else city.position
			var sp = grid_utils.grid_to_screen(center.x, center.y, DataManager.get_height_at(center.x, center.y))
			var sprite = Sprite2D.new()
			sprite.texture = _make_diamond_texture(oc, 0)
			sprite.position = sp
			sprite.z_index = center.y + 1
			sprite.scale = Vector2(1.5, 1.5)
			overlay_layer.add_child(sprite)
			_county_overlay_sprites.append(sprite)


# ============================================================
# 河流 — Catmull-Rom样条平滑 + 变宽 + 4层
# ============================================================

func render_rivers() -> void:
	var rivers = DataManager.get_all_rivers()
	for river in rivers:
		var raw_path: Array = river.get("path", [])
		if raw_path.size() < 2: continue

		# Catmull-Rom 样条插值 → 平滑曲线 (更多插值点)
		var pts: Array = []
		for i in range(raw_path.size()):
			var p = raw_path[i]
			pts.append(Vector2(p[0] if typeof(p) == TYPE_ARRAY else p.x,
							   p[1] if typeof(p) == TYPE_ARRAY else p.y))

		var smooth_path: Array = _catmull_rom_spline(pts, 12)
		if smooth_path.size() < 2: continue

		# 河流宽度 ×45 → width=3(长江)=135px≈2格, width=2(黄河)=90px≈1.4格
		var base_w = river.get("width", 2) * 45.0

		# 沿河宽度变化
		var n_seg = smooth_path.size() - 1
		for i in range(n_seg):
			var p1 = smooth_path[i]
			var p2 = smooth_path[i + 1]
			var h1 = DataManager.get_height_at(int(p1.x), int(p1.y))
			var h2 = DataManager.get_height_at(int(p2.x), int(p2.y))
			var sp1 = grid_utils.grid_to_screen(int(p1.x), int(p1.y), h1)
			var sp2 = grid_utils.grid_to_screen(int(p2.x), int(p2.y), h2)

			# 中段最宽，两端收窄
			var t = float(i) / float(maxi(1, n_seg))
			var wf = 1.0 - (t - 0.5) * (t - 0.5) * 1.3
			var w = base_w * clampf(wf, 0.65, 1.15)

			# 5层河流: 外岸土→内岸草→浅水→深水→河心高光
			_draw_segment(feature_layer, sp1, sp2, Color(0.28, 0.22, 0.14, 0.9), w + 14, 5)   # 外岸
			_draw_segment(feature_layer, sp1, sp2, Color(0.18, 0.30, 0.16, 0.85), w + 7, 6)   # 内岸植被
			_draw_segment(feature_layer, sp1, sp2, Color(0.12, 0.28, 0.50, 0.8), w + 2, 7)    # 浅水
			_draw_segment(feature_layer, sp1, sp2, Color(0.15, 0.35, 0.58, 0.85), w, 8)       # 深水
			_draw_segment(feature_layer, sp1, sp2, Color(0.22, 0.48, 0.72, 0.45), w * 0.25, 9) # 河心


func _catmull_rom_spline(pts: Array, subdiv: int) -> Array:
	# 返回 Vector2 数组的平滑路径
	if pts.size() < 2: return pts
	var result: Array = [pts[0]]
	for i in range(pts.size() - 1):
		var p0 = pts[maxi(0, i - 1)]
		var p1 = pts[i]
		var p2 = pts[i + 1]
		var p3 = pts[mini(pts.size() - 1, i + 2)]
		for j in range(1, subdiv + 1):
			var t = float(j) / float(subdiv)
			var tt = t * t; var ttt = tt * t
			var x = 0.5 * ((2.0 * p1.x) +
				(-p0.x + p2.x) * t +
				(2.0 * p0.x - 5.0 * p1.x + 4.0 * p2.x - p3.x) * tt +
				(-p0.x + 3.0 * p1.x - 3.0 * p2.x + p3.x) * ttt)
			var y = 0.5 * ((2.0 * p1.y) +
				(-p0.y + p2.y) * t +
				(2.0 * p0.y - 5.0 * p1.y + 4.0 * p2.y - p3.y) * tt +
				(-p0.y + 3.0 * p1.y - 3.0 * p2.y + p3.y) * ttt)
			result.append(Vector2(x, y))
	result.append(pts[pts.size() - 1])
	return result


func _draw_segment(parent: Node2D, p1: Vector2, p2: Vector2, color: Color, width: float, z: int) -> void:
	var mid_y = (p1.y + p2.y) / 2.0  # approximate
	var line = Line2D.new()
	line.points = PackedVector2Array([p1, p2])
	line.width = width
	line.default_color = color
	line.z_index = int(mid_y / 32.0) + z  # rough y-based z
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	parent.add_child(line)


# ============================================================
# 道路
# ============================================================

func render_roads() -> void:
	var roads = DataManager.get_all_roads()
	for road in roads:
		var path = road.get("path", [])
		if path.size() < 2: continue

		var pts: Array = []
		for i in range(path.size()):
			var p = path[i]
			pts.append(Vector2(p[0] if typeof(p) == TYPE_ARRAY else p.x,
							   p[1] if typeof(p) == TYPE_ARRAY else p.y))
		var smooth = _catmull_rom_spline(pts, 4)
		if smooth.size() < 2: continue

		for i in range(smooth.size() - 1):
			var p1 = smooth[i]; var p2 = smooth[i + 1]
			var h1 = DataManager.get_height_at(int(p1.x), int(p1.y))
			var h2 = DataManager.get_height_at(int(p2.x), int(p2.y))
			var sp1 = grid_utils.grid_to_screen(int(p1.x), int(p1.y), h1)
			var sp2 = grid_utils.grid_to_screen(int(p2.x), int(p2.y), h2)
			_draw_segment(feature_layer, sp1, sp2, Color(0.36, 0.28, 0.18, 0.75), 5.5, 3)
			_draw_segment(feature_layer, sp1, sp2, Color(0.52, 0.42, 0.28, 0.50), 3.0, 4)


# ============================================================
# 城市
# ============================================================

func render_cities() -> void:
	_city_sprites.clear()
	for city in GameManager.cities.values():
		var pos = city.position
		var height = DataManager.get_height_at(pos.x, pos.y)
		var sp = grid_utils.grid_to_screen(pos.x, pos.y, height)
		var marker = _create_city_marker(city)
		marker.position = sp
		marker.z_index = pos.y + 30
		feature_layer.add_child(marker)
		_city_sprites[city.id] = marker


func _create_city_marker(city: City) -> Node2D:
	var container = Node2D.new()

	var color: Color
	if city.is_owned():
		var faction = GameManager.get_faction(city.faction_id)
		color = faction.color if faction else Color(0.42, 0.38, 0.28)
	else:
		color = Color(0.32, 0.32, 0.25)

	var importance = 0
	if city.counties.size() >= 5: importance = 2
	elif city.counties.size() >= 3: importance = 1

	var castle_tex = _make_castle_texture(color, importance)
	var castle = Sprite2D.new()
	castle.texture = castle_tex
	castle.scale = Vector2(1.8, 1.8)
	container.add_child(castle)

	# 城名阴影
	var label_y = -100
	var shadow = Label.new()
	shadow.text = city.name
	shadow.position = Vector2(2, label_y - 2)
	shadow.add_theme_font_size_override("font_size", 17)
	shadow.add_theme_color_override("font_color", Color(0, 0, 0, 0.65))
	shadow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(shadow)

	var label = Label.new()
	label.text = city.name
	label.position = Vector2(0, label_y)
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.72))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("outline_size", 1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(label)

	return container


# ============================================================
# 关隘
# ============================================================

func render_passes() -> void:
	_clear_pass_harbor_sprites(_pass_sprites)
	for pass_data in DataManager.get_all_passes():
		var p = pass_data.get("position", {})
		var x = p.get("x", 0); var y = p.get("y", 0)
		var height = DataManager.get_height_at(x, y)
		var sp = grid_utils.grid_to_screen(x, y, height)
		var marker = Sprite2D.new()
		marker.texture = _make_diamond_texture(Color(0.70, 0.52, 0.25, 0.88), 0)
		marker.scale = Vector2(1.4, 1.4)
		marker.position = sp; marker.z_index = y + 25
		feature_layer.add_child(marker)
		_pass_sprites.append(marker)
		var label = Label.new()
		label.text = pass_data.get("name", "")
		label.position = sp + Vector2(0, -18)
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(1, 0.86, 0.62))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
		label.add_theme_constant_override("outline_size", 1)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.z_index = y + 26
		feature_layer.add_child(label)


# ============================================================
# 港口
# ============================================================

func render_harbors() -> void:
	for harbor_data in DataManager.get_all_harbors():
		var p = harbor_data.get("position", {})
		var x = p.get("x", 0); var y = p.get("y", 0)
		var height = DataManager.get_height_at(x, y)
		var sp = grid_utils.grid_to_screen(x, y, height)
		var marker = Sprite2D.new()
		marker.texture = _make_diamond_texture(Color(0.22, 0.42, 0.65, 0.88), 0)
		marker.scale = Vector2(1.1, 1.1)
		marker.position = sp; marker.z_index = y + 25
		feature_layer.add_child(marker)
		_harbor_sprites.append(marker)


# ============================================================
# 资源
# ============================================================

func render_resources() -> void:
	for res in DataManager.get_all_resources():
		var p = res.get("position", {})
		var x = p.get("x", 0); var y = p.get("y", 0)
		var height = DataManager.get_height_at(x, y)
		var sp = grid_utils.grid_to_screen(x, y, height)
		var rt = res.get("type", "farmland")
		var color: Color
		match rt:
			"farmland": color = Color(0.52, 0.65, 0.22, 0.8)
			"mine": color = Color(0.45, 0.38, 0.28, 0.8)
			"village": color = Color(0.65, 0.58, 0.42, 0.8)
			_: color = Color.GRAY
		var marker = Sprite2D.new()
		marker.texture = _make_diamond_texture(color, 0)
		marker.scale = Vector2(0.55, 0.55)
		marker.position = sp; marker.z_index = y + 10
		feature_layer.add_child(marker)


# ============================================================
# 部队
# ============================================================

func render_armies() -> void:
	_clear_army_sprites()
	for army in GameManager.armies.values():
		if not army.is_alive(): continue
		var pos = army.position
		var height = DataManager.get_height_at(pos.x, pos.y)
		var sp = grid_utils.grid_to_screen(pos.x, pos.y, height)
		var faction = GameManager.get_faction(army.faction_id)
		var color = faction.color if faction else Color(0.5, 0.5, 0.4)
		var border = Sprite2D.new()
		border.texture = _make_diamond_texture(Color(0.72, 0.55, 0.20, 0.82), 0)
		border.scale = Vector2(1.35, 1.35)
		border.position = sp; border.z_index = pos.y + 34
		unit_layer.add_child(border)
		_army_sprites[army.id] = border
		var sprite = Sprite2D.new()
		sprite.texture = _make_diamond_texture(color, 0)
		sprite.scale = Vector2(1.15, 1.15)
		sprite.position = sp; sprite.z_index = pos.y + 35
		unit_layer.add_child(sprite)
		var cmdr = GameManager.get_officer(army.commander_id)
		var label = Label.new()
		label.text = "%s %d" % [cmdr.name if cmdr else "?", army.troops]
		label.position = sp + Vector2(0, -14)
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", Color(1.0, 0.90, 0.72))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
		label.add_theme_constant_override("outline_size", 1)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.z_index = pos.y + 36
		unit_layer.add_child(label)


# ============================================================
# 高亮 & 移动范围
# ============================================================

func highlight_vertex(x: int, y: int) -> void:
	_clear_layer(ui_layer)
	var height = DataManager.get_height_at(x, y)
	var sp = grid_utils.grid_to_screen(x, y, height)
	var hl = Sprite2D.new()
	hl.texture = _make_diamond_texture(Color(1.0, 0.85, 0.22, 0.62), 0)
	hl.scale = Vector2(1.3, 1.3)
	hl.position = sp; hl.z_index = y + 40
	ui_layer.add_child(hl)


func show_move_range(reachable: Dictionary) -> void:
	_clear_layer(ui_layer)
	for pos in reachable:
		var remaining = reachable[pos]
		var alpha = clampf(0.18 + float(remaining) / 20.0 * 0.5, 0.12, 0.62)
		var height = DataManager.get_height_at(pos.x, pos.y)
		var sp = grid_utils.grid_to_screen(pos.x, pos.y, height)
		var m = Sprite2D.new()
		m.texture = _make_diamond_texture(Color(0.22, 0.72, 1.0, alpha), 0)
		m.position = sp; m.z_index = pos.y + 39
		ui_layer.add_child(m)


# ============================================================
# 部队范围
# ============================================================

func _show_army_range(army: Army) -> void:
	if army.faction_id != GameManager.player_faction_id or army.has_moved: return
	var commander = GameManager.get_officer(army.commander_id)
	var mp = 10
	if commander: mp = commander.get_stat("tong") / 5 + 5
	var costs = {"plain":1, "grassland":1, "road":1, "forest":2, "hill":2, "wetland":3, "ford":3, "mountain":4, "dense_forest":4, "desert":2}
	var blocked: Array = []
	for a in GameManager.armies.values():
		if a.id != army.id and a.is_alive(): blocked.append(a.position)
	var reachable = grid_utils.get_reachable_vertices(army.position, mp, costs, blocked)
	show_move_range(reachable)


# ============================================================
# 信号
# ============================================================

func _on_city_clicked(city_id: String) -> void:
	var city = GameManager.get_city(city_id)
	if city: highlight_vertex(city.position.x, city.position.y)

func _on_army_clicked(army_id: int) -> void:
	var army = GameManager.get_army(army_id)
	if army:
		highlight_vertex(army.position.x, army.position.y)
		_show_army_range(army)

func _on_vertex_clicked(pos: Vector2i) -> void:
	highlight_vertex(pos.x, pos.y)


# ============================================================
# 相机
# ============================================================

func set_viewport_offset(offset: Vector2) -> void:
	if camera: camera.position = offset


# ============================================================
# 辅助
# ============================================================

func _clear_layer(layer: Node2D) -> void:
	for child in layer.get_children(): child.queue_free()

func _clear_pass_harbor_sprites(list: Array) -> void:
	for sprite in list:
		if is_instance_valid(sprite): sprite.queue_free()
	list.clear()

func _clear_army_sprites() -> void:
	for sprite in _army_sprites.values():
		if is_instance_valid(sprite): sprite.queue_free()
	_army_sprites.clear()
