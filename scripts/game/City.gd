class_name City extends RefCounted
## 城市数据类

var id: String
var name: String
var position: Vector2i            # 地图坐标
var faction_id: String = ""       # 所属势力
var durability: int = 2000
var max_durability: int = 2000
var counties: Array = []  # 下辖郡列表
var gold: int = 5000
var food: int = 20000
var officers: Array = []     # 城内武将ID列表
var governor_id: int = -1    # 太守（城守）武将ID，-1=无


func from_dict(d: Dictionary) -> void:
	id = d.get("id", "")
	name = d.get("name", "")
	max_durability = d.get("max_durability", 2000)
	durability = max_durability
	gold = d.get("gold", 5000)
	food = d.get("food", 20000)

	var p = d.get("position", {})
	position = Vector2i(p.get("x", 0), p.get("y", 0))

	# 创建郡
	var county_data = d.get("counties", [])
	for cd in county_data:
		var county = County.new()
		cd["city_id"] = id
		county.from_dict(cd)
		counties.append(county)


func get_total_population() -> int:
	var total = 0
	for c in counties:
		total += c.population
	return total


func get_total_troops() -> int:
	var total = 0
	for c in counties:
		total += c.troops
	return total


func get_gold_income_per_turn() -> int:
	var base = 0
	for c in counties:
		base += int(c.dev_commerce * 0.1)
		for f in c.facilities:
			if f.get("type") == "market":
				base += 50 * f.get("level", 1)
	return base


func get_food_income_per_turn() -> int:
	var base = 0
	for c in counties:
		base += int(c.dev_agriculture * 0.15)
		for f in c.facilities:
			if f.get("type") == "farm":
				base += 50 * f.get("level", 1)
	return base


func has_governor(county_id: String) -> bool:
	for c in counties:
		if c.id == county_id:
			return c.has_governor()
	return false


func is_owned() -> bool:
	return faction_id != ""


const EXPANDED_CITY_IDS: Array[String] = ["jinyang", "beiping", "yecheng", "cangzhou", "kaifeng"]


## 判断该城是否已扩张为七格六边形
func is_expanded() -> bool:
	return id in EXPANDED_CITY_IDS


## 获取七格城市区域（中心 + 6邻接格子）
func get_hex_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = [position]
	var nb: Array
	if position.y & 1:
		nb = [[position.x, position.y - 1], [position.x + 1, position.y - 1], [position.x - 1, position.y], [position.x + 1, position.y], [position.x, position.y + 1], [position.x + 1, position.y + 1]]
	else:
		nb = [[position.x - 1, position.y - 1], [position.x, position.y - 1], [position.x - 1, position.y], [position.x + 1, position.y], [position.x - 1, position.y + 1], [position.x, position.y + 1]]
	for pair in nb:
		tiles.append(Vector2i(pair[0], pair[1]))
	return tiles
