class_name Faction extends RefCounted
## 势力数据类

var id: String
var name: String
var leader_id: int = 0
var color: Color = Color.WHITE
var cities: Array = []       # 城市ID列表
var officers: Array = []        # 武将ID列表
var gold: int = 0
var food: int = 0
var tech_levels: Dictionary = {}     # {tech_tree_id: level}
var diplomacy: Dictionary = {}       # {faction_id: "allied"/"neutral"/"war"/"truce"}
var armies: Array = []          # 部队ID列表


func from_dict(d: Dictionary) -> void:
	id = d.get("id", "")
	name = d.get("name", "")
	leader_id = d.get("leader_id", 0); if leader_id == null: leader_id = 0
	cities = d.get("cities", [])
	gold = d.get("gold", 0)
	food = d.get("food", 0)
	tech_levels = d.get("tech_levels", {})

	var color_str = d.get("color", "#FFFFFF")
	color = Color.from_string(color_str, Color.WHITE)


func get_tech_level(tech_tree_id: String) -> int:
	return tech_levels.get(tech_tree_id, 0)


func set_tech_level(tech_tree_id: String, level: int) -> void:
	tech_levels[tech_tree_id] = level


func get_total_troops(cities_dict: Dictionary) -> int:
	var total = 0
	for city_id in cities:
		if city_id in cities_dict:
			total += cities_dict[city_id].get_total_troops()
	return total


func get_city_count() -> int:
	return cities.size()


func is_at_war_with(faction_id: String) -> bool:
	return diplomacy.get(faction_id, "neutral") == "war"


func is_allied_with(faction_id: String) -> bool:
	return diplomacy.get(faction_id, "neutral") == "allied"


func declare_war(target: String) -> void:
	diplomacy[target] = "war"


func make_alliance(target: String) -> void:
	diplomacy[target] = "allied"


func has_city(city_id: String) -> bool:
	return city_id in cities


func add_city(city_id: String) -> void:
	if city_id not in cities:
		cities.append(city_id)


func remove_city(city_id: String) -> void:
	cities.erase(city_id)


func add_officer(officer_id: int) -> void:
	if officer_id not in officers:
		officers.append(officer_id)


func remove_officer(officer_id: int) -> void:
	officers.erase(officer_id)
