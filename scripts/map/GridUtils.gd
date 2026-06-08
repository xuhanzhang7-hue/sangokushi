class_name GridUtils
extends RefCounted
## Offset Square（偏移方格）网格坐标转换工具
##
## 奇数行右移半格，每个 tile 有 6 个邻接 tile，行为等同六边形网格
##
## 布局示例 (gx=列, gy=行):
##   Row 0 (even): [0,0] [1,0] [2,0] [3,0]
##   Row 1 (odd):    [0,1] [1,1] [2,1] [3,1]
##   Row 2 (even): [0,2] [1,2] [2,2] [3,2]
##
## 屏幕投影 (俯视图):
##   sx = gx * TILE_SIZE + (gy % 2) * TILE_SIZE * 0.5 + origin_x
##   sy = gy * TILE_SIZE + origin_y

# Tile 尺寸
const TILE_SIZE: float = 96.0
const TILE_HALF: float = 48.0

# 地图原点偏移（屏幕坐标）
var origin_x: float = 0.0
var origin_y: float = 0.0

# 网格范围
var grid_width: int = 240
var grid_height: int = 360


func setup(p_origin_x: float, p_origin_y: float, p_width: int, p_height: int) -> void:
	origin_x = p_origin_x
	origin_y = p_origin_y
	grid_width = p_width
	grid_height = p_height


## ============================================================
## 坐标转换
## ============================================================

## 网格坐标 → 屏幕坐标
func grid_to_screen(gx: int, gy: int) -> Vector2:
	var sx = gx * TILE_SIZE + (gy & 1) * TILE_HALF + TILE_HALF + origin_x
	var sy = gy * TILE_SIZE + TILE_HALF + origin_y
	return Vector2(sx, sy)


## 屏幕坐标 → 最近的 tile 坐标
func screen_to_grid_precise(screen_x: float, screen_y: float) -> Vector2i:
	var fx = screen_x - origin_x
	var fy = screen_y - origin_y

	# 先估算行
	var gy_est = roundi(fy / TILE_SIZE)
	gy_est = clampi(gy_est, 0, grid_height - 1)

	# 在估算行附近搜索最佳 tile
	var best_dist = INF
	var best_pos = Vector2i(0, 0)
	for dy in [-1, 0, 1]:
		var gy = gy_est + dy
		if gy < 0 or gy >= grid_height:
			continue
		var offset = (gy & 1) * TILE_HALF
		var gx_est = roundi((fx - offset) / TILE_SIZE)
		gx_est = clampi(gx_est, 0, grid_width - 1)
		for dx in [-1, 0, 1]:
			var gx = gx_est + dx
			if gx < 0 or gx >= grid_width:
				continue
			var spos = grid_to_screen(gx, gy)
			var dist = Vector2(screen_x, screen_y).distance_squared_to(spos)
			if dist < best_dist:
				best_dist = dist
				best_pos = Vector2i(gx, gy)
	return best_pos


## ============================================================
## 邻接
## ============================================================

## 获取 6 方向相邻 tile
func get_adjacent(pos: Vector2i) -> Array[Vector2i]:
	var gx = pos.x
	var gy = pos.y
	var result: Array[Vector2i] = []

	# 左右邻接（所有行通用）
	_add_if_in_bounds(gx - 1, gy, result)
	_add_if_in_bounds(gx + 1, gy, result)

	if gy & 1:
		# 奇数行偏移表
		_add_if_in_bounds(gx,     gy - 1, result)   # 左上
		_add_if_in_bounds(gx + 1, gy - 1, result)   # 右上
		_add_if_in_bounds(gx,     gy + 1, result)   # 左下
		_add_if_in_bounds(gx + 1, gy + 1, result)   # 右下
	else:
		# 偶数行偏移表
		_add_if_in_bounds(gx - 1, gy - 1, result)   # 左上
		_add_if_in_bounds(gx,     gy - 1, result)   # 右上
		_add_if_in_bounds(gx - 1, gy + 1, result)   # 左下
		_add_if_in_bounds(gx,     gy + 1, result)   # 右下

	return result


func _add_if_in_bounds(gx: int, gy: int, out: Array[Vector2i]) -> void:
	if gx >= 0 and gy >= 0 and gx < grid_width and gy < grid_height:
		out.append(Vector2i(gx, gy))


## 获取 6 方向邻接（含自身，用于范围查询）
func get_adjacent_8(pos: Vector2i) -> Array[Vector2i]:
	return get_adjacent(pos)


## ============================================================
## 距离
## ============================================================

## 偏移坐标 → 立方坐标
func _offset_to_cube(gx: int, gy: int) -> Vector3i:
	var cx = gx - (gy - (gy & 1)) / 2
	var cz = gy
	var cy = -cx - cz
	return Vector3i(cx, cy, cz)


## 六边形网格距离（基于立方坐标）
func grid_distance(a: Vector2i, b: Vector2i) -> int:
	var ca = _offset_to_cube(a.x, a.y)
	var cb = _offset_to_cube(b.x, b.y)
	return maxi(maxi(abs(ca.x - cb.x), abs(ca.y - cb.y)), abs(ca.z - cb.z))


## 网格曼哈顿距离（简化版六边形距离）
func grid_manhattan(a: Vector2i, b: Vector2i) -> int:
	return grid_distance(a, b)


## ============================================================
## 边界
## ============================================================

## 判断 tile 是否在网格范围内
func is_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < grid_width and pos.y < grid_height


## ============================================================
## 移动范围 (BFS)
## ============================================================

## ============================================================
## 六边形顶点（城市扩张渲染）
## ============================================================

## 获取城市六边形的6个屏幕空间顶点（顺时针）
## 视觉正六边形 — 压扁纵轴使角度均匀（sin60°≈0.866），不影响格子逻辑
## 顶点顺序：右上→右→右下→左下→左→左上
func get_hex_vertices_screen(gx: int, gy: int) -> PackedVector2Array:
	var center = grid_to_screen(gx, gy)
	var hw: float = TILE_SIZE          # 半宽 = 水平半径 = 96
	var hh: float = TILE_SIZE * 0.866  # 半高 = 正六边形垂直半径 ≈ 83.1
	var hw2: float = hw * 0.5          # 上下顶点 x 偏移 = 48
	var offsets = [
		Vector2(hw2, -hh),    # 右上
		Vector2(hw, 0),       # 右
		Vector2(hw2, hh),     # 右下
		Vector2(-hw2, hh),    # 左下
		Vector2(-hw, 0),      # 左
		Vector2(-hw2, -hh),   # 左上
	]
	var vertices = PackedVector2Array()
	for off in offsets:
		vertices.append(center + off)
	return vertices


## 获取移动范围内可达 tile（BFS，考虑移动力和地形消耗）
func get_reachable_vertices(
	start: Vector2i,
	move_points: int,
	terrain_costs: Dictionary,
	blocked_vertices: Array = []
) -> Dictionary:
	"""
	返回 {Vector2i: remaining_move_points} 的可达 tile 字典
	terrain_costs: {terrain_type: move_cost} 如 {"plain": 1, "forest": 2}
	blocked_vertices: 障碍 tile 列表
	"""
	var visited: Dictionary = {}
	var queue: Array = [{pos = start, remaining = move_points}]
	var blocked_set: Dictionary = {}
	for b in blocked_vertices:
		blocked_set[b] = true

	while not queue.is_empty():
		var current = queue.pop_front()
		var pos: Vector2i = current.pos
		var remaining: int = current.remaining

		if remaining < 0:
			continue
		if pos in visited and visited[pos] >= remaining:
			continue
		visited[pos] = remaining

		for adj in get_adjacent(pos):
			if adj in blocked_set:
				continue
			# 获取地形消耗（外部注入，默认1）
			var cost = 1
			var terrain_key = str(adj)
			if terrain_key in terrain_costs:
				cost = terrain_costs[terrain_key]
			var new_remaining = remaining - cost
			if new_remaining >= 0:
				queue.append({pos = adj, remaining = new_remaining})

	return visited
