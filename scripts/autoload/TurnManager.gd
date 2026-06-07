extends Node
## 回合管理器单例
##
## 管理回合推进、旬结算、呈报生成、AI行动等。

# 回合阶段
enum TurnPhase { PLAYER_INPUT, AI_PROCESSING, HOUKOU_RESOLVE, EVENTS_CHECK, END_TURN }

var phase: TurnPhase = TurnPhase.PLAYER_INPUT
var is_processing: bool = false

# 每旬结算的常量
const DAYS_PER_TURN: int = 10
const TURNS_PER_YEAR: int = 36


func _ready() -> void:
	print("TurnManager: Initialized")


## 执行回合推进（玩家点击"进行"按钮时调用）
## 结束玩家回合，自动处理所有 AI 势力，然后回到玩家回合。
func execute_turn() -> void:
	if is_processing:
		return
	is_processing = true

	# 1. 结束当前势力（玩家）的回合
	var player_fid = GameManager.faction_turn_order[GameManager.current_faction_index]
	_end_faction_turn(player_fid)

	# 2. 处理所有 AI 势力直到回到玩家回合
	while GameManager.state == GameManager.GameState.PLAYING:
		_advance_faction_turn()

		# 回到开头 -> 旬结算
		if GameManager.current_faction_index == 0:
			_execute_end_of_turn()

		var fid = GameManager.faction_turn_order[GameManager.current_faction_index]
		if fid == GameManager.player_faction_id:
			break

		# AI 势力回合
		EventBus.faction_turn_started.emit(fid)
		GameManager.turn_phase = "ai"
		_process_ai_turn(fid)
		_end_faction_turn(fid)

	# 3. 开始玩家新回合
	GameManager.turn_phase = "player"
	EventBus.faction_turn_started.emit(GameManager.player_faction_id)
	print("TurnManager: Turn %d - Player: %s" % [GameManager.current_turn, GameManager.player_faction_id])

	is_processing = false


func _end_faction_turn(faction_id: String) -> void:
	EventBus.faction_turn_ended.emit(faction_id)

	# 重置该势力所有部队的行动状态
	var faction = GameManager.get_faction(faction_id)
	if faction:
		for army_id in faction.armies:
			var army = GameManager.get_army(army_id)
			if army:
				army.reset_turn()


func _advance_faction_turn() -> void:
	GameManager.current_faction_index += 1
	if GameManager.current_faction_index >= GameManager.faction_turn_order.size():
		GameManager.current_faction_index = 0


func _process_ai_turn(_faction_id: String) -> void:
	# TODO: AI 决策将在 Phase 4 实现
	# 目前 AI 跳过，直接结束其回合
	pass


func _execute_end_of_turn() -> void:
	"""
	每旬结束时对所有城市进行结算：
	- 金钱收入
	- 粮食收入
	- 人口增长
	- 治安变化
	- 武将忠诚变化
	- 呈报生成
	- 事件检查
	"""
	GameManager.current_turn += 1

	# 更新年份
	if GameManager.current_turn % TURNS_PER_YEAR == 1 and GameManager.current_turn > 1:
		GameManager.current_year += 1

	# 结算每个城市
	for city in GameManager.cities.values():
		if city.is_owned():
			_resolve_city_economy(city)
			_generate_houkou(city)

	# 结算每个势力的研究
	for faction in GameManager.factions.values():
		_resolve_tech_research(faction)

	# 检查事件
	_check_events()

	EventBus.turn_ended.emit(GameManager.current_turn)
	print("TurnManager: Turn %d ended (Year %d)" % [GameManager.current_turn, GameManager.current_year])


func _resolve_city_economy(city: City) -> void:
	var faction = GameManager.get_faction(city.faction_id)
	if not faction:
		return

	# 计算收入
	var gold_income = city.get_gold_income_per_turn()
	var food_income = city.get_food_income_per_turn()

	# 应用势力科技加成
	var commerce_lv = faction.get_tech_level("commerce_tech")
	gold_income = int(gold_income * (1.0 + commerce_lv * 0.1))

	var agri_lv = faction.get_tech_level("agriculture_tech")
	food_income = int(food_income * (1.0 + agri_lv * 0.1))

	# 应用特技加成
	for oid in city.officers:
		var officer = GameManager.get_officer(oid)
		if officer and officer.faction_id == city.faction_id:
			if officer.has_skill("fuhao"):
				gold_income = int(gold_income * 1.5)
			if officer.has_skill("midao"):
				food_income = int(food_income * 1.5)

	# 更新城市和势力资源
	city.gold += gold_income
	city.food += food_income
	faction.gold += gold_income
	faction.food += food_income

	# 人口增长
	for county in city.counties:
		county.population += int(county.population * 0.002)  # 每旬 0.2%

		# 治安恢复
		if county.security < 100:
			county.security = mini(100, county.security + 2)
			if county.has_governor():
				var governor = GameManager.get_officer(county.governor_id)
				if governor and governor.has_skill("fazhi"):
					county.security = mini(100, county.security + 1)

		# 郡开发自然增长（如果无知行则缓慢）
		if county.has_governor():
			var governor = GameManager.get_officer(county.governor_id)
			if governor:
				var pol = governor.get_stat("zheng")
				var dev_speed = 1.0
				if governor.has_skill("nengli"):
					dev_speed *= 2.0
				county.dev_agriculture = mini(1000, county.dev_agriculture + int(pol * 0.05 * dev_speed))
				county.dev_commerce = mini(1000, county.dev_commerce + int(pol * 0.05 * dev_speed))
				county.dev_barracks = mini(1000, county.dev_barracks + int(pol * 0.03 * dev_speed))

	# 武将忠诚自然衰减
	for oid in city.officers:
		var officer = GameManager.get_officer(oid)
		if officer and officer.faction_id == city.faction_id:
			var decay = 0
			if officer.yeli > 70: decay += 1
			if officer.yili < 30: decay += 1
			var has_renzheng = false
			for oid2 in city.officers:
				var other = GameManager.get_officer(oid2)
				if other and other.has_skill("renzheng"):
					has_renzheng = true
					break
			if has_renzheng:
				decay = maxi(0, decay - 1)
			officer.loyalty = clampi(officer.loyalty - decay, 0, 100)


func _generate_houkou(city: City) -> void:
	"""
	为城市中担任知郡事的武将生成呈报。
	呈报在玩家回合开始时展示。
	"""
	for county in city.counties:
		if not county.has_governor():
			continue
		var governor = GameManager.get_officer(county.governor_id)
		if not governor:
			continue

		# 呈报概率 = 政治 x 0.2 + 智力 x 0.1
		var prob = governor.get_stat("zheng") * 0.2 + governor.get_stat("zhi") * 0.1
		if randf() * 100 < prob:
			var houkou = _create_random_houkou(city, county, governor)
			if not houkou.is_empty():
				EventBus.houkou_generated.emit(houkou)


func _create_random_houkou(city: City, county: County, governor: Officer) -> Dictionary:
	var types = ["develop_agri", "develop_comm", "develop_barracks", "recruit", "find_talent"]
	var houkou_type = types[randi() % types.size()]

	match houkou_type:
		"develop_agri":
			if county.dev_agriculture >= 1000: return {}
			return {
				"id": "houkou_%d_%s" % [GameManager.current_turn, county.id],
				"type": "develop_agri",
				"city_id": city.id,
				"county_id": county.id,
				"governor_id": governor.id,
				"governor_name": governor.name,
				"title": "%s郡农田可扩张" % county.id,
				"message": "[%s]呈报：%s郡尚有未开发农田，若投入500金，可增农业开发度50。" % [governor.name, county.id],
				"cost_gold": 500,
				"effect": {"dev_agriculture": 50}
			}
		"develop_comm":
			if county.dev_commerce >= 1000: return {}
			return {
				"id": "houkou_%d_%s_2" % [GameManager.current_turn, county.id],
				"type": "develop_comm",
				"city_id": city.id,
				"county_id": county.id,
				"governor_id": governor.id,
				"governor_name": governor.name,
				"title": "%s郡商贾求设市集" % county.id,
				"message": "[%s]呈报：商贾希望在%s郡开设市集，投入300金可增商业开发度40，并额外获得200金。" % [governor.name, county.id],
				"cost_gold": 300,
				"effect": {"dev_commerce": 40, "bonus_gold": 200}
			}
		"develop_barracks":
			if county.dev_barracks >= 1000: return {}
			return {
				"id": "houkou_%d_%s_3" % [GameManager.current_turn, county.id],
				"type": "develop_barracks",
				"city_id": city.id,
				"county_id": county.id,
				"governor_id": governor.id,
				"governor_name": governor.name,
				"title": "%s郡可扩建兵舍" % county.id,
				"message": "[%s]呈报：%s郡可扩建兵舍，投入400金可增兵舍开发度40。" % [governor.name, county.id],
				"cost_gold": 400,
				"effect": {"dev_barracks": 40}
			}
		"recruit":
			return {
				"id": "houkou_%d_%s_4" % [GameManager.current_turn, county.id],
				"type": "recruit",
				"city_id": city.id,
				"county_id": county.id,
				"governor_id": governor.id,
				"governor_name": governor.name,
				"title": "%s郡捕获贼寇可编入行伍" % county.id,
				"message": "[%s]呈报：在%s郡捕获一伙贼寇，可编入300人入伍。" % [governor.name, county.id],
				"cost_gold": 0,
				"effect": {"troops": 300}
			}
		"find_talent":
			return {
				"id": "houkou_%d_%s_5" % [GameManager.current_turn, county.id],
				"type": "find_talent",
				"city_id": city.id,
				"county_id": county.id,
				"governor_id": governor.id,
				"governor_name": governor.name,
				"title": "%s郡发现疑似人才" % county.id,
				"message": "[%s]呈报：在%s郡听闻一隐士名声，建议派人寻访。" % [governor.name, county.id],
				"cost_gold": 200,
				"effect": {"talent_search": true}
			}
	return {}


func _resolve_tech_research(faction: Faction) -> void:
	# TODO: 科技研究进度推进（Phase 2 实现）
	pass


func _check_events() -> void:
	# TODO: 事件系统（Phase 5 实现）
	pass


## 接受呈报
func accept_houkou(houkou: Dictionary) -> void:
	var city = GameManager.get_city(houkou.get("city_id", ""))
	if not city: return

	var county_id = houkou.get("county_id", "")
	var target_county: County = null
	for c in city.counties:
		if c.id == county_id:
			target_county = c
			break
	if not target_county: return

	var cost = houkou.get("cost_gold", 0)
	if cost > 0:
		city.gold -= cost
		var faction = GameManager.get_faction(city.faction_id)
		if faction:
			faction.gold -= cost

	var effect = houkou.get("effect", {})
	if "dev_agriculture" in effect:
		target_county.dev_agriculture = mini(1000, target_county.dev_agriculture + effect["dev_agriculture"])
	if "dev_commerce" in effect:
		target_county.dev_commerce = mini(1000, target_county.dev_commerce + effect["dev_commerce"])
	if "dev_barracks" in effect:
		target_county.dev_barracks = mini(1000, target_county.dev_barracks + effect["dev_barracks"])
	if "troops" in effect:
		target_county.troops += effect["troops"]
	if "bonus_gold" in effect:
		city.gold += effect["bonus_gold"]
		var faction = GameManager.get_faction(city.faction_id)
		if faction: faction.gold += effect["bonus_gold"]

	if "talent_search" in effect:
		_resolve_talent_search(city, target_county, houkou)

	EventBus.houkou_accepted.emit(houkou["id"])


## 人才搜索
func _resolve_talent_search(city: City, county: County, houkou: Dictionary) -> void:
	print("[人才搜索] triggered for %s" % houkou.get("title", "?"))
	var governor = GameManager.get_officer(houkou.get("governor_id", -1))
	if not governor: return
	var available: Array = []
	for o in GameManager.officers.values():
		if o.status == "在野" and o.location == city.id:
			available.append(o)
	# Debug: print all unaligned officers
	print("[人才搜索] All unaligned officers:")
	for o in GameManager.officers.values():
		if o.status == "在野":
			print("  %s (id=%d) at location=%s" % [o.name, o.id, o.location])
	print("[人才搜索] Looking in city: %s" % city.id)

	if available.is_empty():
		print("[人才搜索] %s：该城无在野人才" % governor.name)
		return
	var chance = governor.get_stat("zhi") * 0.3 + governor.get_stat("mei") * 0.2
	if randf() * 100 < chance:
		var found = available[randi() % available.size()]
		found.faction_id = city.faction_id
		found.status = "一般"
		found.loyalty = 70
		city.officers.append(found.id)
		var faction = GameManager.get_faction(city.faction_id)
		if faction: faction.officers.append(found.id)
		print("[人才搜索] %s 发现了 %s！已加入 %s" % [governor.name, found.name, faction.name if faction else ""])
	else:
		print("[人才搜索] %s 寻访无功而返" % governor.name)


## 拒绝呈报
func reject_houkou(houkou: Dictionary) -> void:
	var governor = GameManager.get_officer(houkou.get("governor_id", -1))
	if governor:
		governor.loyalty = maxi(0, governor.loyalty - 2)
	EventBus.houkou_rejected.emit(houkou["id"])
