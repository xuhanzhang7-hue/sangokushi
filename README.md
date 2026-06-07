# 三国新生 — 三国志11地图 × 信野新生内政

> AI 辅助编程项目 | Godot 4.x | v0.1.0 MVP

## 项目简介

在三国志11风格的等距菱形网格大地图上，使用信长之野望16新生的知行/郡/呈报系统进行领地经营。全部代码由 AI 辅助生成。

## 核心理念

- **地图即一切** — 战斗、内政、发展、建设全部在大地图上发生
- **知行分离** — 玩家是君主，武将代管郡县，提出呈报
- **数据即地图** — 地图完全由 JSON 数据文件定义，可直接编辑调整

## 快速开始

1. 安装 [Godot 4.x](https://godotengine.org/download/windows/)
2. 用 Godot 打开本项目的 `project.godot`
3. 按 F5 运行游戏

## 项目结构

```
sangokushi/
├── project.godot              # Godot 项目配置
├── scenes/                    # 场景文件
│   └── main.tscn              # 主场景入口
├── scripts/                   # GDScript 脚本
│   ├── autoload/              # 全局单例
│   │   ├── EventBus.gd        # 事件总线
│   │   ├── DataManager.gd     # 数据管理
│   │   ├── GameManager.gd     # 游戏状态
│   │   └── TurnManager.gd     # 回合管理
│   ├── map/                   # 地图系统
│   │   ├── GridUtils.gd       # 坐标转换
│   │   ├── MapRenderer.gd     # 地图渲染
│   │   └── MapInput.gd        # 地图输入
│   ├── game/                  # 游戏逻辑
│   │   ├── Officer.gd         # 武将
│   │   ├── City.gd            # 城市
│   │   ├── County.gd          # 郡
│   │   ├── Army.gd            # 部队
│   │   └── Faction.gd         # 势力
│   └── ui/                    # UI
│       └── HUDController.gd   # HUD控制
├── data/                      # JSON 数据文件（可编辑！）
│   ├── officers.json          # 50名武将
│   ├── cities.json            # 20座城市
│   ├── skills.json            # 32种特技
│   ├── units.json             # 12种兵种
│   ├── techs.json             # 科技树
│   ├── scenarios/             # 剧本
│   │   └── 207_chibi.json     # 207赤壁之战
│   └── map/                   # 地图数据（可编辑！）
│       ├── terrain.json       # 地形区域定义
│       ├── rivers.json        # 河流路径
│       ├── roads.json         # 道路
│       ├── passes.json        # 关隘
│       ├── harbors.json       # 港口
│       └── resources.json     # 资源点
└── docs/
    └── GDD.md                 # 完整游戏设计文档
```

## 调整地图

编辑 `data/map/` 下的 JSON 文件：
- 改城市位置 → `cities.json` 修改 `position` 坐标
- 改关隘位置 → `passes.json`
- 改河流走向 → `rivers.json` 修改 `path` 折线
- 改地形 → `terrain.json` 修改 `regions` 矩形区域

重进游戏即可看到变化。

## 开发阶段

- [x] Phase 0 — 项目搭建 + 数据文件
- [ ] Phase 1 — 地图渲染
- [ ] Phase 2 — 回合 + 内政
- [ ] Phase 3 — 部队 + 战斗
- [ ] Phase 4 — 外交 + AI
- [ ] Phase 5 — 事件 + 剧本
- [ ] Phase 6 — 打磨 + 编辑器

## License

MIT
