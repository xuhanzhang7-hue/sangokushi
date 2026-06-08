extends Node
## HUD 控制器 — 连接 UI 元素到游戏状态
##
## 挂在 main.tscn 的 UI 节点上

@onready var gold_label: Label = $"TopBar/TopBarContainer/GoldLabel"
@onready var food_label: Label = $"TopBar/TopBarContainer/FoodLabel"
@onready var turn_label: Label = $"TopBar/TopBarContainer/TurnLabel"
@onready var faction_label: Label = $"TopBar/TopBarContainer/FactionLabel"
@onready var side_title: Label = $"SidePanel/SidePanelTitle"
@onready var side_content: VBoxContainer = $"SidePanel/SidePanelContent"
@onready var btn_end_turn: Button = $"CommandBar/CommandContainer/BtnEndTurn"
@onready var btn_internal: Button = $"CommandBar/CommandContainer/BtnInternal"
@onready var btn_military: Button = $"CommandBar/CommandContainer/BtnMilitary"
@onready var btn_talent: Button = $"CommandBar/CommandContainer/BtnTalent"
@onready var btn_diplomacy: Button = $"CommandBar/CommandContainer/BtnDiplomacy"
@onready var btn_strategy: Button = $"CommandBar/CommandContainer/BtnStrategy"

# 呈报队列
var _houkou_queue: Array = []
var _current_houkou_index: int = 0
var _is_showing_houkou: bool = false

# 呈报弹窗
var _houkou_dialog: Panel
var _houkou_title: Label
var _houkou_message: Label
var _houkou_cost: Label
var _houkou_accept_btn: Button
var _houkou_reject_btn: Button
var _current_houkou: Dictionary = {}

# 选中状态
var _selected_city_id: String = ""
var _selected_army_id: int = -1
var _is_internal_mode: bool = false


var _army_panel: Panel
var _army_list_container: VBoxContainer

func _ready() -> void:
	_apply_theme()
	_setup_houkou_dialog()
	_setup_army_panel()
	_connect_signals()
	_refresh_top_bar()


func _setup_army_panel() -> void:
	_army_panel = Panel.new()
	_army_panel.name = "ArmyPanel"
	_army_panel.offset_left = 8.0
	_army_panel.offset_top = 52.0
	_army_panel.offset_right = 228.0
	_army_panel.offset_bottom = 500.0
	_army_panel.z_index = 10

	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.04, 0.02, 0.94)
	s.set_border_width_all(1)
	s.border_color = Color(0.5, 0.4, 0.2, 0.8)
	s.set_corner_radius_all(4)
	_army_panel.add_theme_stylebox_override("panel", s)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 2)
	_army_panel.add_child(vbox)

	var title = Label.new()
	title.text = "— 部 队 —"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	_army_list_container = VBoxContainer.new()
	_army_list_container.add_theme_constant_override("separation", 2)
	vbox.add_child(_army_list_container)

	add_child(_army_panel)


func _setup_houkou_dialog() -> void:
	# 创建呈报弹窗（默认隐藏）
	_houkou_dialog = Panel.new()
	_houkou_dialog.visible = false
	_houkou_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_houkou_dialog.custom_minimum_size = Vector2(420, 280)
	_houkou_dialog.offset_left = -210.0
	_houkou_dialog.offset_right = 210.0
	_houkou_dialog.offset_top = -140.0
	_houkou_dialog.offset_bottom = 140.0
	_houkou_dialog.z_index = 100

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.04, 0.02, 0.95)
	style.set_border_width_all(2)
	style.border_color = Color(0.6, 0.5, 0.2, 1.0)
	style.set_corner_radius_all(8)
	_houkou_dialog.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	_houkou_dialog.add_child(vbox)

	# 标题
	_houkou_title = Label.new()
	_houkou_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_houkou_title.add_theme_font_size_override("font_size", 20)
	_houkou_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vbox.add_child(_houkou_title)

	# 分隔线
	var sep1 = HSeparator.new()
	vbox.add_child(sep1)

	# 内容
	_houkou_message = Label.new()
	_houkou_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_houkou_message.add_theme_font_size_override("font_size", 14)
	_houkou_message.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	_houkou_message.custom_minimum_size = Vector2(0, 80)
	vbox.add_child(_houkou_message)

	# 消耗
	_houkou_cost = Label.new()
	_houkou_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_houkou_cost.add_theme_font_size_override("font_size", 14)
	_houkou_cost.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vbox.add_child(_houkou_cost)

	# 按钮
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	_houkou_accept_btn = Button.new()
	_houkou_accept_btn.text = "  接  受  "
	_houkou_accept_btn.add_theme_font_size_override("font_size", 16)
	_houkou_accept_btn.pressed.connect(_on_houkou_accepted)
	hbox.add_child(_houkou_accept_btn)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(20, 0)
	hbox.add_child(spacer)

	_houkou_reject_btn = Button.new()
	_houkou_reject_btn.text = "  拒  绝  "
	_houkou_reject_btn.add_theme_font_size_override("font_size", 16)
	_houkou_reject_btn.pressed.connect(_on_houkou_rejected)
	hbox.add_child(_houkou_reject_btn)

	add_child(_houkou_dialog)


func _apply_theme() -> void:
	# 三国主题色：暗牛皮纸 + 金色边框
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.04, 0.02, 0.94)
	panel_style.set_border_width_all(1)
	panel_style.border_color = Color(0.5, 0.4, 0.2, 0.8)
	panel_style.set_corner_radius_all(4)

	for panel_name in ["TopBar", "SidePanel", "CommandBar"]:
		var panel = get_node_or_null(panel_name)
		if panel:
			panel.add_theme_stylebox_override("panel", panel_style)

	# 顶栏标签颜色 — 金色系
	_apply_label_style(gold_label, Color(0.9, 0.75, 0.3, 1.0), 16)
	_apply_label_style(food_label, Color(0.5, 0.85, 0.4, 1.0), 16)
	_apply_label_style(turn_label, Color(0.7, 0.75, 0.9, 1.0), 16)
	_apply_label_style(faction_label, Color(0.9, 0.85, 0.75, 1.0), 16)
	_apply_label_style(side_title, Color(0.9, 0.85, 0.75, 1.0), 18)

	for btn in [btn_end_turn, btn_internal, btn_military, btn_talent, btn_diplomacy, btn_strategy]:
		if btn:
			btn.add_theme_font_size_override("font_size", 16)


func _apply_label_style(label: Label, color: Color, size: int) -> void:
	if label:
		label.add_theme_color_override("font_color", color)
		label.add_theme_font_size_override("font_size", size)


func _connect_signals() -> void:
	btn_end_turn.pressed.connect(_on_end_turn_pressed)
	btn_internal.pressed.connect(_on_internal_pressed)
	btn_military.pressed.connect(_on_military_pressed)
	btn_talent.pressed.connect(_on_talent_pressed)
	btn_diplomacy.pressed.connect(_on_diplomacy_pressed)
	btn_strategy.pressed.connect(_on_strategy_pressed)

	# 游戏事件
	EventBus.turn_ended.connect(_on_turn_ended)
	EventBus.map_city_clicked.connect(_on_city_selected)
	EventBus.map_pass_clicked.connect(_on_pass_selected)
	EventBus.map_army_clicked.connect(_on_army_selected)
	EventBus.map_vertex_clicked.connect(_on_vertex_selected)
	EventBus.houkou_generated.connect(_on_houkou_generated)
	EventBus.faction_turn_started.connect(_on_faction_turn_started)


## ============================================================
## 顶部信息栏
## ============================================================

func _refresh_top_bar() -> void:
	var faction = GameManager.get_player_faction()
	if faction:
		gold_label.text = "金: %d" % faction.gold
		food_label.text = "粮: %d" % faction.food
		faction_label.text = "势力: %s  城: %d  将: %d  兵: %d" % [
			faction.name,
			faction.get_city_count(),
			faction.officers.size(),
			faction.get_total_troops(GameManager.cities)
		]
	turn_label.text = "回合: %d" % GameManager.current_turn


## ============================================================
## 按钮回调
## ============================================================

func _on_end_turn_pressed() -> void:
	btn_end_turn.disabled = true
	btn_end_turn.text = "处理中..."
	TurnManager.execute_turn()
	btn_end_turn.disabled = false
	btn_end_turn.text = "进行 (结束回合)"
	_refresh_top_bar()


func _on_internal_pressed() -> void:
	if _selected_city_id == "":
		_show_notice("请先选择一个城市")
		return
	_is_internal_mode = true
	_show_internal_popup(_selected_city_id)


func _on_military_pressed() -> void:
	_show_military_popup()


func _get_city_commander_troops(city: City, officer_id: int) -> int:
	if city.governor_id == officer_id:
		return city.get_total_troops()
	for county in city.counties:
		if county.governor_id == officer_id:
			return county.troops
	return 0


func _get_county_governors(city: City) -> Array:
	var result: Array = []
	for county in city.counties:
		if county.has_governor():
			var gov = GameManager.get_officer(county.governor_id)
			if gov and gov.faction_id == GameManager.player_faction_id:
				if not result.has(gov):
					result.append(gov)
	return result


func _show_military_popup() -> void:
	var faction = GameManager.get_player_faction()
	if not faction: return
	var my_cities = GameManager.get_player_cities()
	if my_cities.is_empty():
		_show_notice("没有可出征的城市")
		return

	var overlay = ColorRect.new()
	overlay.name = "MilitaryOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.5)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 95
	add_child(overlay)

	var popup = Panel.new()
	popup.name = "MilitaryPopup"
	popup.set_anchors_preset(Control.PRESET_CENTER)
	popup.offset_left = -260.0
	popup.offset_right = 260.0
	popup.offset_top = -350.0
	popup.offset_bottom = 350.0
	popup.z_index = 96
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.04, 0.02, 0.95)
	s.set_border_width_all(2)
	s.border_color = Color(0.8, 0.3, 0.3, 1.0)
	s.set_corner_radius_all(8)
	popup.add_theme_stylebox_override("panel", s)
	add_child(popup)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	popup.add_child(vbox)

	var title = Label.new()
	title.text = "军 事 — 出 征"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	var state = {"city_idx": 0, "commander_id": -1, "sub_ids": [], "unit": "spear", "troops": 0}

	# City selector buttons
	var city_btns = HBoxContainer.new()
	for i in range(my_cities.size()):
		var c = my_cities[i]
		var btn = Button.new()
		btn.text = "%s" % c.name
		btn.add_theme_font_size_override("font_size", 13)
		btn.custom_minimum_size = Vector2(70, 30)
		var ci = i
		btn.pressed.connect(func():
			state.city_idx = ci
			state.commander_id = -1
			state.sub_ids = []
			state.troops = 0
			_refresh_military_form(vbox.get_node("FormContainer"), state, my_cities, faction)
		)
		city_btns.add_child(btn)
	vbox.add_child(city_btns)

	var form_container = VBoxContainer.new()
	form_container.name = "FormContainer"
	vbox.add_child(form_container)

	# Bottom buttons (always visible)
	var hbox_close = HBoxContainer.new()
	hbox_close.alignment = BoxContainer.ALIGNMENT_CENTER
	var btn_dispatch = Button.new()
	btn_dispatch.text = "出  征"
	btn_dispatch.add_theme_font_size_override("font_size", 18)
	btn_dispatch.custom_minimum_size = Vector2(150, 40)
	btn_dispatch.pressed.connect(func():
		_do_dispatch(state, my_cities, faction, overlay, popup)
	)
	hbox_close.add_child(btn_dispatch)
	var btn_cancel = Button.new()
	btn_cancel.text = "取  消"
	btn_cancel.add_theme_font_size_override("font_size", 18)
	btn_cancel.custom_minimum_size = Vector2(150, 40)
	btn_cancel.pressed.connect(func():
		overlay.queue_free()
		popup.queue_free()
	)
	hbox_close.add_child(btn_cancel)
	vbox.add_child(hbox_close)

	_refresh_military_form(form_container, state, my_cities, faction)


func _refresh_military_form(container: VBoxContainer, state: Dictionary, my_cities: Array, faction: Faction) -> void:
	for c in container.get_children():
		c.queue_free()

	var city = my_cities[state.city_idx]
	var max_subs = maxi(0, city.counties.size() - 1)

	# Commander selection
	var cmdr_label = Label.new()
	cmdr_label.text = "主将 (太守或知郡事):"
	cmdr_label.add_theme_font_size_override("font_size", 13)
	cmdr_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	container.add_child(cmdr_label)

	# City governor option
	if city.governor_id > 0:
		var gov = GameManager.get_officer(city.governor_id)
		if gov:
			var total = city.get_total_troops()
			var btn = Button.new()
			btn.text = "[太守] %s 统%d武%d  可率:%d兵" % [gov.name, gov.get_stat("tong"), gov.get_stat("wu"), total]
			btn.add_theme_font_size_override("font_size", 12)
			if state.commander_id == city.governor_id:
				btn.text = "V " + btn.text
			btn.pressed.connect(func():
				state.commander_id = city.governor_id
				state.sub_ids = []
				state.troops = total
				_refresh_military_form(container, state, my_cities, faction)
			)
			container.add_child(btn)

	# County governor options
	for county in city.counties:
		if county.has_governor() and county.governor_id != city.governor_id:
			var gov = GameManager.get_officer(county.governor_id)
			if gov:
				var btn = Button.new()
				btn.text = "[知郡事] %s 统%d武%d  本郡:%d兵" % [gov.name, gov.get_stat("tong"), gov.get_stat("wu"), county.troops]
				btn.add_theme_font_size_override("font_size", 12)
				if state.commander_id == county.governor_id:
					btn.text = "V " + btn.text
				btn.pressed.connect(func():
					state.commander_id = county.governor_id
					state.sub_ids = []
					state.troops = county.troops
					_refresh_military_form(container, state, my_cities, faction)
				)
				container.add_child(btn)

	if state.commander_id <= 0:
		return

	# Sub commanders
	var sub_label = Label.new()
	sub_label.text = "副将 (可选, 最多%d人, 知郡事可带兵):" % max_subs
	sub_label.add_theme_font_size_override("font_size", 13)
	sub_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	container.add_child(sub_label)

	var available_subs = _get_county_governors(city)
	var filtered: Array = []
	for g in available_subs:
		if g.id != state.commander_id:
			filtered.append(g)

	var sub_box = HBoxContainer.new()
	for gov in filtered:
		var btn = Button.new()
		var ct = _get_city_commander_troops(city, gov.id)
		btn.text = "%s (+%d兵)" % [gov.name, ct]
		btn.add_theme_font_size_override("font_size", 11)
		if gov.id in state.sub_ids:
			btn.text = "V " + btn.text
		var gid = gov.id
		btn.pressed.connect(func():
			if gid in state.sub_ids:
				state.sub_ids.erase(gid)
				state.troops -= ct
			elif state.sub_ids.size() < max_subs:
				state.sub_ids.append(gid)
				state.troops += ct
			_refresh_military_form(container, state, my_cities, faction)
		)
		sub_box.add_child(btn)
	container.add_child(sub_box)

	# Unit type
	var unit_label = Label.new()
	unit_label.text = "兵种:"
	unit_label.add_theme_font_size_override("font_size", 13)
	unit_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	container.add_child(unit_label)

	var unit_box = HBoxContainer.new()
	var units = [
		{"id": "spear", "name": "枪兵"},
		{"id": "cavalry", "name": "骑兵"},
		{"id": "bow", "name": "弓兵"},
	]
	for u in units:
		var btn = Button.new()
		btn.text = "%s" % u.name
		btn.add_theme_font_size_override("font_size", 12)
		if state.unit == u.id:
			btn.text = "V " + btn.text
		var uid = u.id
		btn.pressed.connect(func():
			state.unit = uid
			_refresh_military_form(container, state, my_cities, faction)
		)
		unit_box.add_child(btn)
	container.add_child(unit_box)

	# Troop display
	var cost_gold = state.troops
	var cost_food = state.troops * 2
	var info = Label.new()
	info.text = "可出动兵力: %d  (消耗: %d金 + %d粮)" % [state.troops, cost_gold, cost_food]
	info.add_theme_font_size_override("font_size", 14)
	info.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	container.add_child(info)


var _pending_dispatch: Dictionary = {}

func _do_dispatch(state: Dictionary, my_cities: Array, faction: Faction, overlay: ColorRect, popup: Panel) -> void:
	if state.commander_id <= 0:
		_show_notice("请选择主将")
		return
	if state.troops <= 0:
		_show_notice("可出动兵力为0，请先征兵")
		return
	var cost_gold = state.troops
	var cost_food = state.troops * 2
	if faction.gold < cost_gold or faction.food < cost_food:
		_show_notice("资源不足 (需要%d金 %d粮)" % [cost_gold, cost_food])
		return

	# Store dispatch data and enter destination selection mode
	_pending_dispatch = {
		"city_idx": state.city_idx,
		"commander_id": state.commander_id,
		"sub_ids": state.sub_ids.duplicate(),
		"unit": state.unit,
		"troops": state.troops,
		"cost_gold": cost_gold,
		"cost_food": cost_food,
	}
	overlay.queue_free()
	popup.queue_free()
	_show_notice("请点击地图选择出征目的地")


func _on_destination_selected(grid_pos: Vector2i) -> void:
	if _pending_dispatch.is_empty(): return
	var pd = _pending_dispatch
	_pending_dispatch = {}

	var faction = GameManager.get_player_faction()
	if not faction: return
	var my_cities = GameManager.get_player_cities()
	if pd.city_idx >= my_cities.size(): return
	var city = my_cities[pd.city_idx]

	if faction.gold < pd.cost_gold or faction.food < pd.cost_food:
		_show_notice("资源不足")
		return

	var commander = GameManager.get_officer(pd.commander_id)
	if not commander: return

	faction.gold -= pd.cost_gold
	faction.food -= pd.cost_food

	# Deduct troops
	var remaining = pd.troops
	if city.governor_id == pd.commander_id:
		var total = maxi(1, city.get_total_troops())
		for county in city.counties:
			var share = int(float(county.troops) / total * pd.troops)
			share = mini(share, county.troops)
			county.troops -= share
			remaining -= share
	else:
		for county in city.counties:
			if county.governor_id == pd.commander_id:
				var take = mini(pd.troops, county.troops)
				county.troops -= take
				remaining -= take
				break

	for sub_id in pd.sub_ids:
		if remaining <= 0: break
		for county in city.counties:
			if county.governor_id == sub_id:
				var take = mini(remaining, county.troops)
				county.troops -= take
				remaining -= take

	var army = Army.new()
	army.id = GameManager._next_army_id
	GameManager._next_army_id += 1
	army.faction_id = faction.id
	army.commander_id = commander.id
	army.unit_type = pd.unit
	army.troops = pd.troops - remaining
	army.max_troops = pd.troops
	army.morale = 100
	army.position = grid_pos
	army.food_carried = pd.cost_food
	army.sub_ids = pd.sub_ids.duplicate()

	GameManager.armies[army.id] = army
	faction.armies.append(army.id)

	print("Dispatched army %d: %s with %d troops to (%d,%d)" % [army.id, commander.name, army.troops, grid_pos.x, grid_pos.y])

	var renderer = get_node_or_null("../Map")
	if renderer and renderer.has_method("render_armies"):
		renderer.render_armies()

	_refresh_top_bar()
	_refresh_army_panel()

func _on_talent_pressed() -> void:
	print("HUD: Talent panel - TODO")


func _on_diplomacy_pressed() -> void:
	print("HUD: Diplomacy panel - TODO")


func _on_strategy_pressed() -> void:
	print("HUD: Strategy panel - TODO")


## ============================================================
## 事件回调
## ============================================================

func _on_turn_ended(_turn: int) -> void:
	_refresh_top_bar()
	_process_houkou_queue()
	_refresh_army_panel()


func _on_faction_turn_started(faction_id: String) -> void:
	# TurnManager 直接处理所有 AI 回合，这里只需刷新 UI
	if faction_id == GameManager.player_faction_id:
		_refresh_top_bar()


func _on_city_selected(city_id: String) -> void:
	_selected_city_id = city_id
	_selected_army_id = -1
	print("HUD: City selected: %s" % city_id)
	_update_side_panel_city(city_id)


func _on_pass_selected(pass_id: String) -> void:
	_selected_city_id = ""
	_selected_army_id = -1
	print("HUD: Pass selected: %s" % pass_id)
	_show_pass_info(pass_id)


func _on_army_selected(army_id: int) -> void:
	_selected_army_id = army_id
	_selected_city_id = ""
	print("HUD: Army selected: %d" % army_id)
	_update_side_panel_army(army_id)
	_refresh_army_panel()


func _on_vertex_selected(pos: Vector2i) -> void:
	print("HUD: Vertex selected: (%d, %d) — empty terrain" % [pos.x, pos.y])
	_refresh_army_panel()


## ============================================================
## 侧面板
## ============================================================

func _update_side_panel_city(city_id: String) -> void:
	_clear_side_panel()
	var city = GameManager.get_city(city_id)
	if not city: return

	side_title.text = city.name
	if city.is_owned():
		var faction = GameManager.get_faction(city.faction_id)
		side_title.text += " [%s]" % (faction.name if faction else "?")

	_add_info_line("耐久: %d / %d" % [city.durability, city.max_durability])
	_add_info_line("金钱: %d  粮食: %d" % [city.gold, city.food])
	_add_info_line("人口: %d  兵力: %d" % [city.get_total_population(), city.get_total_troops()])
	_add_info_line("收入: %d金/旬  %d粮/旬" % [city.get_gold_income_per_turn(), city.get_food_income_per_turn()])
	_add_separator()

	# 郡列表
	for county in city.counties:
		var gov_name = "无"
		if county.has_governor():
			var gov = GameManager.get_officer(county.governor_id)
			if gov: gov_name = gov.name

		_add_info_line("■ %s [知行: %s]" % [county.id, gov_name])
		_add_info_line("  农:%d 商:%d 兵:%d  人口:%d 治安:%d" % [
			county.dev_agriculture, county.dev_commerce,
			county.dev_barracks, county.population, county.security
		])

		# 城下町设施
		if not county.facilities.is_empty():
			var fac_names: Array = []
			for f in county.facilities:
				fac_names.append("%s Lv%d" % [f.get("type", "?"), f.get("level", 1)])
			_add_info_line("  设施: %s" % ", ".join(fac_names))


func _update_side_panel_army(army_id: int) -> void:
	_clear_side_panel()
	var army = GameManager.get_army(army_id)
	if not army: return

	var commander = GameManager.get_officer(army.commander_id)
	var unit_data = DataManager.get_unit_definition(army.unit_type)

	side_title.text = commander.name if commander else "部队 #%d" % army_id

	_add_info_line("兵种: %s  兵力: %d" % [unit_data.get("name", army.unit_type), army.troops])
	_add_info_line("士气: %d / 100" % army.morale)
	_add_info_line("粮食: %d" % army.food_carried)
	_add_info_line("位置: (%d, %d)" % [army.position.x, army.position.y])

	if commander:
		_add_separator()
		_add_info_line("统:%d 武:%d 智:%d 政:%d 魅:%d" % [
			commander.get_stat("tong"),
			commander.get_stat("wu"),
			commander.get_stat("zhi"),
			commander.get_stat("zheng"),
			commander.get_stat("mei")
		])

		if not commander.skills.is_empty():
			_add_info_line("特技: %s" % ", ".join(commander.skills))


func _show_pass_info(pass_id: String) -> void:
	_clear_side_panel()
	var pass_data = GameManager.get_pass_data(pass_id)
	if pass_data.is_empty(): return

	side_title.text = pass_data.get("name", "关口")
	_add_info_line("耐久: %d / %d" % [pass_data.get("durability", pass_data.get("max_durability", 2000)), pass_data.get("max_durability", 2000)])
	_add_info_line("防御加成: %d%%" % pass_data.get("defense_bonus", 0))
	_add_separator()
	var connects = pass_data.get("connects", [])
	if not connects.is_empty():
		_add_info_line("连接: %s" % ", ".join(connects))
	var tiles = pass_data.get("tiles", [])
	if tiles.size() >= 2:
		_add_info_line("规模: 横跨%d格" % tiles.size())


func _refresh_army_panel() -> void:
	for c in _army_list_container.get_children():
		c.queue_free()

	var faction = GameManager.get_player_faction()
	if not faction: return

	for army_id in faction.armies:
		var army = GameManager.get_army(army_id)
		if not army or not army.is_alive(): continue
		var cmdr = GameManager.get_officer(army.commander_id)
		var cmdr_name = cmdr.name if cmdr else "???"

		var status = ""
		if not army.has_moved:
			status = " ●"
		else:
			status = " ○"

		var unit_names = {"spear": "枪", "cavalry": "骑", "bow": "弓", "navy": "水"}
		var un = unit_names.get(army.unit_type, "?")

		var btn = Button.new()
		btn.text = "%s %s%s %d兵" % [status, cmdr_name, un, army.troops]
		btn.add_theme_font_size_override("font_size", 12)
		btn.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(200, 28)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		if not army.has_moved:
			btn.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))

		var aid = army_id
		btn.pressed.connect(_select_army_from_list.bind(aid))
		_army_list_container.add_child(btn)


func _select_army_from_list(army_id: int) -> void:
	var army = GameManager.get_army(army_id)
	if not army: return

	GameManager.selected_army_id = army_id
	_selected_army_id = army_id
	_selected_city_id = ""

	# Center camera on army using grid_to_screen
	var renderer = get_node_or_null("../Map")
	if renderer and renderer.camera and renderer.grid_utils:
		var world_pos = renderer.grid_utils.grid_to_screen(army.position.x, army.position.y)
		renderer.camera.position = world_pos

	_update_side_panel_army(army_id)
	EventBus.map_army_clicked.emit(army_id)


func _clear_side_panel() -> void:
	side_title.text = ""
	for child in side_content.get_children():
		child.queue_free()


func _add_info_line(text: String) -> void:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side_content.add_child(label)


func _add_separator() -> void:
	var sep = HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 8)
	side_content.add_child(sep)


## ============================================================
## 内政面板
## ============================================================

func _show_internal_popup(city_id: String) -> void:
	var city = GameManager.get_city(city_id)
	if not city: return
	var faction = GameManager.get_player_faction()
	if not faction: return

	# Clean up any existing internal popups first
	_close_internal_popups()

	# Dark overlay (catches all clicks, prevents map interaction)
	var overlay = ColorRect.new()
	overlay.name = "InternalOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.5)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 95
	add_child(overlay)

	# Main popup
	var popup = Panel.new()
	popup.name = "InternalPopup"
	popup.set_anchors_preset(Control.PRESET_CENTER)
	popup.offset_left = -280.0
	popup.offset_right = 280.0
	popup.offset_top = -350.0
	popup.offset_bottom = 350.0
	popup.z_index = 96

	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.04, 0.02, 0.95)
	s.set_border_width_all(2)
	s.border_color = Color(0.6, 0.5, 0.2, 1.0)
	s.set_corner_radius_all(8)
	popup.add_theme_stylebox_override("panel", s)
	add_child(popup)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 6)
	popup.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "内政 — %s (金:%d 粮:%d)" % [city.name, faction.gold, faction.food]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	# County sections in a scroll
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 500)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)

	for county in city.counties:
		var gov_name = "无"
		if county.has_governor():
			var gov = GameManager.get_officer(county.governor_id)
			if gov: gov_name = gov.name

		# County header with special resource indicator
		var res_text = ""
		match county.special_resource:
			"gold_mine": res_text = "[金矿]"
			"iron_mine": res_text = "[铁矿]"
			"farmland": res_text = "[沃土]"

		# Facility summary
		var fac_names = {"farm": "农田", "market": "市场", "barracks": "兵舍",
			"mint": "造币厂", "forge": "锻冶厂", "armory": "武库",
			"granary": "大农场", "granary2": "粮仓"}
		var fac_summary = ""
		if not county.facilities.is_empty():
			for f in county.facilities:
				var fn = fac_names.get(f.get("type", ""), f.get("type", "?"))
				fac_summary += "%sLv%d " % [fn, f.get("level", 1)]

		var header = Label.new()
		header.text = "■ %s [知行:%s] 农:%d 商:%d 兵:%d 人口:%d %s 设施:%s" % [
			county.id, gov_name,
			county.dev_agriculture, county.dev_commerce, county.dev_barracks,
			county.population, res_text,
			fac_summary if fac_summary != "" else "无"
		]
		header.add_theme_font_size_override("font_size", 13)
		header.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		list.add_child(header)

		# Button row
		var btns = HBoxContainer.new()
		btns.add_theme_constant_override("separation", 4)
		list.add_child(btns)

		# Governor button
		var btn_gov = Button.new()
		btn_gov.text = "撤换知行" if county.has_governor() else "任命知行"
		btn_gov.add_theme_font_size_override("font_size", 13)
		btn_gov.custom_minimum_size = Vector2(100, 32)
		btn_gov.pressed.connect(_on_appoint_governor.bind(county.id))
		btns.add_child(btn_gov)

		# Develop buttons
		for act in [
			["农+30", "300金", _on_dev_agri, county.dev_agriculture < 1000 and faction.gold >= 300],
			["商+20", "200金", _on_dev_comm, county.dev_commerce < 1000 and faction.gold >= 200],
			["兵+30", "400金", _on_dev_barracks, county.dev_barracks < 1000 and faction.gold >= 400],
		]:
			var btn = Button.new()
			btn.text = "%s %s" % [act[0], act[1]]
			btn.add_theme_font_size_override("font_size", 12)
			btn.custom_minimum_size = Vector2(100, 32)
			btn.disabled = not act[3]
			btn.pressed.connect(act[2].bind(county.id))
			btns.add_child(btn)

		# Recruit button
		var btn_rec = Button.new()
		btn_rec.text = "征兵+500"
		btn_rec.add_theme_font_size_override("font_size", 12)
		btn_rec.custom_minimum_size = Vector2(100, 32)
		btn_rec.disabled = faction.gold < 200 or faction.food < 200
		btn_rec.pressed.connect(_on_recruit.bind(county.id))
		btns.add_child(btn_rec)

		# Build facility button
		if county.can_build_facility():
			var btn_fac = Button.new()
			btn_fac.text = "建设施"
			btn_fac.add_theme_font_size_override("font_size", 12)
			btn_fac.custom_minimum_size = Vector2(100, 32)
			btn_fac.pressed.connect(_on_build_facility.bind(county.id))
			btns.add_child(btn_fac)

	list.add_child(HSeparator.new())

	# Close button
	var btn_close = Button.new()
	btn_close.text = "关  闭"
	btn_close.add_theme_font_size_override("font_size", 16)
	btn_close.custom_minimum_size = Vector2(120, 40)
	btn_close.pressed.connect(_on_internal_close.bind(overlay, popup))
	vbox.add_child(btn_close)


func _on_internal_close(overlay: ColorRect, popup: Panel) -> void:
	_is_internal_mode = false
	overlay.queue_free()
	popup.queue_free()
	_update_side_panel_city(_selected_city_id)


func _close_internal_popups() -> void:
	for child in get_children():
		if child.name in ["InternalOverlay", "InternalPopup", "OfficerDialog", "BuildDialog"]:
			remove_child(child)
			child.queue_free()


func _refresh_internal_popup() -> void:
	_refresh_top_bar()
	_close_internal_popups()
	_show_internal_popup(_selected_city_id)


func _show_internal_panel(city_id: String) -> void:
	_clear_side_panel()
	get_node("SidePanel").mouse_filter = Control.MOUSE_FILTER_STOP
	var city = GameManager.get_city(city_id)
	if not city: return

	var faction = GameManager.get_player_faction()
	if not faction: return

	side_title.text = "内政 — %s" % city.name

	_add_info_line("金: %d  粮: %d" % [faction.gold, faction.food])
	_add_separator()

	for county in city.counties:
		var gov_name = "无"
		if county.has_governor():
			var gov = GameManager.get_officer(county.governor_id)
			if gov: gov_name = gov.name

		_add_info_line("■ %s [知行: %s]" % [county.id, gov_name])
		_add_info_line("  农:%d/1000  商:%d/1000  兵:%d/1000" % [
			county.dev_agriculture, county.dev_commerce, county.dev_barracks
		])
		_add_info_line("  人口:%d  治安:%d  兵力:%d" % [
			county.population, county.security, county.troops
		])

		# 知行任命按钮
		var btn_gov = Button.new()
		if county.has_governor():
			btn_gov.text = "撤换知郡事"
		else:
			btn_gov.text = "任命知郡事"
		btn_gov.add_theme_font_size_override("font_size", 12)
		btn_gov.custom_minimum_size = Vector2(150, 30)
		btn_gov.mouse_filter = Control.MOUSE_FILTER_STOP
		btn_gov.pressed.connect(_on_appoint_governor.bind(county.id))
		side_content.add_child(btn_gov)

		# 城下町设施与建设按钮
		if county.can_build_facility():
			var btn_build = Button.new()
			btn_build.text = "建设设施 (%d/%d)" % [county.facilities.size(), county.max_facilities]
			btn_build.add_theme_font_size_override("font_size", 12)
			btn_build.custom_minimum_size = Vector2(150, 30)
			btn_build.mouse_filter = Control.MOUSE_FILTER_STOP
			btn_build.pressed.connect(_on_build_facility.bind(county.id))
			side_content.add_child(btn_build)

		# 开发按钮
		var btn_agri = Button.new()
		btn_agri.text = "开发农业 (300金)"
		btn_agri.add_theme_font_size_override("font_size", 12)
		btn_agri.pressed.connect(_on_dev_agri.bind(county.id))
		if faction.gold < 300 or county.dev_agriculture >= 1000:
			btn_agri.disabled = true
		side_content.add_child(btn_agri)

		var btn_comm = Button.new()
		btn_comm.text = "开发商业 (200金)"
		btn_comm.add_theme_font_size_override("font_size", 12)
		btn_comm.pressed.connect(_on_dev_comm.bind(county.id))
		if faction.gold < 200 or county.dev_commerce >= 1000:
			btn_comm.disabled = true
		side_content.add_child(btn_comm)

		var btn_barracks = Button.new()
		btn_barracks.text = "开发兵舍 (400金)"
		btn_barracks.add_theme_font_size_override("font_size", 12)
		btn_barracks.pressed.connect(_on_dev_barracks.bind(county.id))
		if faction.gold < 400 or county.dev_barracks >= 1000:
			btn_barracks.disabled = true
		side_content.add_child(btn_barracks)

		var btn_recruit = Button.new()
		btn_recruit.text = "征兵 (200金+200粮 → +500兵)"
		btn_recruit.add_theme_font_size_override("font_size", 12)
		btn_recruit.pressed.connect(_on_recruit.bind(county.id))
		if faction.gold < 200 or faction.food < 200:
			btn_recruit.disabled = true
		side_content.add_child(btn_recruit)

		_add_separator()

	# 返回按钮
	var btn_back = Button.new()
	btn_back.text = "◀ 返回城市详情"
	btn_back.add_theme_font_size_override("font_size", 14)
	btn_back.pressed.connect(_on_internal_back)
	side_content.add_child(btn_back)

	# 强制 VBoxContainer 重新布局
	side_content.reset_size()
	print("Internal panel: %d children added" % side_content.get_child_count())


func _get_county_by_id(city_id: String, county_id: String) -> County:
	var city = GameManager.get_city(city_id)
	if not city: return null
	for c in city.counties:
		if c.id == county_id:
			return c
	return null


func _on_dev_agri(county_id: String) -> void:
	var faction = GameManager.get_player_faction()
	var county = _get_county_by_id(_selected_city_id, county_id)
	if not faction or not county: return
	if faction.gold < 300 or county.dev_agriculture >= 1000: return

	faction.gold -= 300
	county.dev_agriculture = mini(1000, county.dev_agriculture + 30)
	print("HUD: %s 农业 +30 (→%d)" % [county_id, county.dev_agriculture])
	_refresh_internal_popup()


func _on_dev_comm(county_id: String) -> void:
	var faction = GameManager.get_player_faction()
	var county = _get_county_by_id(_selected_city_id, county_id)
	if not faction or not county: return
	if faction.gold < 200 or county.dev_commerce >= 1000: return

	faction.gold -= 200
	county.dev_commerce = mini(1000, county.dev_commerce + 20)
	faction.gold += 100  # 商业开发回馈
	print("HUD: %s 商业 +20 (→%d)" % [county_id, county.dev_commerce])
	_refresh_internal_popup()


func _on_dev_barracks(county_id: String) -> void:
	var faction = GameManager.get_player_faction()
	var county = _get_county_by_id(_selected_city_id, county_id)
	if not faction or not county: return
	if faction.gold < 400 or county.dev_barracks >= 1000: return

	faction.gold -= 400
	county.dev_barracks = mini(1000, county.dev_barracks + 30)
	print("HUD: %s 兵舍 +30 (→%d)" % [county_id, county.dev_barracks])
	_refresh_internal_popup()


func _on_recruit(county_id: String) -> void:
	var faction = GameManager.get_player_faction()
	var county = _get_county_by_id(_selected_city_id, county_id)
	if not faction or not county: return
	if faction.gold < 200 or faction.food < 200: return

	faction.gold -= 200
	faction.food -= 200
	county.troops += 500
	print("HUD: %s 征兵 +500 (→%d)" % [county_id, county.troops])
	_refresh_internal_popup()


func _on_internal_back() -> void:
	_is_internal_mode = false
	if _selected_city_id != "":
		_update_side_panel_city(_selected_city_id)
	else:
		_clear_side_panel()




## ============================================================
## 知行任命
## ============================================================

func _on_appoint_governor(county_id: String) -> void:
	var city = GameManager.get_city(_selected_city_id)
	if not city:
		_show_notice("请先选择一个城市")
		return

	var county = _get_county_by_id(_selected_city_id, county_id)
	if not county: return

	# 获取城内本势力武将（排除已是本郡知行者）
	var available: Array = []
	for oid in city.officers:
		var officer = GameManager.get_officer(oid)
		if officer and officer.faction_id == GameManager.player_faction_id:
			if county.governor_id != oid:
				available.append(officer)

	if available.is_empty() and county.governor_id <= 0:
		_show_notice("该城没有可用的武将")
		return

	# Show selection dialog with "解除任命" option if has governor
	_show_officer_selection(county_id, available, county.has_governor())


func _show_notice(msg: String) -> void:
	var n = Panel.new()
	n.set_anchors_preset(Control.PRESET_CENTER)
	n.offset_left = -120.0
	n.offset_right = 120.0
	n.offset_top = -20.0
	n.offset_bottom = 20.0
	n.z_index = 200
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0.85)
	s.set_corner_radius_all(6)
	n.add_theme_stylebox_override("panel", s)
	var l = Label.new()
	l.text = msg
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color.WHITE)
	n.add_child(l)
	add_child(n)
	await get_tree().create_timer(1.5).timeout
	n.queue_free()


func _show_officer_selection(county_id: String, officers: Array, has_gov: bool = false) -> void:
	var dialog = Panel.new()
	dialog.name = "OfficerDialog"
	dialog.set_anchors_preset(Control.PRESET_CENTER)
	dialog.custom_minimum_size = Vector2(320, 300)
	dialog.offset_left = -160.0
	dialog.offset_right = 160.0
	dialog.offset_top = -150.0
	dialog.offset_bottom = 150.0
	dialog.z_index = 101

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.04, 0.02, 0.95)
	style.set_border_width_all(2)
	style.border_color = Color(0.6, 0.5, 0.2, 1.0)
	style.set_corner_radius_all(8)
	dialog.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	dialog.add_child(vbox)

	var title = Label.new()
	title.text = "选择知郡事"
	if has_gov:
		title.text += " — 或解除"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# "解除任命" button if has governor
	if has_gov:
		var btn_remove = Button.new()
		btn_remove.text = "✕ 解除任命（成为空郡）"
		btn_remove.add_theme_font_size_override("font_size", 14)
		btn_remove.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		btn_remove.pressed.connect(_on_governor_removed.bind(county_id, dialog))
		vbox.add_child(btn_remove)
		vbox.add_child(HSeparator.new())

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 180)
	vbox.add_child(scroll)

	var list = VBoxContainer.new()
	scroll.add_child(list)

	if officers.is_empty():
		var nolabel = Label.new()
		nolabel.text = "（无其他可用武将）"
		nolabel.add_theme_font_size_override("font_size", 13)
		nolabel.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		list.add_child(nolabel)

	for officer in officers:
		var btn = Button.new()
		btn.text = "%s 统%d武%d智%d政%d" % [officer.name, officer.get_stat("tong"), officer.get_stat("wu"), officer.get_stat("zhi"), officer.get_stat("zheng")]
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(_on_governor_appointed.bind(county_id, officer.id, dialog))
		list.add_child(btn)

	var cancel = Button.new()
	cancel.text = "取消"
	cancel.add_theme_font_size_override("font_size", 14)
	cancel.pressed.connect(dialog.queue_free)
	vbox.add_child(cancel)

	add_child(dialog)


func _on_governor_removed(county_id: String, dialog: Panel) -> void:
	var county = _get_county_by_id(_selected_city_id, county_id)
	if county:
		county.governor_id = -1
		print("HUD: Removed governor from %s" % county_id)
	dialog.queue_free()
	_refresh_internal_popup()


func _on_governor_appointed(county_id: String, officer_id: int, dialog: Panel) -> void:
	var city = GameManager.get_city(_selected_city_id)
	if not city: return

	# Remove old governor from this county
	for county in city.counties:
		if county.id == county_id:
			county.governor_id = officer_id
			print("HUD: Appointed officer %d as governor of %s" % [officer_id, county_id])
			break

	# Remove new governor from other counties in the same city
	for county in city.counties:
		if county.id != county_id and county.governor_id == officer_id:
			county.governor_id = -1

	dialog.queue_free()
	_refresh_internal_popup()


## ============================================================
## 城下町建设
## ============================================================

func _on_build_facility(county_id: String) -> void:
	var county = _get_county_by_id(_selected_city_id, county_id)
	if not county or not county.can_build_facility(): return

	var faction = GameManager.get_player_faction()
	if not faction: return

	# Basic facility types
	var types = [
		{"id": "farm", "name": "农田", "cost": 300, "desc": "农业收入+50/旬"},
		{"id": "market", "name": "市场", "cost": 300, "desc": "商业收入+50/旬"},
		{"id": "barracks", "name": "兵舍", "cost": 400, "desc": "可征兵数+200"},
	]

	# Special facilities based on resource
	if county.special_resource == "gold_mine":
		types.append_array([
			{"id": "mint", "name": "造币厂", "cost": 600, "desc": "金钱收入+150/旬"},
			{"id": "forge", "name": "锻冶厂", "cost": 500, "desc": "金矿锻冶，收入+100/旬"},
		])
	elif county.special_resource == "iron_mine":
		types.append_array([
			{"id": "forge", "name": "锻冶厂", "cost": 500, "desc": "兵器锻造，征兵质量↑"},
			{"id": "armory", "name": "武库", "cost": 400, "desc": "部队攻击力+10%"},
		])
	elif county.special_resource == "farmland":
		types.append_array([
			{"id": "granary", "name": "大农场", "cost": 400, "desc": "农业收入+100/旬"},
			{"id": "granary2", "name": "粮仓", "cost": 300, "desc": "粮食存储+2000"},
		])

	var res_name = ""
	match county.special_resource:
		"gold_mine": res_name = " [金矿]"
		"iron_mine": res_name = " [铁矿]"
		"farmland": res_name = " [沃土]"

	var dialog = Panel.new()
	dialog.name = "BuildDialog"
	dialog.set_anchors_preset(Control.PRESET_CENTER)
	dialog.custom_minimum_size = Vector2(340, 280)
	dialog.offset_left = -170.0
	dialog.offset_right = 170.0
	dialog.offset_top = -140.0
	dialog.offset_bottom = 140.0
	dialog.z_index = 101

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.04, 0.02, 0.95)
	style.set_border_width_all(2)
	style.border_color = Color(0.4, 0.6, 0.3, 1.0)
	style.set_corner_radius_all(8)
	dialog.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 6)
	dialog.add_child(vbox)

	var title = Label.new()
	title.text = "建设设施 — %s%s (%d/%d)" % [county_id, res_name, county.facilities.size(), county.max_facilities]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 180)
	vbox.add_child(scroll)
	var list = VBoxContainer.new()
	scroll.add_child(list)

	for ft in types:
		var btn = Button.new()
		if "special" in ft:
			btn.text = "★ %s (%d金) — %s" % [ft.name, ft.cost, ft.desc]
		else:
			btn.text = "%s (%d金) — %s" % [ft.name, ft.cost, ft.desc]
		btn.add_theme_font_size_override("font_size", 13)
		if faction.gold < ft.cost:
			btn.disabled = true
		btn.pressed.connect(_on_facility_built.bind(county_id, ft.id, ft.cost, dialog))
		list.add_child(btn)

	var cancel = Button.new()
	cancel.text = "取消"
	cancel.add_theme_font_size_override("font_size", 14)
	cancel.pressed.connect(dialog.queue_free)
	vbox.add_child(cancel)

	add_child(dialog)


func _on_facility_built(county_id: String, fac_type: String, cost: int, dialog: Panel) -> void:
	var county = _get_county_by_id(_selected_city_id, county_id)
	var faction = GameManager.get_player_faction()
	if not county or not faction: return
	if faction.gold < cost: return

	faction.gold -= cost
	var new_fac = {"type": fac_type, "level": 1}
	county.facilities.append(new_fac)
	print("HUD: Built %s in %s" % [fac_type, county_id])
	dialog.queue_free()
	_refresh_internal_popup()
## ============================================================
## 呈报处理
## ============================================================

func _on_houkou_generated(houkou: Dictionary) -> void:
	# 只接受玩家势力的呈报
	var city = GameManager.get_city(houkou.get("city_id", ""))
	if city and city.faction_id == GameManager.player_faction_id:
		_houkou_queue.append(houkou)


func _process_houkou_queue() -> void:
	if not _is_showing_houkou:
		_show_next_houkou()


func _show_next_houkou() -> void:
	if _houkou_queue.is_empty():
		_is_showing_houkou = false
		return

	_is_showing_houkou = true
	_current_houkou = _houkou_queue.pop_front()

	_houkou_title.text = "【呈报】%s" % _current_houkou.get("title", "")
	_houkou_message.text = _current_houkou.get("message", "")
	var cost = _current_houkou.get("cost_gold", 0)
	if cost > 0:
		_houkou_cost.text = "消耗: %d 金" % cost
	else:
		_houkou_cost.text = "消耗: 无"
	_houkou_dialog.visible = true


func _on_houkou_accepted() -> void:
	_houkou_dialog.visible = false
	TurnManager.accept_houkou(_current_houkou)
	print("[呈报] 已接受: %s" % _current_houkou.get("title", ""))
	_current_houkou = {}
	_show_next_houkou()


func _on_houkou_rejected() -> void:
	_houkou_dialog.visible = false
	TurnManager.reject_houkou(_current_houkou)
	print("[呈报] 已拒绝: %s" % _current_houkou.get("title", ""))
	_current_houkou = {}
	_show_next_houkou()


## ============================================================
## 游戏启动
## ============================================================

func start_game(scenario_id: String = "207_chibi") -> void:
	print("HUD: Starting game with scenario '%s'" % scenario_id)

	# 初始化游戏
	GameManager.new_game(scenario_id)

	# 渲染地图
	var map_renderer = get_node_or_null("../Map")
	if map_renderer and map_renderer.has_method("render_full_map"):
		map_renderer.render_full_map()

	# 渲染部队
	if map_renderer and map_renderer.has_method("render_armies"):
		map_renderer.render_armies()

	# 刷新 UI
	_refresh_top_bar()

	print("HUD: Game started. Good luck, commander!")
	_refresh_army_panel()
