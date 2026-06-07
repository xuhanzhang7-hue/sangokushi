extends Node
## 地图输入处理
##
## 鼠标点击、悬停、拖拽、缩放。使用 Camera2D 实现平滑拖拽/缩放。

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


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(event.position, 1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(event.position, 1.0 / 1.1)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_on_map_pressed(event.position)
		elif event.button_index == drag_button:
			if event.pressed:
				_start_drag(event.position)
			else:
				_end_drag()

	if event is InputEventMouseMotion:
		if _is_dragging:
			_update_drag(event.position)
		else:
			_update_hover(event.position)


## ============================================================
## 屏幕 ↔ 世界坐标转换（通过 Camera2D）
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
## 点击处理
## ============================================================

func _on_map_pressed(screen_pos: Vector2) -> void:
	var world = _screen_to_world(screen_pos)
	var grid_pos = _grid_utils.screen_to_grid_precise(world.x, world.y)

	if not _grid_utils.is_in_bounds(grid_pos):
		return

	# Check for pending dispatch destination selection
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

	# If an army is selected, try to move it
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

	# Check if destination is reachable
	var reachable = _get_army_reachable(army)
	if not grid_pos in reachable:
		print("MapInput: Destination not reachable")
		return

	# Check for enemy at destination
	var enemy = GameManager.get_army_at(grid_pos.x, grid_pos.y)
	if enemy and enemy.faction_id != army.faction_id:
		_resolve_combat(army, enemy)

	# Check for enemy city at destination (siege)
	if army.is_alive():
		var city = GameManager.get_city_at(grid_pos.x, grid_pos.y)
		if city and city.faction_id != army.faction_id:
			_resolve_siege(army, city)

	# Move army (if still alive)
	if army.is_alive():
		army.position = grid_pos
	army.has_moved = true

	var remaining = reachable[grid_pos]
	print("MapInput: Army %d moved to (%d, %d)" % [army.id, grid_pos.x, grid_pos.y])

	# Refresh map and clear move range
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

	var atk_stats = {"tong": atk_cmdr.get_stat("tong") if atk_cmdr else 50, "wu": atk_cmdr.get_stat("wu") if atk_cmdr else 50}
	var def_stats = {"tong": def_cmdr.get_stat("tong") if def_cmdr else 50, "wu": def_cmdr.get_stat("wu") if def_cmdr else 50}

	var atk_power = int((atk_stats.wu * 0.6 + atk_stats.tong * 0.4) * sqrt(attacker.troops / 1000.0) * (attacker.morale / 100.0))
	var def_power = int((def_stats.wu * 0.6 + def_stats.tong * 0.4) * sqrt(defender.troops / 1000.0) * (defender.morale / 100.0))

	print("  Attacker power: %d, Defender power: %d" % [atk_power, def_power])

	# Attacker attacks
	var dmg_to_def = maxi(1, int(atk_power * 0.1))
	defender.take_damage(dmg_to_def)
	print("  Attacker deals %d damage, defender troops: %d" % [dmg_to_def, defender.troops])

	# Defender counter-attacks (if alive)
	if defender.is_alive():
		var dmg_to_atk = maxi(1, int(def_power * 0.1))
		attacker.take_damage(dmg_to_atk)
		print("  Defender deals %d damage, attacker troops: %d" % [dmg_to_atk, attacker.troops])

	# Morale loss
	attacker.morale = maxi(0, attacker.morale - 10)
	defender.morale = maxi(0, defender.morale - 10)

	# Results
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

	# City durability defense
	var dmg_to_city = maxi(1, siege_power)
	city.durability -= dmg_to_city
	print("  Siege damage to city: %d, durability: %d/%d" % [dmg_to_city, city.durability, city.max_durability])

	# City garrison fights back
	var garrison_dmg = maxi(1, int(city.get_total_troops() / 50))
	army.take_damage(garrison_dmg)
	print("  Garrison deals %d damage, army troops: %d" % [garrison_dmg, army.troops])

	# Check if city falls
	if city.durability <= 0:
		city.durability = 0
		var old_faction = city.faction_id
		city.faction_id = army.faction_id
		var faction = GameManager.get_faction(army.faction_id)
		if faction:
			faction.cities.append(city.id)
		# Remove from old faction
		var old_fac = GameManager.get_faction(old_faction)
		if old_fac:
			old_fac.cities.erase(city.id)
		print("  %s has fallen! Now belongs to %s" % [city.name, faction.name if faction else "?"])
		EventBus.city_captured.emit(city.id, old_faction, army.faction_id)

	print("=== SIEGE END ===")


func _get_army_reachable(army: Army) -> Dictionary:
	# Calculate move points based on commander's stats
	var commander = GameManager.get_officer(army.commander_id)
	var move_points = 10
	if commander:
		move_points = commander.get_stat("tong") / 5 + 5

	# Terrain costs
	var terrain_costs = {
		"plain": 1, "grassland": 1, "road": 1,
		"forest": 2, "hill": 2, "wetland": 3, "ford": 3,
		"mountain": 4, "dense_forest": 4, "desert": 2,
	}

	# Blocked vertices (other armies, cities, etc.)
	var blocked: Array = []
	for a in GameManager.armies.values():
		if a.id != army.id and a.is_alive():
			blocked.append(a.position)

	return _grid_utils.get_reachable_vertices(army.position, move_points, terrain_costs, blocked)


func _on_map_double_clicked(grid_pos: Vector2i) -> void:
	var city = GameManager.get_city_at(grid_pos.x, grid_pos.y)
	if city:
		print("Double clicked city: %s" % city.name)


## ============================================================
## 悬停处理
## ============================================================

func _update_hover(screen_pos: Vector2) -> void:
	var grid_pos = _screen_to_grid(screen_pos)

	if grid_pos != _last_hover and _grid_utils.is_in_bounds(grid_pos):
		_last_hover = grid_pos
		EventBus.map_hover_changed.emit(grid_pos)


## ============================================================
## 拖拽处理（移动 Camera2D，无需重绘）
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
## 缩放处理（Camera2D.zoom + 定位光标下世界点）
## ============================================================

func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	if not _camera:
		return

	var new_zoom = _camera.zoom * factor
	new_zoom.x = clampf(new_zoom.x, 0.2, 4.0)
	new_zoom.y = clampf(new_zoom.y, 0.2, 4.0)

	if is_equal_approx(new_zoom.x, _camera.zoom.x):
		return

	# 保持光标下的世界点不变
	var world_under_cursor = _screen_to_world(screen_pos)
	_camera.zoom = new_zoom
	# 重新计算 camera 位置使得光标下的世界点保持在原位
	var vp_size = get_viewport().get_visible_rect().size
	var center = vp_size / 2.0
	_camera.position = world_under_cursor - (screen_pos - center) / _camera.zoom

	# tile 尺寸保持不变 — Camera2D.zoom 已处理视觉缩放
