extends Node2D
## Offset Square（偏移方格）地图渲染器 — 俯视 tile 制
##
## 每个 tile: TILE_SIZE × TILE_SIZE 方形
## 奇数行右移半格 → 6邻接/砖墙布局
## 地形色 + 细节噪声 + 明显边框

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
var _tile_cache: Dictionary = {}

# Tile 尺寸 (来自 GridUtils)
const TS: float = GridUtils.TILE_SIZE
const TSI: int = int(GridUtils.TILE_SIZE)  # int 版，给 Image/Range 用
const BORDER: int = 2

# Tile 可变参数
var _tile_modulates: Dictionary = {}

# Sprite 追踪
var _tile_sprites: Array = []
var _tile_dict: Dictionary = {}   # {Vector2i: Sprite2D}
var _city_sprites: Dictionary = {}
var _army_sprites: Dictionary = {}
var _pass_harbor_sprites: Array = []

# 编辑器
var edit_mode: bool = false
var edit_terrain: String = "plain"
var edit_brush: int = 1   # 笔刷半径 (1=单格, 2=3x3, 3=5x5)
var edit_city_mode: bool = false  # true=放置城市模式
var _edit_hover: Vector2i = Vector2i(-1, -1)
var _edit_highlight: Sprite2D = null

# ============================================================
# 地形色板
# ============================================================

const TERRAIN_COLORS: Dictionary = {
	"plain":        Color(0.62, 0.65, 0.38),
	"grassland":    Color(0.55, 0.62, 0.33),
	"forest":       Color(0.20, 0.38, 0.17),
	"dense_forest": Color(0.12, 0.28, 0.10),
	"hill":         Color(0.56, 0.50, 0.34),
	"mountain":     Color(0.44, 0.39, 0.30),
	"high_mountain":Color(0.42, 0.38, 0.32),
	"desert":       Color(0.78, 0.72, 0.48),
	"wetland":      Color(0.30, 0.44, 0.30),
	"water":        Color(0.16, 0.36, 0.55),
	"ocean":        Color(0.08, 0.25, 0.50),
	"road":         Color(0.65, 0.62, 0.42),
	"guandao":      Color(0.72, 0.58, 0.30),
	"city":         Color(0.82, 0.22, 0.18),
}

# 中文显示名
const TERRAIN_NAMES: Dictionary = {
	"plain":        "平原",
	"grassland":    "草原",
	"forest":       "森林",
	"dense_forest": "密林",
	"hill":         "丘陵",
	"mountain":     "山地",
	"high_mountain":"险峰",
	"desert":       "沙漠",
	"wetland":      "湿地",
	"water":        "河流",
	"ocean":        "海洋",
	"road":         "小路",
	"guandao":      "官道",
	"city":         "城市",
}

const BORDER_COLOR: Color = Color(0.15, 0.12, 0.08, 0.85)
const BORDER_HIGHLIGHT: Color = Color(0.28, 0.25, 0.18, 0.45)


# ============================================================
# 初始化
# ============================================================

func _ready() -> void:
	_setup_layers()

	# 地图居中
	var cx = DataManager.map_width / 2.0
	var cy = DataManager.map_height / 2.0
	var screen_center = grid_utils.grid_to_screen(int(cx), int(cy))
	var view_center = Vector2(960, 540)
	grid_utils.setup(view_center.x - screen_center.x + TS * 0.5, view_center.y - screen_center.y + TS * 0.5,
		DataManager.map_width, DataManager.map_height)

	if camera:
		camera.enabled = true
		camera.position = view_center
		camera.zoom = Vector2(0.7, 0.7)

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
	print("MapRenderer: Rendering offset-square tile map (%dx%d)..." % [DataManager.map_width, DataManager.map_height])
	var t0 = Time.get_ticks_msec()
	render_terrain()
	print("  Terrain: %dms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	render_county_overlays()
	print("  Overlays: %dms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	render_cities()
	render_passes()
	render_harbors()
	print("  Features: %dms" % (Time.get_ticks_msec() - t0))
	print("MapRenderer: Done.")


# ============================================================
# Tile 地形渲染
# ============================================================

func render_terrain() -> void:
	_clear_layer(terrain_layer)
	_tile_sprites.clear()
	_tile_dict.clear()
	_tile_modulates.clear()

	var rng = RandomNumberGenerator.new()
	rng.seed = 42

	for gy in range(DataManager.map_height):
		for gx in range(DataManager.map_width):
			var terrain = DataManager.get_terrain_at(gx, gy)
			var tex = _get_tile_texture(terrain)
			var screen_pos = grid_utils.grid_to_screen(gx, gy)

			var sprite = Sprite2D.new()
			sprite.texture = tex
			sprite.position = screen_pos
			sprite.centered = true
			sprite.z_index = gy

			# 微调色调变化
			var seed_val = (gx * 313 + gy * 157) % 1000
			rng.seed = seed_val
			var variation = rng.randf_range(-0.04, 0.04)
			sprite.modulate = Color(1.0 + variation, 1.0 + variation, 1.0 + variation)

			terrain_layer.add_child(sprite)
			_tile_sprites.append(sprite)
			_tile_dict[Vector2i(gx, gy)] = sprite

	print("MapRenderer: %d tiles rendered" % _tile_sprites.size())


## 更新单个 tile 的地形（编辑器用）
func update_tile(gx: int, gy: int, terrain: String) -> void:
	var key = Vector2i(gx, gy)
	var sprite: Sprite2D = _tile_dict.get(key, null)
	if not sprite:
		return
	sprite.texture = _get_tile_texture(terrain)
	# Refresh modulate
	var rng = RandomNumberGenerator.new()
	var seed_val = (gx * 313 + gy * 157) % 1000
	rng.seed = seed_val
	var variation = rng.randf_range(-0.04, 0.04)
	sprite.modulate = Color(1.0 + variation, 1.0 + variation, 1.0 + variation)


## 显示编辑悬停高亮
func show_edit_hover(gx: int, gy: int) -> void:
	if gx == _edit_hover.x and gy == _edit_hover.y:
		return
	_edit_hover = Vector2i(gx, gy)

	# Update coordinate label in palette
	if _palette_panel:
		var vbox = _palette_panel.get_child(0)
		for child in vbox.get_children():
			if child is Label and child.name == "CoordLabel":
				child.text = "坐标 (%d, %d)" % [gx, gy]

	# Update highlight sprite
	if _edit_highlight:
		_edit_highlight.queue_free()
	var screen_pos = grid_utils.grid_to_screen(gx, gy)
	var img = Image.create(TSI, TSI, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 0.35))
	var tex = ImageTexture.create_from_image(img)
	_edit_highlight = Sprite2D.new()
	_edit_highlight.texture = tex
	_edit_highlight.position = screen_pos
	_edit_highlight.centered = true
	_edit_highlight.z_index = gy + 80
	ui_layer.add_child(_edit_highlight)


## 生成 tile 纹理（地形颜色 + 噪声 + 边框）
func _get_tile_texture(terrain: String) -> ImageTexture:
	if terrain in _tile_cache:
		return _tile_cache[terrain]

	var img = Image.create(TSI, TSI, false, Image.FORMAT_RGBA8)
	var base = TERRAIN_COLORS.get(terrain, Color.GRAY)
	var rng = RandomNumberGenerator.new()
	rng.seed = terrain.hash()

	# 噪声 LUT（小尺寸 → 快速生成）
	var nsize: int = TSI * TSI
	var noise: Array = []
	noise.resize(nsize)
	for i in range(nsize):
		noise[i] = rng.randf()

	# 逐像素填充
	for px in range(TSI):
		for py in range(TSI):
			var idx = (px * 37 + py * 53) % nsize
			var n = noise[idx]

			# Border check
			var is_border = false
			if px < BORDER or px >= TSI - BORDER or py < BORDER or py >= TSI - BORDER:
				is_border = true

			var col: Color
			if is_border:
				# Border pixel — dark outline
				col = BORDER_COLOR
				# Top-left highlight for 3D bevel effect
				if px < BORDER and py < BORDER:
					col = BORDER_HIGHLIGHT
				elif px < BORDER and py < TS / 4:
					col = BORDER_HIGHLIGHT
				elif py < BORDER and px < TS / 4:
					col = BORDER_HIGHLIGHT
			else:
				# Terrain body with subtle noise
				var noise_amt = 0.04
				match terrain:
					"plain", "grassland":
						noise_amt = 0.05
					"forest", "dense_forest":
						noise_amt = 0.10
					"mountain", "high_mountain":
						noise_amt = 0.12
					"desert":
						noise_amt = 0.06
					"water", "ocean":
						noise_amt = 0.04
					"wetland":
						noise_amt = 0.08

				var v = (n - 0.5) * noise_amt * 2.0
				col = Color(
					clampf(base.r + v, 0.0, 1.0),
					clampf(base.g + v, 0.0, 1.0),
					clampf(base.b + v * 0.6, 0.0, 1.0)
				)

				# 特殊地形细节
				match terrain:
					"water", "ocean":
						# 水面波光
						var wx = sin(px * 0.08 + py * 0.05) * 0.025
						col = col.lightened(wx)
					"desert":
						# 沙纹
						var sx = sin(px * 0.05 + py * 0.07) * 0.015
						col = col.lightened(sx)

			img.set_pixel(px, py, col)

	var tex = ImageTexture.create_from_image(img)
	_tile_cache[terrain] = tex
	return tex


# ============================================================
# 郡域覆盖（势力颜色半透明覆盖）
# ============================================================

func render_county_overlays() -> void:
	_clear_layer(overlay_layer)

	for city in GameManager.cities.values():
		if not city.is_owned():
			continue
		var faction = GameManager.get_faction(city.faction_id)
		if not faction:
			continue

		var pos = city.position
		var screen_pos = grid_utils.grid_to_screen(pos.x, pos.y)
		var color = Color(faction.color.r, faction.color.g, faction.color.b, 0.22)

		var sprite = Sprite2D.new()
		sprite.texture = _make_square_overlay(color)
		sprite.position = screen_pos
		sprite.centered = true
		sprite.z_index = pos.y + 1
		overlay_layer.add_child(sprite)


func _make_square_overlay(color: Color) -> ImageTexture:
	var tex_key = "overlay_%s" % color.to_rgba32()
	if tex_key in _tile_cache:
		return _tile_cache[tex_key]

	var S = int(TS * 0.8)
	var img = Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(color)
	var tex = ImageTexture.create_from_image(img)
	_tile_cache[tex_key] = tex
	return tex


# ============================================================
# 城市
# ============================================================

func render_cities() -> void:
	_city_sprites.clear()
	for city in GameManager.cities.values():
		var pos = city.position
		var screen_pos = grid_utils.grid_to_screen(pos.x, pos.y)
		var marker = _create_city_marker(city)
		marker.position = screen_pos
		marker.z_index = pos.y + 50
		feature_layer.add_child(marker)
		_city_sprites[city.id] = marker


func _create_city_marker(city: City) -> Node2D:
	var container = Node2D.new()

	var color: Color
	if city.is_owned():
		var faction = GameManager.get_faction(city.faction_id)
		color = faction.color if faction else Color(0.5, 0.5, 0.4)
	else:
		color = Color(0.45, 0.45, 0.4)

	# City base — colored square with border
	var size = 48.0
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var city_bg = Color(color.r, color.g, color.b, 0.85)
	var city_border = Color(color.r * 0.5, color.g * 0.5, color.b * 0.5, 0.95)
	for px in range(size):
		for py in range(size):
			var is_edge = px < 3 or px >= size - 3 or py < 3 or py >= size - 3
			if is_edge:
				img.set_pixel(px, py, city_border)
			else:
				img.set_pixel(px, py, city_bg)

	var city_tex = ImageTexture.create_from_image(img)
	var sprite = Sprite2D.new()
	sprite.texture = city_tex
	sprite.centered = true
	container.add_child(sprite)

	# City name label
	var label_y = -38
	var shadow = Label.new()
	shadow.text = city.name
	shadow.position = Vector2(1, label_y - 1)
	shadow.add_theme_font_size_override("font_size", 15)
	shadow.add_theme_color_override("font_color", Color(0, 0, 0, 0.7))
	shadow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(shadow)

	var label = Label.new()
	label.text = city.name
	label.position = Vector2(0, label_y)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.72))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("outline_size", 1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(label)

	return container


# ============================================================
# 关隘 / 港口
# ============================================================

func render_passes() -> void:
	for pass_data in DataManager.get_all_passes():
		var p = pass_data.get("position", {})
		var sx = p.get("x", 0); var sy = p.get("y", 0)
		var screen_pos = grid_utils.grid_to_screen(sx, sy)
		_add_small_marker(screen_pos, sy, Color(0.70, 0.52, 0.25, 0.9))

		var label = Label.new()
		label.text = pass_data.get("name", "")
		label.position = screen_pos + Vector2(0, -22)
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", Color(1, 0.86, 0.62))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
		label.add_theme_constant_override("outline_size", 1)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.z_index = sy + 51
		feature_layer.add_child(label)


func render_harbors() -> void:
	for harbor_data in DataManager.get_all_harbors():
		var p = harbor_data.get("position", {})
		var sx = p.get("x", 0); var sy = p.get("y", 0)
		var screen_pos = grid_utils.grid_to_screen(sx, sy)
		_add_small_marker(screen_pos, sy, Color(0.22, 0.42, 0.65, 0.9))


func _add_small_marker(screen_pos: Vector2, grid_y: int, color: Color) -> void:
	var size = 20
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	var tex = ImageTexture.create_from_image(img)
	var sprite = Sprite2D.new()
	sprite.texture = tex
	sprite.position = screen_pos
	sprite.centered = true
	sprite.z_index = grid_y + 50
	feature_layer.add_child(sprite)
	_pass_harbor_sprites.append(sprite)


# ============================================================
# 部队
# ============================================================

func render_armies() -> void:
	_clear_army_sprites()
	for army in GameManager.armies.values():
		if not army.is_alive():
			continue
		var pos = army.position
		var screen_pos = grid_utils.grid_to_screen(pos.x, pos.y)
		var faction = GameManager.get_faction(army.faction_id)
		var color = faction.color if faction else Color(0.5, 0.5, 0.4)

		# 部队图标
		var size = 32
		var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
		var army_color = Color(color.r, color.g, color.b, 0.92)
		img.fill(army_color)
		var tex = ImageTexture.create_from_image(img)

		var sprite = Sprite2D.new()
		sprite.texture = tex
		sprite.position = screen_pos
		sprite.centered = true
		sprite.z_index = pos.y + 60
		unit_layer.add_child(sprite)

		# 外框
		var border_img = Image.create(size + 6, size + 6, false, Image.FORMAT_RGBA8)
		border_img.fill(Color(0.85, 0.75, 0.2, 0.8))
		var border_tex = ImageTexture.create_from_image(border_img)
		var border = Sprite2D.new()
		border.texture = border_tex
		border.position = screen_pos
		border.centered = true
		border.z_index = pos.y + 59
		unit_layer.add_child(border)
		_army_sprites[army.id] = border

		# 指挥官名 + 兵力
		var cmdr = GameManager.get_officer(army.commander_id)
		var label = Label.new()
		label.text = "%s %d" % [cmdr.name if cmdr else "?", army.troops]
		label.position = screen_pos + Vector2(0, -22)
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", Color(1.0, 0.90, 0.72))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
		label.add_theme_constant_override("outline_size", 1)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.z_index = pos.y + 61
		unit_layer.add_child(label)


# ============================================================
# 高亮 & 移动范围
# ============================================================

func highlight_vertex(x: int, y: int) -> void:
	_clear_layer(ui_layer)
	var screen_pos = grid_utils.grid_to_screen(x, y)

	# 选择高亮框
	var size = TS * 0.9
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var hl_color = Color(1.0, 0.85, 0.22, 0.55)
	img.fill(hl_color)
	var tex = ImageTexture.create_from_image(img)

	var sprite = Sprite2D.new()
	sprite.texture = tex
	sprite.position = screen_pos
	sprite.centered = true
	sprite.z_index = y + 70
	ui_layer.add_child(sprite)


func show_move_range(reachable: Dictionary) -> void:
	for pos in reachable:
		var remaining = reachable[pos]
		var alpha = clampf(0.15 + float(remaining) / 20.0 * 0.5, 0.1, 0.6)
		var screen_pos = grid_utils.grid_to_screen(pos.x, pos.y)

		var size = TS * 0.75
		var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.22, 0.72, 1.0, alpha))
		var tex = ImageTexture.create_from_image(img)

		var sprite = Sprite2D.new()
		sprite.texture = tex
		sprite.position = screen_pos
		sprite.centered = true
		sprite.z_index = pos.y + 68
		ui_layer.add_child(sprite)


# ============================================================
# 部队移动范围
# ============================================================

func _show_army_range(army: Army) -> void:
	if army.faction_id != GameManager.player_faction_id or army.has_moved:
		return

	var commander = GameManager.get_officer(army.commander_id)
	var mp = 10
	if commander:
		mp = commander.get_stat("tong") / 5 + 5

	var costs = {
		"plain": 1, "grassland": 1, "road": 1, "guandao": 1, "city": 1,
		"forest": 2, "hill": 2, "wetland": 3, "ford": 3,
		"mountain": 4, "dense_forest": 4, "desert": 2,
		"water": 99, "ocean": 99,
	}

	var blocked: Array = []
	for a in GameManager.armies.values():
		if a.id != army.id and a.is_alive():
			blocked.append(a.position)

	# 转换 terrain cost key 为 terrain type 查找
	var terrain_costs: Dictionary = {}
	for gy in range(DataManager.map_height):
		for gx in range(DataManager.map_width):
			var t = DataManager.get_terrain_at(gx, gy)
			var c = costs.get(t, 1)
			terrain_costs[str(Vector2i(gx, gy))] = c

	var reachable = grid_utils.get_reachable_vertices(army.position, mp, terrain_costs, blocked)
	show_move_range(reachable)


# ============================================================
# 信号响应
# ============================================================

func _on_city_clicked(city_id: String) -> void:
	var city = GameManager.get_city(city_id)
	if city:
		highlight_vertex(city.position.x, city.position.y)


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
	if camera:
		camera.position = offset


# ============================================================
# 编辑器调色板
# ============================================================

var _palette_layer: CanvasLayer = null
var _palette_panel: Panel = null

const TERRAIN_TYPES: Array[String] = [
	"plain", "grassland", "forest", "dense_forest",
	"hill", "mountain", "high_mountain",
	"desert", "wetland", "water", "ocean",
	"road", "guandao", "city"
]

var _coord_labels: Array = []

func _on_edit_mode_changed() -> void:
	if edit_mode:
		_create_palette()
		_draw_coordinate_grid()
	else:
		_destroy_palette()
		_clear_coordinate_grid()


func _draw_coordinate_grid() -> void:
	_clear_coordinate_grid()
	var label_color = Color(1.0, 1.0, 1.0, 0.35)
	for gy in range(0, DataManager.map_height, 10):
		for gx in range(0, DataManager.map_width, 10):
			var screen_pos = grid_utils.grid_to_screen(gx, gy)
			var label = Label.new()
			label.text = "%d,%d" % [gx, gy]
			label.position = screen_pos - Vector2(20, 6)
			label.add_theme_font_size_override("font_size", 9)
			label.add_theme_color_override("font_color", label_color)
			label.z_index = gy + 90
			ui_layer.add_child(label)
			_coord_labels.append(label)


func _clear_coordinate_grid() -> void:
	for label in _coord_labels:
		if is_instance_valid(label):
			label.queue_free()
	_coord_labels.clear()


func _create_palette() -> void:
	if _palette_panel:
		return

	# Create CanvasLayer so palette always renders on top, screen-fixed
	_palette_layer = CanvasLayer.new()
	_palette_layer.name = "EditorLayer"
	_palette_layer.layer = 100
	get_tree().root.add_child(_palette_layer)

	_palette_panel = Panel.new()
	_palette_panel.name = "TerrainPalette"
	_palette_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_palette_panel.offset_left = 4
	_palette_panel.offset_top = 48
	_palette_panel.offset_right = 172
	var btn_count = TERRAIN_TYPES.size() + 5  # terrain btns + brush btns + save + separators
	_palette_panel.offset_bottom = 48 + 26 * btn_count + 12
	_palette_panel.z_index = 200

	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.04, 0.02, 0.94)
	s.set_border_width_all(1)
	s.border_color = Color(0.8, 0.7, 0.2, 1.0)
	s.set_corner_radius_all(4)
	_palette_panel.add_theme_stylebox_override("panel", s)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 1)
	_palette_panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "地图编辑 [E退出]"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vbox.add_child(title)

	# Coordinate display
	var coord_label = Label.new()
	coord_label.name = "CoordLabel"
	coord_label.text = "悬停查看坐标"
	coord_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coord_label.add_theme_font_size_override("font_size", 11)
	coord_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	vbox.add_child(coord_label)

	# Brush size controls
	var brush_label = Label.new()
	brush_label.name = "BrushLabel"
	brush_label.text = "笔刷: 单格 [1]"
	brush_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brush_label.add_theme_font_size_override("font_size", 11)
	brush_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	vbox.add_child(brush_label)

	var brush_box = HBoxContainer.new()
	brush_box.add_theme_constant_override("separation", 2)
	for pair in [[1, "1"], [2, "3x3"], [3, "5x5"]]:
		var sz = pair[0]
		var btn = Button.new()
		btn.text = pair[1]
		btn.add_theme_font_size_override("font_size", 10)
		btn.custom_minimum_size = Vector2(0, 20)
		btn.pressed.connect(_on_brush_btn.bind(sz))
		var bbs = StyleBoxFlat.new()
		bbs.bg_color = Color(0.2, 0.4, 0.8, 0.6) if sz == edit_brush else Color(0.2, 0.2, 0.2, 0.5)
		bbs.set_corner_radius_all(2)
		btn.add_theme_stylebox_override("normal", bbs)
		btn.name = "BrushBtn%d" % sz
		brush_box.add_child(btn)
	vbox.add_child(brush_box)

	vbox.add_child(HSeparator.new())

	# Terrain buttons with Chinese names
	for terrain in TERRAIN_TYPES:
		var btn = Button.new()
		var cname = TERRAIN_NAMES.get(terrain, terrain)
		btn.text = cname
		btn.add_theme_font_size_override("font_size", 12)
		btn.custom_minimum_size = Vector2(0, 22)
		btn.pressed.connect(_on_palette_btn.bind(terrain))
		var tc = TERRAIN_COLORS.get(terrain, Color.GRAY)
		var bs = StyleBoxFlat.new()
		bs.bg_color = Color(tc.r, tc.g, tc.b, 0.5) if terrain != edit_terrain else Color(tc.r, tc.g, tc.b, 0.85)
		if terrain == edit_terrain:
			bs.set_border_width_all(2)
			bs.border_color = Color.WHITE
		bs.set_corner_radius_all(2)
		btn.add_theme_stylebox_override("normal", bs)
		btn.name = "TerrainBtn_%s" % terrain
		vbox.add_child(btn)

	# City placement button
	vbox.add_child(HSeparator.new())
	var btn_city = Button.new()
	btn_city.name = "CityBtn"
	btn_city.text = "🏙 放置城市"
	btn_city.add_theme_font_size_override("font_size", 13)
	btn_city.custom_minimum_size = Vector2(0, 28)
	var cbs = StyleBoxFlat.new()
	cbs.bg_color = Color(0.5, 0.15, 0.1, 0.6)
	cbs.set_corner_radius_all(2)
	cbs.set_border_width_all(1)
	cbs.border_color = Color(0.8, 0.3, 0.3, 0.8)
	btn_city.add_theme_stylebox_override("normal", cbs)
	btn_city.pressed.connect(func():
		edit_city_mode = not edit_city_mode
		var s2 = StyleBoxFlat.new()
		if edit_city_mode:
			s2.bg_color = Color(0.8, 0.15, 0.1, 0.8)
			s2.set_border_width_all(2)
			s2.border_color = Color.WHITE
		else:
			s2.bg_color = Color(0.5, 0.15, 0.1, 0.6)
			s2.set_border_width_all(1)
			s2.border_color = Color(0.8, 0.3, 0.3, 0.8)
		s2.set_corner_radius_all(2)
		btn_city.add_theme_stylebox_override("normal", s2)
	)
	vbox.add_child(btn_city)

	# Save button
	vbox.add_child(HSeparator.new())
	var btn_save = Button.new()
	btn_save.text = "💾 保存 Ctrl+S"
	btn_save.add_theme_font_size_override("font_size", 12)
	btn_save.custom_minimum_size = Vector2(0, 26)
	btn_save.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	btn_save.pressed.connect(func(): DataManager.save_terrain(); _flash_save_btn(btn_save))
	vbox.add_child(btn_save)

	_palette_layer.add_child(_palette_panel)
	print("Palette created on CanvasLayer")


## 在城市放置模式下点击 tile → 弹出命名框
var _city_place_pos: Vector2i = Vector2i(-1, -1)

func request_city_name(gx: int, gy: int) -> void:
	_city_place_pos = Vector2i(gx, gy)
	if _palette_layer:
		var dialog = _create_naming_dialog()
		_palette_layer.add_child(dialog)


func _create_naming_dialog() -> Panel:
	# Dark background overlay to block map clicks
	var overlay = ColorRect.new()
	overlay.name = "CityOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.4)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 299
	_palette_layer.add_child(overlay)

	var dlg = Panel.new()
	dlg.name = "CityNameDialog"
	dlg.set_anchors_preset(Control.PRESET_CENTER)
	dlg.offset_left = -180
	dlg.offset_right = 180
	dlg.offset_top = -70
	dlg.offset_bottom = 70
	dlg.z_index = 300
	dlg.mouse_filter = Control.MOUSE_FILTER_STOP

	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.05, 0.02, 0.96)
	s.set_border_width_all(2)
	s.border_color = Color(0.9, 0.4, 0.3, 1.0)
	s.set_corner_radius_all(8)
	dlg.add_theme_stylebox_override("panel", s)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	dlg.add_child(vbox)

	var title = Label.new()
	title.text = "命名城市 (%d, %d)" % [_city_place_pos.x, _city_place_pos.y]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vbox.add_child(title)

	var line = LineEdit.new()
	line.name = "NameInput"
	line.placeholder_text = "输入城市名..."
	line.add_theme_font_size_override("font_size", 16)
	line.custom_minimum_size = Vector2(0, 36)
	line.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox.add_child(line)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)

	var ok = Button.new()
	ok.text = "  确 定  "
	ok.add_theme_font_size_override("font_size", 14)
	ok.pressed.connect(func():
		var city_name = line.text.strip_edges()
		if city_name != "":
			_place_city(_city_place_pos.x, _city_place_pos.y, city_name)
		overlay.queue_free()
		dlg.queue_free()
	)
	hbox.add_child(ok)

	var cancel = Button.new()
	cancel.text = "  取 消  "
	cancel.add_theme_font_size_override("font_size", 14)
	cancel.pressed.connect(func():
		overlay.queue_free()
		dlg.queue_free()
	)
	hbox.add_child(cancel)
	vbox.add_child(hbox)

	line.text_submitted.connect(func(_t): ok.pressed.emit())
	dlg.tree_entered.connect(func(): line.grab_focus(), CONNECT_ONE_SHOT)
	return dlg


func _place_city(gx: int, gy: int, name: String) -> void:
	var city_id = "city_" + name.replace(" ", "_").to_lower()
	var tiles = _hex7_tiles(gx, gy)
	for i in range(tiles.size()):
		var tx = tiles[i][0]
		var ty = tiles[i][1]
		var terrain = "city" if i == 0 else "road"
		DataManager.set_terrain_at(tx, ty, terrain)
		update_tile(tx, ty, terrain)

	# Add to cities.json
	DataManager.add_city(city_id, name, gx, gy)
	print("City placed: %s at (%d,%d)" % [name, gx, gy])


func _hex7_tiles(gx: int, gy: int) -> Array:
	var tiles = [[gx, gy]]
	var nb: Array
	if gy & 1:
		nb = [[gx,gy-1],[gx+1,gy-1],[gx-1,gy],[gx+1,gy],[gx,gy+1],[gx+1,gy+1]]
	else:
		nb = [[gx-1,gy-1],[gx,gy-1],[gx-1,gy],[gx+1,gy],[gx-1,gy+1],[gx,gy+1]]
	for pair in nb:
		var nx: int = pair[0]
		var ny: int = pair[1]
		if nx >= 0 and ny >= 0 and nx < DataManager.map_width and ny < DataManager.map_height:
			tiles.append([nx, ny])
	return tiles


func _flash_save_btn(btn: Button) -> void:
	btn.text = "已保存!"
	btn.add_theme_color_override("font_color", Color(1.0, 1.0, 0.5))
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(btn):
		btn.text = "💾 保存 Ctrl+S"
		btn.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))


func _on_brush_btn(size: int) -> void:
	edit_brush = size
	var names = {1: "单格 [1]", 2: "3x3 [2]", 3: "5x5 [3]"}
	if _palette_panel:
		var lbl = _palette_panel.get_node_or_null("BrushLabel") if false else null
		# Update brush label and button styles
		var vbox = _palette_panel.get_child(0)
		for child in vbox.get_children():
			if child is Label and child.name == "BrushLabel":
				child.text = "笔刷: %s" % names.get(size, "?")
			if child is HBoxContainer:
				for btn in child.get_children():
					if btn.name == "BrushBtn%d" % size:
						var bs = StyleBoxFlat.new()
						bs.bg_color = Color(0.2, 0.4, 0.8, 0.6)
						bs.set_corner_radius_all(2)
						btn.add_theme_stylebox_override("normal", bs)
					elif btn is Button:
						var bs = StyleBoxFlat.new()
						bs.bg_color = Color(0.2, 0.2, 0.2, 0.5)
						bs.set_corner_radius_all(2)
						btn.add_theme_stylebox_override("normal", bs)


func _destroy_palette() -> void:
	if _palette_layer:
		_palette_layer.queue_free()
		_palette_layer = null
		_palette_panel = null


func _on_palette_btn(terrain: String) -> void:
	edit_terrain = terrain
	var cname = TERRAIN_NAMES.get(terrain, terrain)
	print("笔刷地形: %s" % cname)
	if _palette_panel:
		var vbox = _palette_panel.get_child(0)
		for child in vbox.get_children():
			if child is Button and child.name.begins_with("TerrainBtn_"):
				var tc = TERRAIN_COLORS.get(terrain, Color.GRAY)
				var ct = child.name.trim_prefix("TerrainBtn_")
				var bs = StyleBoxFlat.new()
				if ct == terrain:
					bs.bg_color = Color(tc.r, tc.g, tc.b, 0.8)
					bs.set_border_width_all(2)
					bs.border_color = Color.WHITE
				else:
					var ttc = TERRAIN_COLORS.get(ct, Color.GRAY)
					bs.bg_color = Color(ttc.r, ttc.g, ttc.b, 0.4)
				bs.set_corner_radius_all(2)
				child.add_theme_stylebox_override("normal", bs)


# ============================================================
# 清理
# ============================================================

func _clear_layer(layer: Node2D) -> void:
	for child in layer.get_children():
		child.queue_free()


func _clear_army_sprites() -> void:
	for sprite in _army_sprites.values():
		if is_instance_valid(sprite):
			sprite.queue_free()
	_army_sprites.clear()
