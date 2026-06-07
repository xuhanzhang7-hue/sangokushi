extends Node2D
## 主场景启动脚本 — 挂载在 Main 节点上
##
## 等待所有 autoload 就绪后，启动新游戏。

func _ready() -> void:
	print("======================================")
	print("  三国新生 v0.1.0")
	print("  三国志11地图 × 信野新生内政")
	print("  AI 辅助编程项目")
	print("======================================")

	# 等待一帧确保所有 autoload _ready() 完成
	await get_tree().process_frame

	# 通过 HUD 控制器启动游戏
	var hud = get_node_or_null("UI")
	if hud and hud.has_method("start_game"):
		hud.start_game("207_chibi")
	else:
		push_error("MainStartup: HUD controller not found!")
