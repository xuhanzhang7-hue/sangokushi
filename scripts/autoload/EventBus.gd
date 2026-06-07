extends Node
## 全局事件总线 — 各系统间解耦通信

# 回合事件
signal turn_started(turn_number: int)
signal turn_ended(turn_number: int)
signal faction_turn_started(faction_id: String)
signal faction_turn_ended(faction_id: String)

# 地图事件
signal map_vertex_clicked(grid_pos: Vector2i)
signal map_city_clicked(city_id: String)
signal map_county_clicked(county_id: String)
signal map_army_clicked(army_id: int)
signal map_pass_clicked(pass_id: String)
signal map_harbor_clicked(harbor_id: String)
signal map_right_clicked(grid_pos: Vector2i)
signal map_hover_changed(grid_pos: Vector2i)

# 呈报事件
signal houkou_generated(houkou_data: Dictionary)
signal houkou_accepted(houkou_id: String)
signal houkou_rejected(houkou_id: String)

# 战斗事件
signal battle_occurred(attacker_id: int, defender_id: int, result: Dictionary)
signal siege_started(army_id: int, city_id: String)
signal city_captured(city_id: String, old_faction: String, new_faction: String)

# 武将事件
signal officer_recruited(officer_id: int, faction_id: String)
signal officer_died(officer_id: int)
signal officer_defected(officer_id: int, old_faction: String, new_faction: String)
signal officer_appointed(officer_id: int, county_id: String)

# 外交事件
signal alliance_formed(faction_a: String, faction_b: String)
signal alliance_broken(faction_a: String, faction_b: String)
signal war_declared(attacker: String, defender: String)

# 势力事件
signal faction_destroyed(faction_id: String)
signal encirclement_formed(target_faction: String)

# 游戏状态
signal game_paused()
signal game_resumed()
signal game_over(winner_faction: String)

# 通知（呈报、事件弹窗）
signal notification_requested(title: String, message: String, choices: Array)
signal notification_response(notification_id: String, choice_index: int)
