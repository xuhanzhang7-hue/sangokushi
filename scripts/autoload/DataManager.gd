extends Node
## 数据管理器单例 — 负责所有 JSON 数据的加载、缓存和查询

# 原始数据缓存
var _officers_raw: Array = []
var _cities_raw: Array = []
var _skills_raw: Dictionary = {}
var _units_raw: Dictionary = {}
var _techs_raw: Dictionary = {}
var _events_raw: Array = []

# 地图数据
var _terrain_data: Dictionary = {}
var _rivers_data: Array = []
var _passes_data: Array = []
var _harbors_data: Array = []
var _roads_data: Array = []
var _resources_data: Array = []

# 展开后的顶点数据（从terrain regions展开）
var _vertex_terrain: Dictionary = {}   # {Vector2i → terrain_type}
var _vertex_height: Dictionary = {}     # {Vector2i → height}
var _vertex_features: Dictionary = {}    # {Vector2i → feature_data}
var _county_vertices: Dictionary = {}    # {county_id → Array[Vector2i]}

# 快速索引
var officers_by_id: Dictionary = {}
var cities_by_id: Dictionary = {}
var counties_by_id: Dictionary = {}
var passes_by_id: Dictionary = {}
var harbors_by_id: Dictionary = {}

# 地图尺寸
var map_width: int = 200
var map_height: int = 180


func _ready() -> void:
	_load_all_data()


## ============================================================
## 数据加载
## ============================================================

func _load_all_data() -> void:
	_load_officers()
	_load_cities()
	_load_skills()
	_load_units()
	_load_techs()
	_load_events()
	_load_map_data()


func _load_officers() -> void:
	var file = FileAccess.open("res://data/officers.json", FileAccess.READ)
	if file:
		var json = JSON.parse_string(file.get_as_text())
		file.close()
		if json and "officers" in json:
			_officers_raw = json["officers"]
			for o in _officers_raw:
				officers_by_id[o["id"]] = o
			print("DataManager: Loaded %d officers" % _officers_raw.size())
	else:
		push_error("DataManager: Failed to load officers.json")


func _load_cities() -> void:
	var file = FileAccess.open("res://data/cities.json", FileAccess.READ)
	if file:
		var json = JSON.parse_string(file.get_as_text())
		file.close()
		if json and "cities" in json:
			_cities_raw = json["cities"]
			for c in _cities_raw:
				cities_by_id[c["id"]] = c
				# 索引郡
				if "counties" in c:
					for county in c["counties"]:
						county["city_id"] = c["id"]
						counties_by_id[county["id"]] = county
			print("DataManager: Loaded %d cities with counties" % _cities_raw.size())
	else:
		push_error("DataManager: Failed to load cities.json")


func _load_skills() -> void:
	var file = FileAccess.open("res://data/skills.json", FileAccess.READ)
	if file:
		var json = JSON.parse_string(file.get_as_text())
		file.close()
		if json:
			_skills_raw = json


func _load_units() -> void:
	var file = FileAccess.open("res://data/units.json", FileAccess.READ)
	if file:
		var json = JSON.parse_string(file.get_as_text())
		file.close()
		if json:
			_units_raw = json


func _load_techs() -> void:
	var file = FileAccess.open("res://data/techs.json", FileAccess.READ)
	if file:
		var json = JSON.parse_string(file.get_as_text())
		file.close()
		if json:
			_techs_raw = json


func _load_events() -> void:
	# 事件数据嵌在剧本文件中，此方法保留用于未来独立事件文件
	if not FileAccess.file_exists("res://data/events.json"):
		print("DataManager: No standalone events.json, events loaded from scenarios")
		return
	var file = FileAccess.open("res://data/events.json", FileAccess.READ)
	if file:
		var json = JSON.parse_string(file.get_as_text())
		file.close()
		if json:
			_events_raw = json.get("events", [])


func _load_map_data() -> void:
	_load_terrain()
	_load_rivers()
	_load_passes()
	_load_harbors()
	_load_roads()
	_load_resources()
	_expand_terrain_regions()


func _load_terrain() -> void:
	var file = FileAccess.open("res://data/map/terrain.json", FileAccess.READ)
	if file:
		var json = JSON.parse_string(file.get_as_text())
		file.close()
		if json:
			_terrain_data = json
			map_width = json.get("width", 200)
			map_height = json.get("height", 180)
			print("DataManager: Loaded terrain data (%dx%d)" % [map_width, map_height])


func _load_rivers() -> void:
	var file = FileAccess.open("res://data/map/rivers.json", FileAccess.READ)
	if file:
		var json = JSON.parse_string(file.get_as_text())
		file.close()
		if json:
			_rivers_data = json.get("rivers", [])


func _load_passes() -> void:
	var file = FileAccess.open("res://data/map/passes.json", FileAccess.READ)
	if file:
		var json = JSON.parse_string(file.get_as_text())
		file.close()
		if json:
			_passes_data = json.get("passes", [])
			for p in _passes_data:
				passes_by_id[p["id"]] = p


func _load_harbors() -> void:
	var file = FileAccess.open("res://data/map/harbors.json", FileAccess.READ)
	if file:
		var json = JSON.parse_string(file.get_as_text())
		file.close()
		if json:
			_harbors_data = json.get("harbors", [])
			for h in _harbors_data:
				harbors_by_id[h["id"]] = h


func _load_roads() -> void:
	var file = FileAccess.open("res://data/map/roads.json", FileAccess.READ)
	if file:
		var json = JSON.parse_string(file.get_as_text())
		file.close()
		if json:
			_roads_data = json.get("roads", [])


func _load_resources() -> void:
	var file = FileAccess.open("res://data/map/resources.json", FileAccess.READ)
	if file:
		var json = JSON.parse_string(file.get_as_text())
		file.close()
		if json:
			_resources_data = json.get("resources", [])


func _compare_region_order(a: Dictionary, b: Dictionary) -> bool:
	return a.get("order", 0) < b.get("order", 0)


## ============================================================
## 地形展开 — 将区域定义展开为逐顶点数据
## ============================================================

func _expand_terrain_regions() -> void:
	_vertex_terrain.clear()
	_vertex_height.clear()

	var default_terrain = _terrain_data.get("default_terrain", "plain")
	var default_height = _terrain_data.get("default_height", 0)
	var regions = _terrain_data.get("regions", [])

	# 按order排序（确保后定义的区域覆盖先定义的）
	regions.sort_custom(_compare_region_order)

	for region in regions:
		var rect = region.get("rect", {})
		var rx = rect.get("x", 0)
		var ry = rect.get("y", 0)
		var rw = rect.get("w", 10)
		var rh = rect.get("h", 10)
		var rtype = region.get("type", default_terrain)
		var rheight = region.get("height", default_height)

		for x in range(rx, rx + rw):
			for y in range(ry, ry + rh):
				if x >= 0 and x < map_width and y >= 0 and y < map_height:
					var key = "%d,%d" % [x, y]
					_vertex_terrain[key] = rtype
					_vertex_height[key] = rheight

	# 应用河流顶点
	for river in _rivers_data:
		var path = river.get("path", [])
		for point in path:
			var x = point[0]
			var y = point[1]
			if x >= 0 and x < map_width and y >= 0 and y < map_height:
				var key = "%d,%d" % [x, y]
				_vertex_terrain[key] = "water"

	# 应用道路顶点
	for road in _roads_data:
		var path = road.get("path", [])
		for point in path:
			var x = point[0]
			var y = point[1]
			if x >= 0 and x < map_width and y >= 0 and y < map_height:
				var key = "%d,%d" % [x, y]
				var existing = _vertex_terrain.get(key, "")
				if existing == "plain":
					_vertex_terrain[key] = "road"

	# 应用overrides
	var overrides = _terrain_data.get("overrides", [])
	for ov in overrides:
		var x = ov.get("x", 0)
		var y = ov.get("y", 0)
		if x >= 0 and x < map_width and y >= 0 and y < map_height:
			var key = "%d,%d" % [x, y]
			_vertex_terrain[key] = ov.get("terrain", default_terrain)
			_vertex_height[key] = ov.get("height", default_height)

	print("DataManager: Expanded terrain for %d vertices" % _vertex_terrain.size())


## ============================================================
## 查询方法
## ============================================================

## 获取顶点地形类型
func get_terrain_at(x: int, y: int) -> String:
	var key = "%d,%d" % [x, y]
	return _vertex_terrain.get(key, "plain")


## 获取顶点高度
func get_height_at(x: int, y: int) -> int:
	var key = "%d,%d" % [x, y]
	return _vertex_height.get(key, 0)


## 判断顶点是否可通过
func is_passable(x: int, y: int) -> bool:
	var terrain = get_terrain_at(x, y)
	return terrain not in ["water", "ocean", "high_mountain"]


## 获取地形移动消耗
func get_terrain_move_cost(x: int, y: int) -> int:
	var terrain = get_terrain_at(x, y)
	match terrain:
		"plain", "grassland": return 1
		"road": return 0.5
		"forest", "hill", "wetland", "ford": return 2
		"mountain", "dense_forest": return 3
		"desert": return 2
		_: return 1


## 获取武将原始数据
func get_officer_data(officer_id: int) -> Dictionary:
	return officers_by_id.get(officer_id, {})


## 获取势力在野/未发现武将
func get_unaligned_officers() -> Array:
	var result: Array = []
	for o in _officers_raw:
		if o.get("faction_id", "") == "":
			result.append(o)
	return result


## 获取技能定义
func get_skill_definition(skill_id: String) -> Dictionary:
	if "skills" in _skills_raw:
		for s in _skills_raw["skills"]:
			if s.get("id") == skill_id:
				return s
	return {}


## 获取兵种定义
func get_unit_definition(unit_id: String) -> Dictionary:
	if "units" in _units_raw:
		for u in _units_raw["units"]:
			if u.get("id") == unit_id:
				return u
	return {}


## 获取势力兵种列表
func get_available_units(faction_id: String, city_id: String, county_ids: Array) -> Array:
	var units: Array = []
	if "units" not in _units_raw:
		return units

	for u in _units_raw["units"]:
		if u.get("water_only", false):
			# 检查是否有港口或造船所
			var has_shipyard = false
			for cid in county_ids:
				var county = counties_by_id.get(cid, {})
				for f in county.get("facilities", []):
					if f.get("type") == "shipyard":
						has_shipyard = true
						break
			if not has_shipyard:
				continue
		units.append(u)
	return units


## 获取所有城市数据
func get_all_cities() -> Array:
	return _cities_raw


## 获取所有关隘数据
func get_all_passes() -> Array:
	return _passes_data


## 获取所有港口数据
func get_all_harbors() -> Array:
	return _harbors_data


## 获取所有河流数据
func get_all_rivers() -> Array:
	return _rivers_data


## 获取所有道路数据
func get_all_roads() -> Array:
	return _roads_data


## 获取所有资源点
func get_all_resources() -> Array:
	return _resources_data


## 获取科技树定义
func get_tech_tree(tech_id: String) -> Dictionary:
	if "tech_trees" in _techs_raw:
		return _techs_raw["tech_trees"].get(tech_id, {})
	return {}


## 获取全部科技树
func get_all_tech_trees() -> Dictionary:
	return _techs_raw.get("tech_trees", {})


## 获取事件列表
func get_all_events() -> Array:
	return _events_raw


## 加载剧本
func load_scenario(scenario_id: String) -> Dictionary:
	var path = "res://data/scenarios/%s.json" % scenario_id
	var file = FileAccess.open(path, FileAccess.READ)
	if file:
		var json = JSON.parse_string(file.get_as_text())
		file.close()
		if json:
			print("DataManager: Loaded scenario '%s'" % scenario_id)
			return json
	push_error("DataManager: Failed to load scenario '%s'" % scenario_id)
	return {}
