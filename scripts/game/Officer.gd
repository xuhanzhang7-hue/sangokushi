class_name Officer extends RefCounted
## 武将数据类

var id: int = 0
var name: String
var style: String             # 字
var birth: int = 0
var death: int = 0
var stats: Dictionary = {}    # {tong, wu, zhi, zheng, mei}
var skills: Array = []
var xiangxing: int            # 相性 0-255
var yeli: int                 # 野心 0-100
var yili: int                 # 义理 0-100
var gender: String = "male"
var relations: Array = []  # [{target_id, type}]
var faction_id: String = ""   # 所属势力ID
var location: String = ""     # 所在城市/郡ID
var status: String = "在野"    # 在野/一般/知郡事/太守/都督/俘虏/未发现
var loyalty: int = 80
var portrait_path: String = ""


func from_dict(d: Dictionary) -> void:
	id = d.get("id", 0)
	name = d.get("name", "")
	style = d.get("style", "")
	birth = d.get("birth", 0)
	death = d.get("death", 0)
	stats = d.get("stats", {})
	skills = d.get("skills", [])
	xiangxing = d.get("xiangxing", 125)
	yeli = d.get("yeli", 50)
	yili = d.get("yili", 50)
	gender = d.get("gender", "male")
	relations = d.get("relations", [])
	loyalty = 80  # 初始忠诚度由剧本设置


func get_stat(stat_name: String) -> int:
	return stats.get(stat_name, 50)


func has_skill(skill_id: String) -> bool:
	return skill_id in skills


func is_alive(current_year: int) -> bool:
	return current_year >= birth and current_year < death


func get_rank_name() -> String:
	var sum_stats = get_stat("tong") + get_stat("wu") + get_stat("zhi") + get_stat("zheng") + get_stat("mei")
	if sum_stats >= 450: return "S"
	if sum_stats >= 400: return "A"
	if sum_stats >= 350: return "B"
	if sum_stats >= 300: return "C"
	if sum_stats >= 250: return "D"
	return "E"


func get_troop_capacity(official_rank: int = 0) -> int:
	return get_stat("tong") * 80 + official_rank * 500
