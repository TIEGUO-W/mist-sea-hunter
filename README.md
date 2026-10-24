# 雾海猎神 · 追猎角渊

直接试玩请使用相邻 Windows 试玩包中的 `SeaBoss.exe`；本文件夹是独立 Godot 源码，Godot 4.5.1+ 打开 `project.godot` 后按 F5。完整原项目的集成源码另行提供，仍使用 Godot 4.7.1 .NET 与 .NET9。

## 操作

WASD 航行 · 鼠标瞄准 / 左键攻击 · 滚轮每格切换相邻武器 · 右键按住格挡（起手瞬间可弹反） · Space 闪避 · R 抢修（两次） · Esc 暂停 · M 静音。所有指令在同屏也有按钮。

## 巨兽（本轮重建）

角渊不再是「椭球 + 管」的拼装体。`scripts/sea_monster.gd` 整体重写为**连续曲面**建模：
躯干、颅骨、下颌、触肢、鳍膜都是带真实 UV 与解析法线的顶点网格，截面用超椭圆而非正圆，
所以脊背的弓起、颞部的收窄、腹侧的压平都是形体本身而不是贴图。

造型上：掠食者楔形长颅 + 静止即张开的下颌 + 上下各两排交错獠牙（6 颗越出下颌线咬合）、
黑色眼球里程序化生成的竖瞳、六条带锯齿刃鳍与末端钩爪的盘卷巨肢、
以及一只完整的鹿角与一只折断生茬的鹿角——不对称是刻意的。

材质全部程序化：3D Voronoi 鳞片穹顶与鳞缝、`BACKLIGHT` 皮下散射、湿润镜面、
鳞缝渗出的青色生物光与稀疏发光孔。巨兽另带三盏只作用于自己的定向光层
（`layers = 1 | 4`），在风暴天幕前把剪影抠出来，同时不干扰甲板油灯。

## 界面（本轮重做）

UI 换成一套「黄铜航海仪表」设计语言：字号只有五档（34/30/22/17/14/11），
信息分三层（巨兽横幅 → 准星与威胁 → 船只/武器/雷达），一色一义
（黄铜＝奖励与弱点，青绿＝玩家资源，赤＝危险，紫＝敌方读条）。
血条是自绘的分段仪表并带幽灵残影；武器卡是单卡加冷却弧；雷达缩到 200px 重画刻度环；
顶部与暂停、胜败页共用同一套排版，并且胜败页会列出历战时长、剩余船体、抢修次数与残留敌血。

## 内容

三个 Boss 技能（陨星坠海 / 断潮雷击 / 巨兽扑击 + 近身碎浪爪）、三种武器、格挡弹反与失衡、
体力与破防、两阶段狂暴、胜败闭环与重新出航，全部可运行。
独立包不接正式奖励或存档；集成项目从标题「3D海怪试战」进入，保留原海图正式战斗。

## 素材与来源

天空全景使用 built-in imagegen 生成，prompt 与尺寸见 [天空记录](assets/environment/prompt.txt)，
实际用于 3D 天空。旧版鳞甲贴图 [鳞甲记录](assets/monster/prompt.txt) 保留在仓库中，
但本轮改为全程序化鳞片后不再被任何材质采样。用户原画保留于 `assets/portraits/`。

## 验证（本轮实测）

6 套 headless 测试全绿（在模型与界面都是整文件替换之后跑的）：

| 套件 | 项数 |
| --- | --- |
| `tests/test_aim_feedback.gd` | 21 |
| `tests/test_limb_hits.gd` | 56 |
| `tests/test_balance.gd` | 40 |
| `tests/test_combat.gd` | 67 |
| `tests/test_scene.gd` | 66 |
| `tests/test_legal_encounter.gd` | 合法通关（中距、近身爪扫/格挡两路，30/60Hz） |

```
godot --headless --path <项目> --script res://tests/test_scene.gd
```

离屏截图（不弹窗、不抢焦点；`tools/shot.gd` 已注册为 autoload，不带参数时完全不生效）：

```
godot --path <项目> --resolution 1600x900 -- \
  --shot=D:\\...\\work\\shot.png [--shot-battle] [--shot-frames=140] \
  [--shot-overlay=briefing|paused|victory|defeat]
```

建模观察台：`godot --path <项目> res://tools/model_stage.tscn -- --shot=... --angle=hero|front|side|low`。

美术方向与每一轮的约束记录在 [docs/ART-DIRECTION.md](docs/ART-DIRECTION.md)（含「右舷姿态被公平性用例锁死」这一条不可回退的约定）。
