class_name County extends RefCounted
## 郡数据类

var id: String
var city_id: String
var governor_id: int = -1       # 知郡事武将ID，-1=无
var center: Vector2i             # 郡中心顶点
var size: String = "medium"      # small/medium/large
var vertices: Array = []  # 该郡包含的顶点列表

# 开发度 0-1000
var dev_agriculture: int = 200
var dev_commerce: int = 150
var dev_barracks: int = 100

# 其他属性
var population: int = 10000
var security: int = 80          # 治安 0-100

# 城下町设施 [{type, level, vertex}]
var facilities: Array = []

# 该郡兵力
var troops: int = 0

# 可建设施上限
var max_facilities: int = 3
var special_resource: String = ""  # gold_mine, iron_mine, farmland, or empty


func from_dict(d: Dictionary) -> void:
	id = d.get("id", "")
	city_id = d.get("city_id", "")
	governor_id = d.get("governor_id", -1)
	size = d.get("size", "medium")
	dev_agriculture = d.get("dev_agriculture", 200)
	dev_commerce = d.get("dev_commerce", 150)
	dev_barracks = d.get("dev_barracks", 100)
	population = d.get("population", 10000)
	security = d.get("security", 80)
	facilities = d.get("facilities", [])
	troops = d.get("troops", 0)
	special_resource = d.get("special_resource", "")

	# 解析 center
	var c = d.get("center", {})
	if c:
		center = Vector2i(c.get("x", 0), c.get("y", 0))

	match size:
		"small":  max_facilities = 3
		"medium": max_facilities = 5
		"large":  max_facilities = 7
		_:        max_facilities = 3


func can_build_facility() -> bool:
	return facilities.size() < max_facilities


func has_governor() -> bool:
	return governor_id > 0


func get_development_total() -> int:
	return dev_agriculture + dev_commerce + dev_barracks
