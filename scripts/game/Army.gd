class_name Army extends RefCounted
## 部队数据类

var id: int = 0
var faction_id: String
var commander_id: int            # 主将
var sub_ids: Array = []     # 副将 (0-2)
var unit_type: String = "spear"  # 兵种ID
var troops: int = 3000
var max_troops: int = 5000
var morale: int = 100
var position: Vector2i
var food_carried: int = 0
var status_effects: Array = []  # ["confused", "on_fire"]
var has_moved: bool = false
var has_attacked: bool = false


func from_dict(d: Dictionary) -> void:
	id = d.get("id", 0)
	faction_id = d.get("faction_id", "")
	commander_id = d.get("commander_id", 0)
	sub_ids = d.get("sub_ids", [])
	unit_type = d.get("unit_type", "spear")
	troops = d.get("troops", 3000)
	max_troops = d.get("max_troops", 5000)
	morale = d.get("morale", 100)
	food_carried = d.get("food_carried", 0)
	var p = d.get("position", {})
	position = Vector2i(p.get("x", 0), p.get("y", 0))


func is_alive() -> bool:
	return troops > 0


func is_routed() -> bool:
	return morale <= 0


func get_attack_power(commander_stats: Dictionary, sub_stats_list: Array, unit_data: Dictionary) -> float:
	var wu = commander_stats.get("wu", 50)
	var sub_wu_avg = 50
	if not sub_stats_list.is_empty():
		var total = 0
		for s in sub_stats_list:
			total += s.get("wu", 50)
		sub_wu_avg = total / sub_stats_list.size()
	var base_wu = wu * 0.7 + sub_wu_avg * 0.3
	var troop_coef = minf(sqrt(float(troops) / 1000.0), 3.0)
	var atk_coef = unit_data.get("attack", 1.0)
	return base_wu * atk_coef * troop_coef


func get_defense_power(commander_stats: Dictionary, sub_stats_list: Array, unit_data: Dictionary) -> float:
	var tong = commander_stats.get("tong", 50)
	var sub_tong_avg = 50
	if not sub_stats_list.is_empty():
		var total = 0
		for s in sub_stats_list:
			total += s.get("tong", 50)
		sub_tong_avg = total / sub_stats_list.size()
	var base_tong = tong * 0.7 + sub_tong_avg * 0.3
	var troop_coef = minf(sqrt(float(troops) / 1000.0), 3.0)
	var def_coef = unit_data.get("defense", 1.0)
	return base_tong * def_coef * troop_coef


func get_morale_multiplier() -> float:
	if morale >= 50: return 1.0
	if morale >= 30: return 0.7
	return 0.5


func take_damage(damage: int) -> void:
	troops = maxi(0, troops - damage)
	if troops <= 0:
		troops = 0


func consume_supplies() -> void:
	var consumed = int(ceil(float(troops) / 1000.0) * 10)
	food_carried = maxi(0, food_carried - consumed)
	if food_carried <= 0:
		morale = maxi(0, morale - 20)
		troops = int(float(troops) * 0.9)


func reset_turn() -> void:
	has_moved = false
	has_attacked = false
