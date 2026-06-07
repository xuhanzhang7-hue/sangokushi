class_name GridUtils
extends RefCounted
## 菱形等距网格坐标转换工具
##
## 网格坐标系：(x, y) 为整数顶点坐标
## 屏幕坐标系：(sx, sy) 为像素坐标
##
## 菱形网格视觉：
##      (0,0)    (2,0)
##         \    /
##   (0,2)  (1,1)  (2,2)
##         /    \
##      (0,4)    (2,4)
##
## 屏幕投影公式：
##   sx = (x - y) * half_w + origin_x
##   sy = (x + y) * half_h - height * height_step + origin_y

# 图块尺寸（可变，支持缩放）
var tile_half_w: float = 64.0   # 菱形半宽（像素）
var tile_half_h: float = 32.0   # 菱形半高（像素）
const HEIGHT_STEP: float = 8.0  # 每级高度偏移（像素）

# 地图原点偏移（屏幕坐标）
var origin_x: float = 0.0
var origin_y: float = 0.0

# 网格范围
var grid_width: int = 200
var grid_height: int = 180


func setup(p_origin_x: float, p_origin_y: float, p_width: int, p_height: int) -> void:
	origin_x = p_origin_x
	origin_y = p_origin_y
	grid_width = p_width
	grid_height = p_height


## 网格坐标 → 屏幕坐标
func grid_to_screen(grid_x: int, grid_y: int, height: int = 0) -> Vector2:
	var sx = (grid_x - grid_y) * tile_half_w + origin_x
	var sy = (grid_x + grid_y) * tile_half_h - height * HEIGHT_STEP + origin_y
	return Vector2(sx, sy)


## 屏幕坐标 → 最近的网格顶点坐标（不考虑高程时的近似）
func screen_to_grid(screen_x: float, screen_y: float) -> Vector2i:
	var rel_x = screen_x - origin_x
	var rel_y = screen_y - origin_y
	# 逆向变换
	var gx_f = rel_x / tile_half_w + rel_y / tile_half_h
	var gy_f = rel_y / tile_half_h - rel_x / tile_half_w
	# 取整得到最近的顶点
	var gx = roundi(gx_f * 0.5)
	var gy = roundi(gy_f * 0.5)
	return Vector2i(gx, gy)


## 更精确的屏幕→网格（考虑菱形形状）
func screen_to_grid_precise(screen_x: float, screen_y: float) -> Vector2i:
	var rel_x = screen_x - origin_x
	var rel_y = screen_y - origin_y
	var gx = rel_x / tile_half_w + rel_y / tile_half_h
	var gy = rel_y / tile_half_h - rel_x / tile_half_w
	# 四舍五入
	var ix = roundi(gx * 0.5)
	var iy = roundi(gy * 0.5)

	# 验证并修正到最近的顶点
	var best_dist = INF
	var best_pos = Vector2i(ix, iy)
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var cx = ix + dx
			var cy = iy + dy
			if cx < 0 or cy < 0 or cx >= grid_width or cy >= grid_height:
				continue
			var spos = grid_to_screen(cx, cy, 0)
			var dist = Vector2(screen_x, screen_y).distance_squared_to(spos)
			if dist < best_dist:
				best_dist = dist
				best_pos = Vector2i(cx, cy)
	return best_pos


## 网格曼哈顿距离
func grid_manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## 网格直线距离（欧几里得近似）
func grid_distance(a: Vector2i, b: Vector2i) -> float:
	var dx = float(a.x - b.x)
	var dy = float(a.y - b.y)
	return sqrt(dx * dx + dy * dy)


## 获取相邻顶点（4方向）
func get_adjacent(pos: Vector2i) -> Array:
	var result: Array = []
	for dir in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
		var nx = pos.x + dir[0]
		var ny = pos.y + dir[1]
		if nx >= 0 and ny >= 0 and nx < grid_width and ny < grid_height:
			result.append(Vector2i(nx, ny))
	return result


## 获取相邻顶点（8方向，含对角）
func get_adjacent_8(pos: Vector2i) -> Array:
	var result: Array = []
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var nx = pos.x + dx
			var ny = pos.y + dy
			if nx >= 0 and ny >= 0 and nx < grid_width and ny < grid_height:
				result.append(Vector2i(nx, ny))
	return result


## 判断顶点是否在网格范围内
func is_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < grid_width and pos.y < grid_height


## 获取移动范围内可达顶点（BFS，考虑移动力和地形消耗）
func get_reachable_vertices(
	start: Vector2i,
	move_points: int,
	terrain_costs: Dictionary,
	blocked_vertices: Array = []
) -> Dictionary:
	"""
	返回 {Vector2i: remaining_move_points} 的可达顶点字典
	terrain_costs: {terrain_type: move_cost}
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
			var terrain = "plain"  # 需要外部提供terrain数据
			var cost = terrain_costs.get(terrain, 1)
			var new_remaining = remaining - cost
			if new_remaining >= 0:
				queue.append({pos = adj, remaining = new_remaining})

	return visited
