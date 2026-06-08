extends Node
## 数据管理器单例 — 负责所有 JSON 数据的加载、缓存和查询
## 支持 Offset Square tile 网格地形

# 原始数据缓存
var _officers_raw: Array = []
var _cities_raw: Array = []
var _skills_raw: Dictionary = {}
var _units_raw: Dictionary = {}
var _techs_raw: Dictionary = {}
var _events_raw: Array = []

# Tile 地形数据（2D 网格）
var _terrain_grid: Array = []      # Array[Array[String]] — 按 [gy][gx] 索引
var _height_grid: Array = []       # Array[Array[int]] — 同形
var map_width: int = 240
var map_height: int = 360

# 地图要素：关隘、港口
var _passes_data: Array = []
var _harbors_data: Array = []
var _resources_data: Array = []

# 快速索引
var officers_by_id: Dictionary = {}
var cities_by_id: Dictionary = {}
var counties_by_id: Dictionary = {}
var passes_by_id: Dictionary = {}
var harbors_by_id: Dictionary = {}


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
	if not FileAccess.file_exists("res://data/events.json"):
		print("DataManager: No standalone events.json, events loaded from scenarios")
		return
	var file = FileAccess.open("res://data/events.json", FileAccess.READ)
	if file:
		var json = JSON.parse_string(file.get_as_text())
		file.close()
		if json:
			_events_raw = json.get("events", [])


## ============================================================
## 地图数据加载（tile 网格）
## ============================================================

func _load_map_data() -> void:
	_load_terrain()
	_load_passes()
	_load_harbors()
	_load_resources()


func _load_terrain() -> void:
	var file = FileAccess.open("res://data/map/terrain.json", FileAccess.READ)
	if file:
		var json = JSON.parse_string(file.get_as_text())
		file.close()
		if json:
			map_width = json.get("width", 120)
			map_height = json.get("height", 90)
			_terrain_grid = json.get("grid", [])
			_height_grid = json.get("heights", [])
			print("DataManager: Loaded terrain grid (%dx%d)" % [map_width, map_height])
			# Validate
			if _terrain_grid.size() != map_height:
				push_error("DataManager: terrain grid row count mismatch! expected %d got %d" % [map_height, _terrain_grid.size()])
			return

	# Fallback: all plains
	push_error("DataManager: Failed to load terrain.json, using default plains grid")
	_terrain_grid = []
	for gy in range(map_height):
		var row: Array = []
		for _gx in range(map_width):
			row.append("plain")
		_terrain_grid.append(row)


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


func _load_resources() -> void:
	var file = FileAccess.open("res://data/map/resources.json", FileAccess.READ)
	if file:
		var json = JSON.parse_string(file.get_as_text())
		file.close()
		if json:
			_resources_data = json.get("resources", [])


## ============================================================
## Tile 地形查询
## ============================================================

## 获取 tile 地形类型
func get_terrain_at(gx: int, gy: int) -> String:
	if gy >= 0 and gy < _terrain_grid.size():
		var row = _terrain_grid[gy]
		if gx >= 0 and gx < row.size():
			return row[gx]
	return "plain"


## 获取 tile 高度
func get_height_at(gx: int, gy: int) -> int:
	if gy >= 0 and gy < _height_grid.size():
		var row = _height_grid[gy]
		if gx >= 0 and gx < row.size():
			return row[gx]
	return 0


## 判断 tile 是否可通过（陆军）
func is_passable(gx: int, gy: int) -> bool:
	var terrain = get_terrain_at(gx, gy)
	return terrain not in ["water", "ocean"]


## 获取地形移动消耗
func get_terrain_move_cost(gx: int, gy: int) -> int:
	var terrain = get_terrain_at(gx, gy)
	match terrain:
		"plain", "grassland": return 1
		"road", "guandao", "city": return 1
		"forest", "hill", "wetland", "ford": return 2
		"mountain", "dense_forest": return 3
		"desert": return 2
		"water", "ocean": return 99
		_: return 1


## ============================================================
## 地图要素查询
## ============================================================

func get_all_passes() -> Array:
	return _passes_data


func get_all_harbors() -> Array:
	return _harbors_data


func get_all_resources() -> Array:
	return _resources_data


## ============================================================
## 武将 / 技能 / 兵种 / 科技 查询
## ============================================================

func get_officer_data(officer_id: int) -> Dictionary:
	return officers_by_id.get(officer_id, {})


func get_unaligned_officers() -> Array:
	var result: Array = []
	for o in _officers_raw:
		if o.get("faction_id", "") == "":
			result.append(o)
	return result


func get_skill_definition(skill_id: String) -> Dictionary:
	if "skills" in _skills_raw:
		for s in _skills_raw["skills"]:
			if s.get("id") == skill_id:
				return s
	return {}


func get_unit_definition(unit_id: String) -> Dictionary:
	if "units" in _units_raw:
		for u in _units_raw["units"]:
			if u.get("id") == unit_id:
				return u
	return {}


func get_available_units(_faction_id: String, _city_id: String, county_ids: Array) -> Array:
	var units: Array = []
	if "units" not in _units_raw:
		return units
	for u in _units_raw["units"]:
		if u.get("water_only", false):
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


func get_all_cities() -> Array:
	return _cities_raw


func get_tech_tree(tech_id: String) -> Dictionary:
	if "tech_trees" in _techs_raw:
		return _techs_raw["tech_trees"].get(tech_id, {})
	return {}


func get_all_tech_trees() -> Dictionary:
	return _techs_raw.get("tech_trees", {})


func get_all_events() -> Array:
	return _events_raw


## ============================================================
## 编辑器
## ============================================================

## 直接设置 tile 地形（编辑器用）
func set_terrain_at(gx: int, gy: int, terrain: String) -> void:
	if gy >= 0 and gy < _terrain_grid.size():
		var row = _terrain_grid[gy]
		if gx >= 0 and gx < row.size():
			row[gx] = terrain


## 添加城市到 cities.json（编辑器用）
func add_city(city_id: String, name: String, gx: int, gy: int) -> void:
	# Read current cities
	var path = "res://data/cities.json"
	var data: Dictionary
	var file = FileAccess.open(path, FileAccess.READ)
	if file:
		var text = file.get_as_text()
		file.close()
		data = JSON.parse_string(text) if text else {}
	else:
		data = {"cities": []}

	if "cities" not in data:
		data["cities"] = []

	# Check if city already exists
	for c in data["cities"]:
		if c.get("id") == city_id:
			c["position"] = {"x": gx, "y": gy}
			print("DataManager: Updated existing city %s position" % name)
			_save_cities(data)
			return

	# Add new city
	var new_city = {
		"id": city_id,
		"name": name,
		"position": {"x": gx, "y": gy},
		"max_durability": 2000,
		"counties": [
			{"id": city_id + "_01", "name": name, "center": {"x": gx, "y": gy}, "size": "medium"},
			{"id": city_id + "_02", "name": name + "郊", "center": {"x": gx + 2, "y": gy}, "size": "small"},
		]
	}
	data["cities"].append(new_city)
	_save_cities(data)
	# Also update runtime cache
	cities_by_id[city_id] = new_city
	for county in new_city["counties"]:
		counties_by_id[county["id"]] = county
	_cities_raw.append(new_city)
	print("DataManager: Added city %s at (%d,%d)" % [name, gx, gy])


func _save_cities(data: Dictionary) -> void:
	var file = FileAccess.open("res://data/cities.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t", false, true))
		file.close()


## 保存地形到 JSON
func save_terrain() -> void:
	var output = {
		"width": map_width,
		"height": map_height,
		"default_terrain": "plain",
		"grid": _terrain_grid.duplicate(true),
		"heights": _height_grid.duplicate(true),
	}
	var file = FileAccess.open("res://data/map/terrain.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(output, "\t"))
		file.close()
		print("DataManager: Terrain saved to terrain.json")
	else:
		push_error("DataManager: Failed to save terrain.json")


## ============================================================
## 剧本
## ============================================================

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
