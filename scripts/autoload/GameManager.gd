extends Node
## 游戏状态管理器单例

enum GameState { MAIN_MENU, SCENARIO_SETUP, PLAYING, PAUSED, GAME_OVER }
var state: GameState = GameState.MAIN_MENU

var factions: Dictionary = {}
var cities: Dictionary = {}
var officers: Dictionary = {}
var armies: Dictionary = {}
var counties_runtime: Dictionary = {}

var player_faction_id: String = ""
var current_turn: int = 1
var current_year: int = 207
var current_faction_index: int = 0
var faction_turn_order: Array = []
var turn_phase: String = "player"

var _next_army_id: int = 1000
var selected_city_id: String = ""
var selected_county_id: String = ""
var selected_army_id: int = -1
var hovered_vertex: Vector2i = Vector2i(-1, -1)
var battle_log: Array = []

# 格子 → 城市/郡 快速索引（支持七格扩张城 + 单格郡）
var _tile_to_city: Dictionary = {}
var _tile_to_commandery: Dictionary = {}


func _ready() -> void:
	print("GameManager: Initialized")


func new_game(scenario_id: String) -> void:
	print("GameManager: Starting new game with scenario '%s'" % scenario_id)
	var scenario = DataManager.load_scenario(scenario_id)
	if scenario.is_empty():
		push_error("GameManager: Failed to load scenario")
		return
	_reset_state()
	_setup_from_scenario(scenario)
	state = GameState.PLAYING
	EventBus.game_resumed.emit()
	print("GameManager: Game started. Player faction: %s" % player_faction_id)


func _reset_state() -> void:
	factions.clear()
	cities.clear()
	officers.clear()
	armies.clear()
	counties_runtime.clear()
	battle_log.clear()
	_next_army_id = 1000
	current_turn = 1
	current_faction_index = 0
	faction_turn_order.clear()
	selected_city_id = ""
	selected_county_id = ""
	selected_army_id = -1
	_tile_to_city.clear()
	_tile_to_commandery.clear()


func _setup_from_scenario(scenario: Dictionary) -> void:
	var sc = scenario.get("scenario", {})
	current_year = sc.get("year", 207)
	current_turn = sc.get("start_turn", 1)

	# Create factions
	var faction_list = scenario.get("factions", [])
	for fd in faction_list:
		var faction = Faction.new()
		faction.from_dict(fd)
		factions[faction.id] = faction

	# Create cities (府) from prefecture data
	var all_city_data = DataManager.get_all_cities()
	for cd in all_city_data:
		var city = City.new()
		city.from_dict(cd)
		cities[city.id] = city

	# Create commandery entities (郡) — 单格，独立可交互
	var all_cmd_data = DataManager.get_all_commanderies()
	for cmd in all_cmd_data:
		var cmd_city = City.new()
		var is_pass = (cmd.get("type", "") == "pass")
		var cmd_type = "pass" if is_pass else "commandery"
		var cmd_tiles = cmd.get("tiles", [])
		var cmd_center = cmd.get("center", {})
		if cmd_center.is_empty() and not cmd_tiles.is_empty():
			cmd_center = {"x": cmd_tiles[0][0], "y": cmd_tiles[0][1]}
		var cmd_durability = cmd.get("max_durability", 2800 if is_pass else 800)
		var synthetic_county = {
			"id": cmd["id"],
			"name": cmd["name"],
			"center": cmd_center,
			"size": "small",
			"prefecture_id": cmd.get("prefecture_id", ""),
			"capabilities": cmd.get("capabilities", []),
			"troops": 500,
		}
		var cmd_dict = {
			"id": cmd["id"],
			"name": cmd["name"],
			"type": cmd_type,
			"center": cmd_center,
			"position": cmd_center,
			"tiles": cmd_tiles,
			"max_durability": cmd_durability,
			"defense_bonus": cmd.get("defense_bonus", 0),
			"prefecture_id": cmd.get("prefecture_id", ""),
			"capabilities": cmd.get("capabilities", []),
			"counties": [synthetic_county],
		}
		cmd_city.from_dict(cmd_dict)
		cmd_city.type = cmd_type
		cities[cmd_city.id] = cmd_city

	# Assign cities (府+郡) to factions
	for fd in faction_list:
		var fid = fd.get("id", "")
		# 兼容 "prefectures" 和 "cities"
		var pf_ids = fd.get("prefectures", fd.get("cities", []))
		for cid in pf_ids:
			if cid in cities:
				cities[cid].faction_id = fid
		# 分配郡
		var cmd_ids = fd.get("commanderies", [])
		for cid in cmd_ids:
			if cid in cities:
				cities[cid].faction_id = fid
		if fid in factions:
			factions[fid].gold = fd.get("gold", 0)
			factions[fid].food = fd.get("food", 0)

	# Create officers and assign to cities
	var all_officer_data = DataManager.officers_by_id
	var assignments = scenario.get("officer_assignments", {})
	for fid in assignments:
		var officer_ids = assignments[fid]
		var city_idx = 0
		var fcs = factions[fid].cities if fid in factions else []
		for oid in officer_ids:
			if not (oid in all_officer_data):
				continue
			var odata = all_officer_data[oid]
			var officer = Officer.new()
			officer.from_dict(odata)
			officer.faction_id = fid
			officer.status = "一般"
			officer.loyalty = 80
			var okey = int(oid)
			officers[okey] = officer

			if fid in factions:
				factions[fid].officers.append(officer.id)

			if not fcs.is_empty():
				var target_city = fcs[city_idx % fcs.size()]
				city_idx += 1
				if target_city in cities:
					cities[target_city].officers.append(officer.id)
					officer.location = target_city

	# Create unaligned officers (nested inside officer_assignments in JSON)
	var in_the_wild = assignments.get("unaligned_in_the_wild", [])
	var locations = scenario.get("officer_locations", {})
	for oid in in_the_wild:
		if oid in all_officer_data:
			var officer = Officer.new()
			officer.from_dict(all_officer_data[oid])
			officer.faction_id = ""
			officer.status = "在野"
			officer.loyalty = 50
			var loc = locations.get(str(oid), "")
			officer.location = loc
			var okey = int(oid)
			officers[okey] = officer

		print("DEBUG: checking unaligned officers...")
	var wild_count = 0
	for o in officers.values():
		if o.status == "在野":
			wild_count += 1
			print("  Unaligned: %s at %s" % [o.name, o.location])
	print("DEBUG: %d unaligned officers found" % wild_count)

	# Create initial armies
	var initial_armies = scenario.get("initial_armies", {})
	for fid in initial_armies:
		var army_list = initial_armies[fid]
		for ad in army_list:
			var army = Army.new()
			army.id = _next_army_id
			_next_army_id += 1
			army.from_dict(ad)
			army.faction_id = fid
			var city_id = ad.get("city", "")
			if city_id in cities:
				army.position = cities[city_id].position
			armies[army.id] = army
			if fid in factions:
				factions[fid].armies.append(army.id)

	# Set faction turn order
	var playable = sc.get("playable_factions", [])
	faction_turn_order = playable.duplicate()
	for fid in factions:
		if fid not in faction_turn_order:
			faction_turn_order.append(fid)

	# Setup initial diplomacy
	var faction_ids = factions.keys()
	for i in range(faction_ids.size()):
		for j in range(i + 1, faction_ids.size()):
			var a = faction_ids[i]
			var b = faction_ids[j]
			if not factions[a].diplomacy.has(b):
				factions[a].diplomacy[b] = "neutral"
			if not factions[b].diplomacy.has(a):
				factions[b].diplomacy[a] = "neutral"

		# Auto-assign faction leaders as city governors (太守)
	for fd in faction_list:
		var fid = fd.get("id", "")
		var lid = fd.get("leader_id", 0)
		if fid in factions and lid > 0:
			var pf = fd.get("prefectures", fd.get("cities", []))
			var fcs = pf if pf is Array else []
			if not fcs.is_empty() and fcs[0] in cities:
				cities[fcs[0]].governor_id = lid
				var leader = get_officer(lid)
				if leader:
					leader.location = fcs[0]
					leader.status = "太守"
					print("Assigned %s as governor of %s" % [leader.name, cities[fcs[0]].name])

	# Build tile-to-city index for fast lookup
	_build_tile_to_city_index()

	# Set player faction
	player_faction_id = playable[0] if not playable.is_empty() else ""


func _build_tile_to_city_index() -> void:
	_tile_to_city.clear()
	_tile_to_commandery.clear()
	for city in cities.values():
		if city.type == "commandery" or city.type == "pass":
			# 郡/关卡 — 单格或多格
			if city.type == "pass" and not city.tiles.is_empty():
				for tile in city.tiles:
					var tv = Vector2i(tile[0], tile[1])
					_tile_to_city[str(tv)] = city.id
					_tile_to_commandery[str(tv)] = city.id
			else:
				_tile_to_city[str(city.position)] = city.id
				_tile_to_commandery[str(city.position)] = city.id
		elif city.is_expanded():
			# 府 — 七格六边形
			for tile in city.get_hex_tiles():
				_tile_to_city[str(tile)] = city.id
		else:
			_tile_to_city[str(city.position)] = city.id


func get_officer(officer_id: int) -> Officer:
	if not officers.has(officer_id):
		print("get_officer(%d): NOT FOUND in dict (size=%d)" % [officer_id, officers.size()])
	return officers.get(officer_id, null)


func get_faction(faction_id: String) -> Faction:
	return factions.get(faction_id, null)


func get_city(city_id: String) -> City:
	return cities.get(city_id, null)


func get_army(army_id: int) -> Army:
	return armies.get(army_id, null)


func get_player_faction() -> Faction:
	return factions.get(player_faction_id, null)


func get_player_cities() -> Array:
	var result: Array = []
	var faction = get_player_faction()
	if faction:
		for cid in faction.cities:
			if cid in cities:
				result.append(cities[cid])
		for cid in faction.commanderies:
			if cid in cities:
				result.append(cities[cid])
	return result


func get_army_at(x: int, y: int) -> Army:
	for army in armies.values():
		if army.position.x == x and army.position.y == y and army.is_alive():
			return army
	return null


func get_city_at(x: int, y: int) -> City:
	var key = str(Vector2i(x, y))
	if key in _tile_to_city:
		return cities.get(_tile_to_city[key], null)
	return null


func get_commandery_at(x: int, y: int) -> City:
	var key = str(Vector2i(x, y))
	if key in _tile_to_commandery:
		return cities.get(_tile_to_commandery[key], null)
	return null


func get_pass_at(x: int, y: int) -> Dictionary:
	for pass_data in DataManager.get_all_passes():
		var tiles = pass_data.get("tiles", [])
		if tiles.size() >= 2:
			for t in tiles:
				if t.get("x", -1) == x and t.get("y", -1) == y:
					return pass_data
		else:
			var p = pass_data.get("position", {})
			if p.get("x", -1) == x and p.get("y", -1) == y:
				return pass_data
	return {}


func get_pass_data(pass_id: String) -> Dictionary:
	for pass_data in DataManager.get_all_passes():
		if pass_data.get("id", "") == pass_id:
			return pass_data
	return {}


func get_harbor_at(x: int, y: int) -> Dictionary:
	for harbor_data in DataManager.get_all_harbors():
		var p = harbor_data.get("position", {})
		if p.get("x", -1) == x and p.get("y", -1) == y:
			return harbor_data
	return {}


func select_vertex(x: int, y: int) -> void:
	hovered_vertex = Vector2i(x, y)
	var city = get_city_at(x, y)
	if city:
		selected_city_id = city.id
		EventBus.map_city_clicked.emit(city.id)
		return
	var commandery = get_commandery_at(x, y)
	if commandery:
		selected_city_id = commandery.id
		EventBus.map_city_clicked.emit(commandery.id)
		return
	var army = get_army_at(x, y)
	if army:
		selected_army_id = army.id
		EventBus.map_army_clicked.emit(army.id)
		return
	var pass_data = get_pass_at(x, y)
	if not pass_data.is_empty():
		EventBus.map_pass_clicked.emit(pass_data.get("id", ""))
		return
	var harbor_data = get_harbor_at(x, y)
	if not harbor_data.is_empty():
		EventBus.map_harbor_clicked.emit(harbor_data.get("id", ""))
		return
	EventBus.map_vertex_clicked.emit(Vector2i(x, y))
