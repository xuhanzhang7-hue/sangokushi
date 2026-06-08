extends Node
## Offset Square 地图输入处理
##
## 鼠标点击、悬停、拖拽、缩放。Camera2D 方案。

@export var map_renderer: NodePath
@export var drag_button: MouseButton = MOUSE_BUTTON_RIGHT

var _grid_utils: GridUtils
var _camera: Camera2D

var _is_dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _camera_start: Vector2 = Vector2.ZERO
var _last_hover: Vector2i = Vector2i(-1, -1)

# 双击检测
var _last_click_time: float = 0.0
var _last_click_pos: Vector2 = Vector2.ZERO
const DOUBLE_CLICK_TIME: float = 0.3
const DOUBLE_CLICK_DIST: float = 10.0


func _ready() -> void:
	var renderer = get_node_or_null(map_renderer) if not map_renderer.is_empty() else null
	if renderer and renderer.has_method("render_full_map"):
		_grid_utils = renderer.grid_utils
		_camera = renderer.camera
	else:
		_grid_utils = GridUtils.new()
		_grid_utils.setup(0, 0, DataManager.map_width, DataManager.map_height)


var _edit_painting: bool = false

func _input(event: InputEvent) -> void:
	# Edit mode keyboard shortcuts
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_E:
			_toggle_edit_mode()
			return
		if event.keycode == KEY_1:
			_set_brush(1)
			return
		if event.keycode == KEY_2:
			_set_brush(2)
			return
		if event.keycode == KEY_3:
			_set_brush(3)
			return
		if event.keycode == KEY_S and event.ctrl_pressed:
			DataManager.save_terrain()
			print("MapInput: 地形已保存!")
			return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(event.position, 1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(event.position, 1.0 / 1.1)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if _is_edit_mode():
					_edit_painting = true
					_paint_at(event.position)
				else:
					_on_map_pressed(event.position)
			else:
				_edit_painting = false
		elif event.button_index == drag_button:
			if event.pressed:
				_start_drag(event.position)
			else:
				_end_drag()

	if event is InputEventMouseMotion:
		if _is_dragging:
			_update_drag(event.position)
		elif _edit_painting:
			_paint_at(event.position)
		elif _is_edit_mode():
			_edit_hover(event.position)
		else:
			_update_hover(event.position)


## ============================================================
## 屏幕 ↔ 世界 ↔ Tile 坐标
## ============================================================

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	if _camera:
		var vp_size = get_viewport().get_visible_rect().size
		var center = vp_size / 2.0
		return _camera.position + (screen_pos - center) / _camera.zoom
	return screen_pos


func _screen_to_grid(screen_pos: Vector2) -> Vector2i:
	var world = _screen_to_world(screen_pos)
	return _grid_utils.screen_to_grid_precise(world.x, world.y)


## ============================================================
## 点击
## ============================================================

func _on_map_pressed(screen_pos: Vector2) -> void:
	var world = _screen_to_world(screen_pos)
	var grid_pos = _grid_utils.screen_to_grid_precise(world.x, world.y)

	if not _grid_utils.is_in_bounds(grid_pos):
		return

	# 检查是否有待处理的出征目的地选择
	var hud = get_node_or_null("../UI")
	if hud and hud.has_method("_on_destination_selected") and not hud._pending_dispatch.is_empty():
		hud._on_destination_selected(grid_pos)
		return

	# 双击检测
	var now = Time.get_ticks_msec() / 1000.0
	var dist = screen_pos.distance_to(_last_click_pos)
	if now - _last_click_time < DOUBLE_CLICK_TIME and dist < DOUBLE_CLICK_DIST:
		_on_map_double_clicked(grid_pos)
	_last_click_time = now
	_last_click_pos = screen_pos

	# 如果已选中部队，尝试移动
	if GameManager.selected_army_id > 0:
		_try_move_army(grid_pos)
		return

	GameManager.select_vertex(grid_pos.x, grid_pos.y)


func _try_move_army(grid_pos: Vector2i) -> void:
	var army = GameManager.get_army(GameManager.selected_army_id)
	if not army or army.faction_id != GameManager.player_faction_id:
		GameManager.selected_army_id = -1
		return

	if army.has_moved:
		print("MapInput: Army already moved this turn")
		return

	# 检查目的地是否可达
	var reachable = _get_army_reachable(army)
	if not grid_pos in reachable:
		print("MapInput: Destination not reachable")
		return

	# 检查目的地是否有敌军
	var enemy = GameManager.get_army_at(grid_pos.x, grid_pos.y)
	if enemy and enemy.faction_id != army.faction_id:
		_resolve_combat(army, enemy)

	# 检查目的地是否有敌城（攻城）
	if army.is_alive():
		var city = GameManager.get_city_at(grid_pos.x, grid_pos.y)
		if city and city.faction_id != army.faction_id:
			_resolve_siege(army, city)

	# 移动部队
	if army.is_alive():
		army.position = grid_pos
	army.has_moved = true

	print("MapInput: Army %d moved to (%d, %d)" % [army.id, grid_pos.x, grid_pos.y])

	# 刷新地图
	var renderer = get_node_or_null(map_renderer)
	if renderer and renderer.has_method("render_armies"):
		renderer.render_armies()
	if renderer and renderer.has_method("highlight_vertex"):
		renderer.highlight_vertex(-1, -1)

	GameManager.selected_army_id = -1


func _resolve_combat(attacker: Army, defender: Army) -> void:
	print("=== BATTLE: Army %d vs Army %d ===" % [attacker.id, defender.id])

	var atk_cmdr = GameManager.get_officer(attacker.commander_id)
	var def_cmdr = GameManager.get_officer(defender.commander_id)

	var atk_stats = {
		"tong": atk_cmdr.get_stat("tong") if atk_cmdr else 50,
		"wu": atk_cmdr.get_stat("wu") if atk_cmdr else 50
	}
	var def_stats = {
		"tong": def_cmdr.get_stat("tong") if def_cmdr else 50,
		"wu": def_cmdr.get_stat("wu") if def_cmdr else 50
	}

	var atk_power = int((atk_stats.wu * 0.6 + atk_stats.tong * 0.4) * sqrt(attacker.troops / 1000.0) * (attacker.morale / 100.0))
	var def_power = int((def_stats.wu * 0.6 + def_stats.tong * 0.4) * sqrt(defender.troops / 1000.0) * (defender.morale / 100.0))

	print("  Attacker power: %d, Defender power: %d" % [atk_power, def_power])

	var dmg_to_def = maxi(1, int(atk_power * 0.1))
	defender.take_damage(dmg_to_def)
	print("  Attacker deals %d damage, defender troops: %d" % [dmg_to_def, defender.troops])

	if defender.is_alive():
		var dmg_to_atk = maxi(1, int(def_power * 0.1))
		attacker.take_damage(dmg_to_atk)
		print("  Defender deals %d damage, attacker troops: %d" % [dmg_to_atk, attacker.troops])

	attacker.morale = maxi(0, attacker.morale - 10)
	defender.morale = maxi(0, defender.morale - 10)

	if not defender.is_alive():
		print("  Defender army %d destroyed!" % defender.id)
	elif not attacker.is_alive():
		print("  Attacker army %d destroyed!" % attacker.id)
	else:
		print("  Both armies survive. Attacker: %d troops, Defender: %d troops" % [attacker.troops, defender.troops])

	print("=== BATTLE END ===")


func _resolve_siege(army: Army, city: City) -> void:
	print("=== SIEGE: Army %d attacks %s ===" % [army.id, city.name])

	var atk_cmdr = GameManager.get_officer(army.commander_id)
	var siege_power = int(army.troops / 100) + (atk_cmdr.get_stat("wu") if atk_cmdr else 50) / 10

	var dmg_to_city = maxi(1, siege_power)
	city.durability -= dmg_to_city
	print("  Siege damage to city: %d, durability: %d/%d" % [dmg_to_city, city.durability, city.max_durability])

	var garrison_dmg = maxi(1, int(city.get_total_troops() / 50))
	army.take_damage(garrison_dmg)
	print("  Garrison deals %d damage, army troops: %d" % [garrison_dmg, army.troops])

	if city.durability <= 0:
		city.durability = 0
		var old_faction = city.faction_id
		city.faction_id = army.faction_id
		var faction = GameManager.get_faction(army.faction_id)
		if faction:
			faction.cities.append(city.id)
		var old_fac = GameManager.get_faction(old_faction)
		if old_fac:
			old_fac.cities.erase(city.id)
		print("  %s has fallen! Now belongs to %s" % [city.name, faction.name if faction else "?"])
		EventBus.city_captured.emit(city.id, old_faction, army.faction_id)

	print("=== SIEGE END ===")


func _get_army_reachable(army: Army) -> Dictionary:
	var commander = GameManager.get_officer(army.commander_id)
	var move_points = 10
	if commander:
		move_points = commander.get_stat("tong") / 5 + 5

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

	# 构建地形消耗字典 (per tile)
	var terrain_costs: Dictionary = {}
	for gy in range(DataManager.map_height):
		for gx in range(DataManager.map_width):
			var t = DataManager.get_terrain_at(gx, gy)
			var c = costs.get(t, 1)
			terrain_costs[str(Vector2i(gx, gy))] = c

	return _grid_utils.get_reachable_vertices(army.position, move_points, terrain_costs, blocked)


func _on_map_double_clicked(grid_pos: Vector2i) -> void:
	var city = GameManager.get_city_at(grid_pos.x, grid_pos.y)
	if city:
		print("Double clicked city: %s" % city.name)


## ============================================================
## 悬停
## ============================================================

func _update_hover(screen_pos: Vector2) -> void:
	var grid_pos = _screen_to_grid(screen_pos)
	if grid_pos != _last_hover and _grid_utils.is_in_bounds(grid_pos):
		_last_hover = grid_pos
		EventBus.map_hover_changed.emit(grid_pos)


## ============================================================
## 相机拖拽
## ============================================================

func _start_drag(screen_pos: Vector2) -> void:
	_is_dragging = true
	_drag_start = screen_pos
	if _camera:
		_camera_start = _camera.position


func _update_drag(screen_pos: Vector2) -> void:
	if not _is_dragging or not _camera:
		return
	var delta = screen_pos - _drag_start
	_camera.position = _camera_start - delta / _camera.zoom


func _end_drag() -> void:
	_is_dragging = false


## ============================================================
## 编辑模式
## ============================================================

func _is_edit_mode() -> bool:
	var renderer = get_node_or_null(map_renderer)
	return renderer and renderer.edit_mode


func _toggle_edit_mode() -> void:
	var renderer = get_node_or_null(map_renderer)
	if not renderer:
		return
	renderer.edit_mode = not renderer.edit_mode
	renderer._on_edit_mode_changed()
	if renderer.edit_mode:
		print("=== EDIT MODE ON === (E=退出, 左键绘制, Ctrl+S=保存)")
		print("  当前地形: %s" % renderer.edit_terrain)
	else:
		print("=== EDIT MODE OFF ===")
		_edit_painting = false


func _paint_at(screen_pos: Vector2) -> void:
	var renderer = get_node_or_null(map_renderer)
	if not renderer or not renderer.edit_mode:
		return
	var grid_pos = _screen_to_grid(screen_pos)
	if not _grid_utils.is_in_bounds(grid_pos):
		return

	# City placement mode
	if renderer.edit_city_mode:
		renderer.request_city_name(grid_pos.x, grid_pos.y)
		_edit_painting = false  # single click only
		return

	# Terrain paint mode
	var terrain = renderer.edit_terrain
	var r = renderer.edit_brush - 1
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var px = grid_pos.x + dx
			var py = grid_pos.y + dy
			if _grid_utils.is_in_bounds(Vector2i(px, py)):
				DataManager.set_terrain_at(px, py, terrain)
				renderer.update_tile(px, py, terrain)

	# 道路地形实时刷新路网
	if terrain in ["road", "guandao"]:
		renderer.render_road_network()

func _set_brush(size: int) -> void:
	var renderer = get_node_or_null(map_renderer)
	if not renderer:
		return
	renderer.edit_brush = size
	renderer._on_brush_btn(size)
	var names = {1: "单格", 2: "3x3", 3: "5x5"}
	print("笔刷: %s" % names.get(size, "?"))


func _edit_hover(screen_pos: Vector2) -> void:
	var renderer = get_node_or_null(map_renderer)
	if not renderer or not renderer.edit_mode:
		return
	var grid_pos = _screen_to_grid(screen_pos)
	if not _grid_utils.is_in_bounds(grid_pos):
		return
	renderer.show_edit_hover(grid_pos.x, grid_pos.y)


func set_edit_terrain(terrain: String) -> void:
	var renderer = get_node_or_null(map_renderer)
	if renderer:
		renderer.edit_terrain = terrain
		print("Editor terrain: %s" % terrain)


## ============================================================
## 缩放
## ============================================================

func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	if not _camera:
		return

	var new_zoom = _camera.zoom * factor
	new_zoom.x = clampf(new_zoom.x, 0.2, 4.0)
	new_zoom.y = clampf(new_zoom.y, 0.2, 4.0)

	if is_equal_approx(new_zoom.x, _camera.zoom.x):
		return

	var world_under_cursor = _screen_to_world(screen_pos)
	_camera.zoom = new_zoom
	var vp_size = get_viewport().get_visible_rect().size
	var center = vp_size / 2.0
	_camera.position = world_under_cursor - (screen_pos - center) / _camera.zoom
