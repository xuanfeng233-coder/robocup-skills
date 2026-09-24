# RoboCup 比赛规则与比赛基础设施（Booster K1 视角）

> ⚠ **本队参加的是区级赛事（非正式 RoboCup），阵容 3v3**：2026 全球数字贸易创新大赛（具身智能机器人挑战赛）足球赛项。本文是正式 HSL 2026 规则的调研，赛规条文（Laws）只作参考基线，本赛事的实际规则以主办方为准，已确认和待确认的项目见 `issues.md` 的 C 组。
> **但裁判机部分直接适用**：主办方指定 **HSL GameController 7.0.0-rc.3**（`event-sop.md` §9；本地快照 `refs/robocup_league/GameController@v7.0.0-rc.3`）。所以 §4.2 的时间参数、§6 的罚时、§8 的队内通信预算（12000 条，**超额时由 GC 软件自动把比分清零**）、§9 的 v20 结构体，在本赛事中都会由裁判机自动执行，除非主办方改了 `params.yaml`。主办方讲义里的判罚按钮说明（`event-sop.md` §9.3）与本文 §6 一致。

> 调研日期：2026-09-24。适用对象：使用 Booster K1（0.95 m，约 19.5–20 kg）参加 RoboCup Humanoid Soccer League（HSL）及国内相关赛事的软件开发。
> 标注约定：**【官方】**＝直接摘自规则源码/官方代码；**【报道】**＝新闻或二手来源；**【待核实】**＝未找到权威出处或存在矛盾，不要当作确定事实使用。

## 0. 信息源（URL + 版本/年份）

| # | 来源 | URL | 版本 / 日期 | 说明 |
|---|------|-----|-------------|------|
| S1 | HSL 规则书源码（主来源） | https://github.com/RoboCup-HumanoidSoccerLeague/HSL-Rules | tag `rules-2026-v1.1.1`（2026-06-29，"final release"），commit `06c44d4` | `Rules.tex` + `rules/*.tex` + `common/variables.tex`（所有数值常量） |
| S2 | HSL 规则 Release 列表 | https://github.com/RoboCup-HumanoidSoccerLeague/HSL-Rules/releases | v0.1（2026-02-11）→ v1.0（2026-05-26）→ v1.1 → v1.1.1（2026-06-29） | v1.1.1 为 RoboCup 2026 最终版 |
| S3 | HSL 技术挑战 / 体能测试 | 同 S1：`Challenges.tex`、`HSL-Fitness-Tests.tex` | 2026 | 仅 Open Research Challenge + 3 项体能测试（试行） |
| S4 | HSL GameController（官方） | https://github.com/RoboCup-HumanoidSoccerLeague/GameController | v7.0.0（2026-07-13；RoboCup 2026 用 v7.0.0-rc.x），HEAD 2026-09-03 | `game_controller_msgs/headers/RoboCupGameControlData.h`，`config/*/params.yaml`，README |
| S5 | GC v7 Release Notes（含 HL→HSL 迁移表） | https://github.com/RoboCup-HumanoidSoccerLeague/GameController/releases | v7.0.0-rc.1（2026-06-16）～rc.3 | 结构体 version 19→20 变更说明 |
| S6 | GC v6.0.0 头文件（German Open 2026） | https://raw.githubusercontent.com/RoboCup-HumanoidSoccerLeague/GameController/v6.0.0/game_controller_msgs/headers/RoboCupGameControlData.h | v6.0.0（2026-03-11），struct version 19 | 用于对比 v19/v20 常量差异 |
| S7 | 旧 HL GameController（已废弃） | https://github.com/RoboCup-Humanoid-TC/GameController | 2025，README 已声明 2026 起被 HSL GC 取代 | HL struct version 12 |
| S8 | HSL 规则草案更新邮件 | https://lists.robocup.org/archives/list/robocup-humanoid@lists.robocup.org/message/WYB4DJHYO756JH6SOLP42RP46GVQVRXD/ | 2026-01-31 | 哨声、通信预算、按分组的球门尺寸 |
| S9 | HSL 参赛通知（CfP） | https://hsl.robocup.org/call-for-participation/ ；https://www.robocup.org/news/187 | 2026 | 分组、人数、Booster 机器人池 |
| S10 | RoboCup Humanoid Robot Program 更新 | https://www.robocup.org/news/186 | 2025/2026 | K1 RoboCup Edition；K1/T1 借用池数量 |
| S11 | HSL 2026 成绩 | https://hsl.robocup.org/results-2026/ | 2026-07 | 各组别排名与决赛比分 |
| S12 | 旧 Humanoid League 2025 规则 | https://humanoid.robocup.org/wp-content/uploads/RC-HL-2025-Rules.pdf | 2025（最后一版 HL 规则） | 仅作历史对照 |
| S13 | 2026 中国机器人大赛暨 RoboCup 中国赛 规则汇总 | https://rcccaa.drct-caa.org.cn/article_info.php?id=113 | 2026-03 | 类人组、标准平台组等 PDF |
| S14 | 中国赛 类人组 2026 规则 PDF | https://rcccaa.drct-caa.org.cn/image/file/20260319/1773889021567373.pdf | 2026 | Small/Middle/Large 三组、场地、技术挑战 |
| S15 | 中国赛 标准平台组 2026 规则 PDF | https://rcccaa.drct-caa.org.cn/image/file/20260319/1773889021363791.pdf | 2026（沿用 2025） | 仍为 NAO v6 |
| S16 | 中国赛 2026 秩序册 | https://rcccaa.drct-caa.org.cn/image/file/20260423/1776959552655445.pdf | 2026-04-22 | 时间地点、分组赛程 |
| S17 | Booster RoboCup 方案页 | https://www.booster.tech/robocup/ ；https://www.booster.tech/zh/robocup/ | 2026-09 访问 | 标注 "K1 → Middle Division" |
| S18 | Booster Champion 仿真赛 | https://champion.booster.tech/ ；本地 `refs/booster_champion_example/docs/developer_protocol.md` | 2026-07 起 | 3v3 仿真赛，GC v19 JSON |
| S19 | Booster robocup_demo（2026 GC 分支） | https://github.com/BoosterRobotics/robocup_demo/tree/sandbox/support_2026_game_controller | 2026-06-26 "compatible with HSL game_controller v7.0" | 本地 `refs/robocup_demo` main 分支仍为 HL v12 协议 |
| S20 | RoBoLeague 2025/2026 | https://tech.gmw.cn/2025-06/30/content_38124365.htm ；https://kfqgw.beijing.gov.cn/zwgkkfq/ztzl/lqztkfq/lqzx/zxxx/202606/t20260602_4681644.html | 2025-06 / 2026-06 | 【报道】 |
| S21 | K1 规格 | 本地 `refs/booster_docs/product-manual__k1__getting-started__specifications.md` | 2026 | 0.95 m / 约 19.5 kg / 22 DoF / Depth Camera / WiFi 6 / BT 5.2 |

**2027 规则**：截至 2026-09-24，HSL-Rules 仓库最后提交为 2026-06-29，无 2027 草案分支/Release；`competition_rules.tex` 中多个小节注释为 "reserved for the 2027 TC"。**2027 规则【待核实】，发布后需重新核对本文件全部数值。**

---

## 1. 关键结论（TL;DR）

| 问题 | 结论 | 依据 |
|------|------|------|
| 联赛名称 | 2026 起 Humanoid League（HL）与 Standard Platform League（SPL）合并为 **Humanoid Soccer League（HSL）**；KidSize/AdultSize 不再存在 | S1 `changes.tex`、S7 README、S9 |
| K1 属于哪组 | **Middle Division**（H_top ≤ 1.25 m 且 ≤ 25 kg）。K1 0.95 m 满足 Small 的身高，但 19.5–20 kg 超过 Small 的 15 kg 上限 → 只能进 Middle（或向上参加 Large）。Booster 官网标注 "K1 → Middle Division"，规则草稿（已注释章节）也把 "Booster K1" 列为 mid 示例 | S1 `robot_players.tex`、`competitions_divisions.tex`；S17 |
| 每队人数 | Middle：**Foundation 3 人 / Advanced 5 人**（上限）；一方选 Foundation 则双方都打 Foundation；**Middle 组从 1/4 决赛起全部为 Advanced（5v5）** | S1 §3.1–3.2 |
| K1 是否免测量 | Booster **T1、K1** 在 "pre-approved standard platforms" 列表中，未改装时无需测量，但仍需到场检查（确认未改装 + 急停演示） | S1 §3.6、competition_rules |
| 比赛时长 | 2 × 10 min，中场 ≥ 10 min；加时 2 × 5 min；点球 3 轮 + sudden death | S1 Law 7/10/14 |
| GameController | HSL GC v7.0.0，`RoboCupGameControlData` **version 20**，header `"RGme"`，UDP 广播 3838（2 Hz，stop 时临时 5 Hz）；返回包 `"RGrt"` version 4，**单播**到 GC 3939（0.5–2 Hz） | S4 |
| 队内通信 | UDP **广播**，端口 **10000 + 队号**，单包 payload ≤ **512 B**，整场预算 **12000 条**（仅 READY/SET/PLAYING 计数）；超额或超长 → **本场进球全部作废** | S1 §3.9、S4 |
| RoboCup 2026 Middle 冠军 | B-Human（K1），决赛 6:0 胜 HTWK Robots；Middle 共 16 队 | S11 |
| 国内赛 | 2026 RoboCup 中国赛（2026-05-02～04，北京首都国际会议中心）类人组已按 HSL 分为 Small/Middle/Large，Small 与 Middle 共用 9×6 m 场地 | S14、S16 |

---

## 2. 联赛体系与分组

### 2.1 HSL 2026 三个 Division【官方 S1 Law 3】

| Division | H_top 上限 | 体重上限 | Foundation 人数 | Advanced 人数 | 可用场地 | 用球 |
|----------|-----------|---------|----------------|--------------|---------|------|
| Small | ≤ 1.10 m | ≤ 15 kg | 4 | 7 | S-Field | FIFA Mini Ball（草稿：SPL 10 cm 球或 FIFA mini size 1） |
| **Middle** | **≤ 1.25 m** | **≤ 25 kg** | **3** | **5** | **S-Field 或 M-Field** | **FIFA size 3 或 4**（草稿注明 size 3 preferred；比赛用哪种由 TC/OC 赛前公布） |
| Large | ≤ 1.90 m | ≤ 80 kg | 3 | 5 | M-Field 或 L-Field | FIFA size 5 |

- 队伍注册时确定 Division，赛中**不得更换**；配置（Foundation/Advanced）赛前提交偏好，赛中可申请更改（组织方裁量）。
- 至多 1 名 goalkeeper；满员时必须有 goalkeeper。替补人数不限。
- GameController 配置目录：`config/middle_foundation`（playersPerTeam=3）、`config/middle_advanced`（playersPerTeam=5）。机器人可由 `competitionType==1 (MIDDLE)` + `playersPerTeam` 判断当前配置。
- RoboCup 2026 Middle 参赛队（GC teams.yaml）：B-Human、Badger Bots、Berlin United、CAU Mountain&Sea、HTWK Robots、HULKs、Inha-United、Invic、NUbots、RedbackBots、RFC-Tsudanuma、Rhoban、RoboEireann、Ruhrbot Devils、rUNSWift、THMOS、whIRLwind Amsterdam 等（多为原 SPL 队，从 NAO 迁移到 K1）。

### 2.2 K1 合规核对

| 项目 | 规则 | K1 数值 | 结论 |
|------|------|---------|------|
| 身高 | Middle ≤ 1.25 m | 0.95 m | ✓ |
| 体重 | Middle ≤ 25 kg（Small ≤ 15 kg） | 约 19.5 kg（官网称 20 kg） | Middle ✓ / Small ✗ |
| BMI = M/H² | 5 ≤ BMI ≤ 30 | 19.5/0.95² ≈ 21.6 | ✓ |
| 腿长 | 0.35·H ≤ H_leg ≤ 0.7·H | 未测 | 预批准平台免测 |
| 臂展 | 0.8·H ≤ A_span ≤ 1.2·H | 未测 | 预批准平台免测 |
| 头高 | 0.1·H ≤ H_head ≤ 0.3·H | 未测 | 预批准平台免测 |
| 相机 | 视野连续，水平 ≤ 220°、垂直 ≤ 160°（表中 RGB ≤ 180°/140°）；须在头部 | Depth Camera（头部） | 预批准；若为主动红外深度则属 "permitted but discouraged" 【待核实 K1 深度相机类型】 |
| 罗盘 | 禁止（IMU 内置罗盘须禁用且不得使用） | IMU | 软件中**不要使用磁力计** |
| 蓝牙 | 场地附近禁止其它 2.4/5 GHz 设备（含蓝牙） | BT 5.2 | 建议比赛时关闭蓝牙/遥控手柄【规则未明确针对机器人本体，待核实】 |

> **K1 Air**：【报道】RoboCup 2026 Small 组冠军 Invic（武汉大学）使用 "Booster K1 Air"（推测为减重版以满足 ≤ 15 kg）。官方规格【待核实】。

### 2.3 与旧 HL 2025 对照（仅供理解旧代码/旧论文）【S12】

| 项目 | HL 2025 KidSize | HL 2025 AdultSize | HSL 2026 Middle |
|------|----------------|-------------------|-----------------|
| 身高 | 40–100 cm | 100–200 cm | ≤ 125 cm 且 ≤ 25 kg |
| 每队人数 | ≤ 4 | ≤ 3 | 3（Foundation）/ 5（Advanced） |
| 场地 | 9 × 6 m | 14 × 9 m | S-Field 9×6 或 M-Field 14×9 |
| 球 | FIFA size 1 | FIFA size 5 | FIFA size 3/4 |
| GC 协议 | HL struct v12（`secondaryState`、`kickOffTeam`…） | 同左 | struct v20 |

K1 在 2025 年按身高属 KidSize（Booster 官网称 K1 为 "2025 KidSize 冠军机型"）；2026 年因体重划入 Middle。

---

## 3. 场地、球门、球【官方 S1 Law 1–2】

### 3.1 场地尺寸（单位 m；线宽计入所围区域，尺寸量至线外沿）

| ID | 项目 | S-Field（原 KidSize/SPL） | M-Field（原 AdultSize） | L-Field |
|----|------|------------------|----------------|---------|
| A | 场地长 | 9.0 | 14.0 | 22.0 |
| B | 场地宽 | 6.0 | 9.0 | 14.0 |
| C | 球门深 | 0.5–1.0 | 0.7–1.2 | 1.0–2.0 |
| D | 球门宽（按场地） | 1.8–1.9 | 2.4–2.6 | 2.6–3.1 |
| E | 球门区长（纵深） | 1.0 | 1.0 | 1.0 |
| F | 球门区宽 | 3.0 | 4.0 | 5.0 |
| G | 罚球区长（纵深） | 2.0 | 3.0 | 3.5 |
| H | 罚球区宽 | 4.0 | 6.0 | 7.0 |
| I | 罚球点距球门线 | 1.5 | 2.0 | 2.5 |
| J | 中圈直径 | 1.5 | 3.0 | 4.0 |
| K | 场外缓冲带（最小） | 1.0 | 1.0 | 1.0 |
| L | 角球弧半径 | 无 | 0.5 | 1.0 |
| – | 线宽 | 0.05 | 0.05 | 0.12 |
| – | 罚球点/中点标记尺寸 | 0.10 | 0.10 | 0.15 |

- 草皮：人工草，高约 20–30 mm；**Small 组草高约 8–12 mm**。颜色绿色，线白色（胶带/油漆/白草均可），线宽 5–12 cm。
- 相邻场地间距 < 3 m 时设挡板；否则可能看到邻场球门/球/线 —— **感知需抗邻场干扰**。
- 照明：不做受控照明，最低约 300 lx（建议 400 lx），可能有窗光、阴影、眩光。
- Technical Area：GC 操作员位于中线侧；**主队在操作员右侧，客队在左侧**。

### 3.2 球门（按 Division）【S1 表 goal_dim】

| Division | 宽 | 高 | 深 |
|----------|----|----|----|
| Small | 1.8–1.9 | 1.2–1.3 | 0.5–1.0 |
| **Middle** | **2.4–2.6** | **1.5–1.9** | **0.7–1.2** |
| Large | 2.6–3.1 | 1.8–2.0 | 1.0–2.0 |

- 门柱/横梁白色，截面宽 7–12 cm；球网白/灰/黑。
- 2026-01-31 邮件（S8）：Middle 在 S-Field 上用 2.4 × 1.6 m 球门，在 M-Field 上用 2.4 × 1.8 m 球门。
- **RoboCup 2026 仁川 Middle 组实际使用 S-Field 还是 M-Field、size 3 还是 size 4 球【待核实】**（官方赛程/成绩页未写明；Booster Champion 仿真默认 M-Field 14 × 9 m）。

### 3.3 Inside / Outside 定义
- 机器人：身体任一部分触地于区域内或边线上即算 inside。
- 球：任一部分压线/在区域内（含空中投影）即 inside；**进球**需整球完全越过球门线、在门柱之间横梁之下。

---

## 4. 比赛流程与状态机【官方 S1 Law 7】

### 4.1 状态定义与机器人允许行为

| 状态（GC `state`） | 值 | 机器人必须/允许 | 违规后果 |
|------|----|----------------|---------|
| INITIAL | 0 | 由 handler 摆放；可转头、做标定；**禁止迈腿/行走** | – |
| READY | 1 | 自主走到开球/定位球合法位置；最长 **45 s**，计时到 GC 自动转 SET（操作员也可提前转 SET） | 到 SET 时不合法 → Illegal Positioning |
| SET | 2 | 静止；**仅允许头、手臂动作及跌倒后起身**；不得迈腿 | Motion in Set（**原地罚 15 s**） |
| PLAYING | 3 | 正常比赛 | – |
| FINISHED | 4 | 半场/全场结束，停止比赛行为 | – |
| penalized（每机器人） | `penalty != 0` | 被移出场外静止等待；罚时结束后**自主从 re-entry 点入场** | 违规干预 → 罚时重置 |
| Brief stop（`stopped == 1`） | – | **立即安全停下并保持静止，连起身都不允许**；行为同 SET | Motion in Stop（标准移除罚，递增） |
| Timeout | 发送为 `state=INITIAL`、`gamePhase=TIMEOUT` | 同 INITIAL | – |

### 4.2 时间参数（规则变量 `common/variables.tex` + GC `params.yaml`）

| 参数 | 值 | 备注 |
|------|----|------|
| 半场时长 | 600 s | 从首个 PLAYING 开始计 |
| 中场休息 | ≥ 600 s | 可协商 |
| 加时 | 2 × 300 s，前有 5 min 休息 | 仅淘汰赛 |
| READY 时长（kick-off / penalty kick） | 45 s | 规则 penalty kick 文字写 "30 s"，但 GC 与变量 `PenaltyKickSetupTime` 为 45 s → 以 GC 为准【矛盾，待核实】 |
| SET→PLAYING 延迟 | **10 s**（kick-off、dropped ball、penalty kick） | 鼓励哨声检测 |
| Kick-off 自由球时间 | 10 s（踢出并明显移动或哨后 10 s，先到为准） | GC `kickOff.duration` |
| 任意球完成时限 | 45 s | 超时 "Ball Free" |
| 点球 / 点球大战单次时限 | 60 s | |
| 标准移除罚 | 45 s，递增 +10 s/次（按队累计） | 见 §6 |
| 原地罚（Motion in Set） | 15 s | 不递增 |
| Local Game Stuck | 球 10 s 无明显移动且有机器人在附近 | 罚最近机器人 |
| Global Game Stuck | 30 s 无机器人进入球 1 m 内 | Dropped ball |
| 跌倒起身 | 20 s 内必须开始起身；最多 3 次（被干扰 4 次） | 否则 Incapable |
| 不活动 | 10 s 无行走/转身/找球/跟踪球 | Incapable |
| Ball holding | 场上球员 5 s；守门员在本方罚球区 10 s | |
| 队伍 timeout | 每场 1 次，≤ 5 min；对方须 2 min 内就绪 | GC `timeoutDuration 300` |
| 裁判 timeout | GC 600 s | |
| Mercy rule | 净胜 10 球立即结束 | GC 2026-09-03 起改为可选参数 |
| 游戏时钟 | READY/SET 期间**不停表**（每半场首次开球除外） | |

### 4.3 哨声信号【S1 Law 7.4】
| 转换 | 哨声 |
|------|------|
| SET → PLAYING | 一短声 |
| 上半场结束（FINISHED） | 两短声 |
| 全场结束 | 两短 + 一长 |

- 裁判在中线 T 字交点附近吹哨。**误响应邻场哨声 → Motion in Set**。
- Brief stop 由裁判口头喊 "Stop Play" + GC `stopped=1`。
- 2026 **不使用 visual referee / 裁判手势**进入正赛（S8：可能以单独挑战形式出现；规则中任意球手势章节已注释掉）。旧 SPL 2025 的 "Standby 阶段识别裁判手势" 在 HSL 2026 中不存在。

### 4.4 Brief stop（GC `stopped`）
- 任何时候可由裁判触发（放球、移除罚下机器人、紧急情况）。**游戏时钟继续走**，二级计时与罚时暂停；恢复后状态不变（任意球/开球信息保留）。
- GC 在 stop 时立即发包并临时提高到 5 Hz。
- 任意球流程本身就是：GC 设 `setPlay` + `stopped=1`（摆球）→ 裁判恢复 `stopped=0` → 45 s 计时。

---

## 5. 开球与定位球【官方 S1 Law 8, 13–17】

| 情形 | GC 表示 | 摆位 / 限制 | 进球规则 |
|------|---------|------------|---------|
| **Kick-off** | READY/SET，`setPlay=SET_PLAY_NONE`，`kickingTeam=开球队号` | 球在中点。非开球队：全部在本方半场且在**中圈外**；开球队：本方半场或中圈内，最多 1 台越过中线（必须在中圈内），该台即指定开球者且必须由它开球 | **不得直接射门得分**；开球队场上 ≥ 3 台时需**两台不同机器人**触球后才能进球；≤ 2 台时开球者须在中圈外再触球一次 |
| 开球权 | – | 上半场：猜硬币胜方选开球或选边；下半场：另一方；进球后：失球方；timeout 后：未叫 timeout 的一方 | – |
| **Dropped ball** | READY/SET，`setPlay=NONE`，`kickingTeam=255` | 双方在本方半场，SET 时**任何机器人不得进中圈**；裁判放球在中点 | 立即 in play，可直接进球 |
| **Kick-in / Throw-in**（间接） | PLAYING，`setPlay=SET_PLAY_THROW_IN(4)` | 球放在出界点边线上；对方须离球 ≥ 中圈半径 | 间接；踢出后同一机器人再次触球前须经他人触球（队伍场上 ≥ 3 台时适用） |
| 手抛界外球 | 同上 | 面向场内、双脚部分在边线上/外、至少一手持球、从头后过顶、10 s 内出手 | 违规 → 对方任意球 |
| **Goal kick**（直接） | `SET_PLAY_GOAL_KICK(5)` | 球放在出界一侧**球门区角**（球门区线与球门线交点，场内侧）；对方须在**整个罚球区外** | 直接 |
| **Corner kick**（直接） | `SET_PLAY_CORNER_KICK(6)` | 球放在出界一侧**场地角** | 直接 |
| **Pushing free kick**（直接） | `SET_PLAY_DIRECT_FREE_KICK(1)` | 球原地；对方离球 ≥ 中圈半径 | 直接 |
| 间接任意球 | `SET_PLAY_INDIRECT_FREE_KICK(2)` | 在对方罚球区内犯规的间接任意球移到平行于球门线的罚球区线上最近点 | 间接 |
| **Penalty kick** | READY→SET→PLAYING，`setPlay=SET_PLAY_PENALTY_KICK(3)` | 守门员双脚在门线上；进攻方最多 1 台在对方罚球区内（SET 时不得挡住罚球点）；其余在罚球区外且离罚球点 ≥ 中圈半径，并在罚球点之后 | 守门员触球前不得扑倒；踢球者二次触球即结束；60 s |
| **Penalty shoot-out** | `gamePhase=GAME_PHASE_PENALTY_SHOOT_OUT(1)`，`setPlay=PENALTY_KICK` | 1 射手 vs 1 守门员；射手摆在罚球区边缘面向球门，门将在门线中央；未被选中的机器人为 `PENALTY_SUBSTITUTE` | 每队 3 球，之后 sudden death（最多 3 轮，按射门质量分级），再平抛硬币 |

**avoidance radius = 中圈半径**：S-Field 0.75 m，M-Field 1.5 m（Goal kick 例外：整个罚球区）。
**任意球失败**：进攻方 45 s 内未执行 → "Ball Free"，防守方先触球可直接得分（即使原为间接）。
**直接/间接任意球直接踢进本方球门** → 对方角球。

---

## 6. 犯规与罚则【官方 S1 Law 12 + GC params】

罚则类型：
- **Standard removal penalty**：handler 将机器人移出场外；放在**本方半场罚球点高度的边线外**、面向对侧边线（被占用则就近，但**必须仍在本方半场**）；GC contact 报 "<颜色> <号> Ready" 后操作员才**开始**计时；结束后 GC 解除，机器人**自主入场**。罚时在 SET 中不减少；维修期间不计时；有人触碰机器人 → 罚时重置。每半场结束清零。
- **In-place penalty**：仅 Motion in Set。**不移出场地**，原地立即停止，15 s 内除起身外不得移动。
- 基础 45 s，**incremental 罚**使本队后续罚时 +10 s。

| 犯规 | GC 常量（v20） | 时长 | 递增 | 触发条件（要点） |
|------|--------------|------|------|-----------------|
| Illegal Positioning | `PENALTY_ILLEGAL_POSITIONING = 1` | 45 s | 否 | SET 时站位违规/在场外；侵入任意球/点球回避区；**本方球门区内同时 > 3 台**（SET/PLAYING）；被推入球门区 5 s 内未离开 |
| Motion in Set | `PENALTY_MOTION_IN_SET = 2` | 15 s 原地 | 否 | SET 中迈腿/移动（起身、头、手臂除外）；**误听他场哨声也算** |
| Motion in Stop | `PENALTY_MOTION_IN_STOP = 3` | 45 s | 是 | brief stop 期间迈腿/移动（连起身都不行） |
| Local Game Stuck | `PENALTY_LOCAL_GAME_STUCK = 4` | 45 s | 否 | 球 10 s 未明显移动且有机器人在附近 → 罚离球最近者，比赛继续 |
| Incapable Robot | `PENALTY_INCAPABLE_ROBOT = 5` | 45 s | 否 | 10 s 无活动/关机；跌倒 20 s 未尝试起身或 3 次（受扰 4 次）失败；**站姿宽度 > 约 1.5 倍肩宽持续 10 s** |
| Request for Pick-up | `PENALTY_PICK_UP = 6` | 45 s（INITIAL/Timeout 中为 0 s） | 否 | 仅限危险情况，须主裁批准；"配置错误/看不到球"不批准；未经批准触碰 → 罚 + 警告 |
| Ball Holding | `PENALTY_BALL_HOLDING = 7` | 45 s | 是 | 凸包覆盖球 > 一半：场上 > 5 s、守门员（一脚在本方罚球区）> 10 s；快速放-控视为连续；摔在球上/球卡双腿间不判（"Clear Ball"） |
| Leaving the Field | `PENALTY_LEAVING_THE_FIELD = 8` | 45 s | 是 | 离开铺草区域；撞门柱/网 > 5 s；手指等缠网 |
| Playing with Arms/Hands | `PENALTY_PLAYING_WITH_ARMS_HANDS = 9` | 45 s | 是 | 非守门员（或守门员在罚球区外）主动用手臂触球；跌倒/起身中意外触球不罚，但由此进球（乌龙除外）不算 → 球门球 |
| Pushing | `PENALTY_PUSHING = 10` | 45 s | 是 | 足以使对手失稳的接触，或接触 > 5 s；正面对顶不算（除非一方明显更快/更猛）；静止机器人（含起脚时球在可踢范围内）不判 |
| Caution（黄牌） | `PENALTY_CAUTIONED = 11` | 45 s | 是 | 严重犯规/危险/反复；第二黄 → 红 |
| Sent off（红牌） | `PENALTY_SENT_OFF = 12` | 全场 | – | 不能替补，少一人比赛 |
| Substitute | `PENALTY_SUBSTITUTE = 13` | – | – | 替补/点球大战未选中者 |

补充：
- 在**球附近（中圈半径内）**犯规 → 停止比赛，罚下后对方获 Pushing Free Kick（直接）；远离球犯规只罚人。
- 被判后除站起/坐下外不得任何移动。
- 裁判卡：蓝牌＝时间罚，黄＝caution，红＝send-off。
- 通信违规（超预算/超 512 B）：GC 标记 `illegal_communication`，**本队比分清零且后续进球不计**（规则："all goals automatically nullified"）。其他无线违规：首次警告，再犯可能取消全部比赛资格。
- 禁止强光、禁止模仿哨声干扰。

---

## 7. 机器人硬件、传感器与安全【官方 S1 Law 3–4】

| 类别 | 规定 |
|------|------|
| 形态 | 躯干+头+双臂+双腿，人形比例；只允许双足走/跑/跳；**禁止手臂持续支撑行走** |
| 自主 | 禁止外部供电、遥操作、遥控、远程计算/感知；**无任何场外感知或计算** |
| 视觉 | 相机在头部；视野连续，静态 ≤ 220° × 160°；可动总视野 ≤ 340° × 220°；可见光范围；允许事件相机 |
| 深度 | 被动（双目）鼓励；主动（红外投射/ToF）允许但不鼓励，未来可能禁止 |
| 姿态 | 陀螺/加速度计/IMU 允许；**罗盘禁止**（IMU 内罗盘须禁用） |
| 声音 | 麦克风在头部，数量不限 |
| 触觉 | 力/触/按钮/电容传感器，位置数量不限 |
| 测距 | 1D 近距离传感器最多 4 个（不鼓励） |
| 球衣 | 背心式，覆盖上身 ≥ 50%，主色 > 一半；号码 1–20，背大前小；守门员须可区分（不同颜色或赛前告知号码）；需提交两套不同纯色设计，赛前审核 |
| 机身颜色 | 以黑/灰/白/银等中性色为主，不反光 |
| 急停 | 必须能被 handler 立即物理停止（把手/按钮/遥控急停）；遥控急停一对一绑定；若急停设备同时具备遥控功能（如手柄/App），比赛中须放在技术区标记区域且只能用于急停；**GC stop（`stopped`）时须立即进入安全姿态** |
| 检录 | 所有平台赛前检录（身高体重、传感器、球衣、急停演示）；改装后须复检 |

---

## 8. 通信规则【官方 S1 §3.9 + S4】

| 通道 | 方向 / 传输 | 端口 | 频率 / 限制 |
|------|-----------|------|-----------|
| GC 控制包 `RoboCupGameControlData` | GC → 机器人，UDP 广播（可配置 255.255.255.255） | **3838** | 2 Hz；play stopped 时立即发送并临时 5 Hz |
| 机器人状态包 `RoboCupGameControlReturnData` | 机器人 → GC，**UDP 单播**（发往最后收到控制包的源 IP） | **3939** | **必须**发送，0.5–2 Hz；GC 以 2 s/4 s 判断连接好/差 |
| 队内通信（team message） | 机器人 ↔ 机器人，**UDP 广播**（GC 同时监听，亦接收组播 239.0.0.1） | **10000 + teamNumber** | payload ≤ **512 B**，格式自定；整队整场 ≤ **12000** 条 |
| Debug | 机器人 → 本队一台有线网络设备，单播 UDP | 自定 | 每台 ≤ 1 包/s；包大小仅受 UDP 上限（约 64 kB） |
| Monitor（TCM/GSV） | 监视器 → GC 请求 `"RGTr"`+版本 0 | 3636 | 监视器收 `"RGTD"` 真实状态（3838）与转发的状态包（3940）。**已发过状态包的主机不能注册为 monitor**（防作弊） |

队内通信预算细则：
- 只在 **READY / SET / PLAYING** 计数；INITIAL、FINISHED、Timeout、**点球大战**不计。
- 每加 1 分钟补时 +600；进入加时赛 +6000。
- 当前剩余额度由 GC 包 `teams[i].messageBudget` 实时下发 → **行为层应自适应发送频率**。
- 估算：2 × 600 s + 各半场首个 READY/SET ≈ 1300 s → 全队约 9 条/s；3 人约 3 条/s/台，5 人约 1.8 条/s/台（建议事件驱动 + 余量保护）。
- 禁止 ad-hoc 直连、禁止机器人间单播；必须使用组织方 AP；网络参数（SSID、IP 段、信道）现场公布。
- 历史协议 `mitecom`（2017）、`RobocupProtocol`（protobuf，2019）为旧 HL 混合队协议，**HSL 不要求**。

违规处罚分两级（`refs/robocup_league/HSL-Rules/rules/game.tex` Jamming 小节 `\paragraph{Wireless Communication}` 起；数值在 `common/variables.tex:51-53`）：
- **违反一般通信规定**（如 ad-hoc 直连、机器人间单播、Debug 超频）：首次**警告**；屡犯**可能取消整个赛事资格**（含全部技术挑战与附加赛）。
- **超出机器人间通信限额**（由 GC 统计的 12000 条预算）：**本场全部进球自动作废**。
- 超长包（> 512 B）是按超限处理还是按一般违规处理，规则原文没有写明（`issues.md` R3）。
- 同一小节还规定：不得用声音干扰哨声识别，不得使用闪光灯或强光源。

---

## 9. GameController 详解（HSL GC v7，struct v20）

### 9.1 `RoboCupGameControlData.h` 原文（S4，2026-05-24 起未变）

```c
#define GAMECONTROLLER_DATA_PORT   3838
#define GAMECONTROLLER_RETURN_PORT 3939

#define GAMECONTROLLER_STRUCT_HEADER  "RGme"
#define GAMECONTROLLER_STRUCT_VERSION 20

#define MAX_NUM_PLAYERS 20

#define TEAM_BLUE   0 // blue, cyan
#define TEAM_RED    1 // red, magenta, pink
#define TEAM_YELLOW 2 // yellow
#define TEAM_BLACK  3 // black, dark gray
#define TEAM_WHITE  4 // white
#define TEAM_GREEN  5 // green
#define TEAM_ORANGE 6 // orange
#define TEAM_PURPLE 7 // purple, violet
#define TEAM_BROWN  8 // brown
#define TEAM_GRAY   9 // lighter gray

#define COMPETITION_TYPE_SMALL  0
#define COMPETITION_TYPE_MIDDLE 1
#define COMPETITION_TYPE_LARGE  2

#define GAME_PHASE_NORMAL            0
#define GAME_PHASE_PENALTY_SHOOT_OUT 1
#define GAME_PHASE_EXTRA_TIME        2
#define GAME_PHASE_TIMEOUT           3

#define STATE_INITIAL  0
#define STATE_READY    1
#define STATE_SET      2
#define STATE_PLAYING  3
#define STATE_FINISHED 4

#define SET_PLAY_NONE               0
#define SET_PLAY_DIRECT_FREE_KICK   1
#define SET_PLAY_INDIRECT_FREE_KICK 2
#define SET_PLAY_PENALTY_KICK       3
#define SET_PLAY_THROW_IN           4
#define SET_PLAY_GOAL_KICK          5
#define SET_PLAY_CORNER_KICK        6

#define KICKING_TEAM_NONE 255

#define PENALTY_NONE                          0
#define PENALTY_ILLEGAL_POSITIONING           1
#define PENALTY_MOTION_IN_SET                 2
#define PENALTY_MOTION_IN_STOP                3
#define PENALTY_LOCAL_GAME_STUCK              4
#define PENALTY_INCAPABLE_ROBOT               5
#define PENALTY_PICK_UP                       6
#define PENALTY_BALL_HOLDING                  7
#define PENALTY_LEAVING_THE_FIELD             8
#define PENALTY_PLAYING_WITH_ARMS_HANDS       9
#define PENALTY_PUSHING                       10
#define PENALTY_CAUTIONED                     11
#define PENALTY_SENT_OFF                      12
#define PENALTY_SUBSTITUTE                    13

struct RobotInfo
{
  uint8_t penalty;             // penalty state of the player (PENALTY_NONE, etc)
  uint8_t secsTillUnpenalised; // estimate of time till unpenalised
  uint8_t cautions;            // number of cautions (yellow cards)
};

struct TeamInfo
{
  uint8_t teamNumber;                        // unique team number
  uint8_t fieldPlayerColour;                 // colour of the field players (TEAM_BLUE, etc)
  uint8_t goalkeeperColour;                  // colour of the goalkeeper (TEAM_BLUE, etc)
  uint8_t goalkeeper;                        // player number of the goalkeeper (0-MAX_NUM_PLAYERS)
  uint8_t score;                             // team's score
  uint8_t penaltyShot;                       // penalty shot counter
  uint16_t singleShots;                      // bits represent penalty shot success
  uint16_t messageBudget;                    // number of team messages the team is allowed to send for the remainder of the game
  struct RobotInfo players[MAX_NUM_PLAYERS]; // the team's players
};

struct RoboCupGameControlData
{
  char header[4];           // header to identify the structure
  uint8_t version;          // version of the data structure
  uint8_t packetNumber;     // number incremented with each packet sent (with wraparound)
  uint8_t playersPerTeam;   // the number of players on a team
  uint8_t competitionType;  // type of the competition (COMPETITION_TYPE_SMALL, etc)
  uint8_t stopped;          // 1 = play is currently stopped, 0 otherwise
  uint8_t gamePhase;        // phase of the game (GAME_PHASE_NORMAL, etc)
  uint8_t state;            // state of the game (STATE_INITIAL, etc)
  uint8_t setPlay;          // active set play (SET_PLAY_NONE, etc)
  uint8_t firstHalf;        // 1 = game in first half, 0 otherwise
  uint8_t kickingTeam;      // the team number of the next team to kick-off, free kick etc, or KICKING_TEAM_NONE
  int16_t secsRemaining;    // estimate of number of seconds remaining in the half
  int16_t secondaryTime;    // number of seconds shown as secondary time (remaining ready, until free ball, etc)
  struct TeamInfo teams[2];
};

// data structure header
#define GAMECONTROLLER_RETURN_STRUCT_HEADER      "RGrt"
#define GAMECONTROLLER_RETURN_STRUCT_VERSION     4

struct RoboCupGameControlReturnData
{
  char header[4];     // "RGrt"
  uint8_t version;    // has to be set to GAMECONTROLLER_RETURN_STRUCT_VERSION
  uint8_t playerNum;  // player number starts with 1
  uint8_t teamNum;    // team number
  uint8_t fallen;     // 1 means that the robot is fallen, 0 means that the robot can play

  // position and orientation of robot
  // coordinates in millimeters
  // 0,0 is in center of field
  // +ve x-axis points towards the goal we are attempting to score on
  // +ve y-axis is 90 degrees counter clockwise from the +ve x-axis
  // angle in radians, 0 along the +x axis, increasing counter clockwise
  float pose[3];         // x,y,theta

  // ball information
  float ballAge;         // seconds since this robot last saw the ball. -1.f if we haven't seen it

  // position of ball relative to the robot
  // coordinates in millimeters
  // 0,0 is in center of the robot
  // +ve x-axis points forward from the robot
  // +ve y-axis is 90 degrees counter clockwise from the +ve x-axis
  float ball[2];
  // （C++ 构造函数省略：默认 version=4, playerNum=0, teamNum=0, fallen=255, ballAge=-1.f, pose/ball=0）
};
```

### 9.2 二进制布局（实测 `sizeof`，小端，自然对齐，无 padding）

| 结构 | 大小 | 关键偏移 |
|------|------|---------|
| `RobotInfo` | 3 B | – |
| `TeamInfo` | 70 B | players 从偏移 10 开始，20 × 3 B |
| `RoboCupGameControlData` | **158 B** | header 0，version 4，packetNumber 5，playersPerTeam 6，competitionType 7，stopped 8，gamePhase 9，state 10，setPlay 11，firstHalf 12，kickingTeam 13，secsRemaining 14（int16 LE），secondaryTime 16，teams 18 |
| `RoboCupGameControlReturnData` | **32 B** | header 0，version 4，playerNum 5，teamNum 6，fallen 7，pose 8/12/16，ballAge 20，ball 24/28（float32 LE） |

### 9.3 GC 端语义要点（读 Rust 源码 `game_controller_core` 得出）

| 语义 | 说明 |
|------|------|
| `teams[0]` / `teams[1]` | `teams[0]` 恒为（GC 视角）**防守左侧球门**的队；换边后顺序会变 → 必须按 `teamNumber` 查找本队，不能写死下标 |
| players 下标 | `players[playerNumber-1]`，playerNumber = 球衣号 1–20 |
| Kick-off | GC 内部 SetPlay::KickOff 在报文中映射为 **`SET_PLAY_NONE`**；判断方法：`state∈{READY,SET}` 且 `setPlay==NONE`，`kickingTeam==本队` → 我方开球；`==255` → dropped ball |
| 进球后 | GC 自动进入 READY（对方开球）；若触发 mercy rule 直接结束 |
| Global game stuck | 等价于 `kickingTeam=NONE` 的 kick-off → READY（dropped ball） |
| 任意球 | 保持 `state=PLAYING`，设置 `setPlay` 与 `kickingTeam`，同时 `stopped=1`；恢复后 `secondaryTime` 倒计时 45 s，到时 `setPlay` 回 NONE |
| Penalty kick（常规时间） | 进入 READY（45 s）→ SET → PLAYING，`setPlay=PENALTY_KICK` |
| **10 s 假状态** | SET→PLAYING 后，控制包**最多 10 s 仍显示 SET**（或直到出现 SET 中不可能发生的事件）；monitor 收到的是真实状态。→ 听到哨声的机器人可提前开踢，否则晚 10 s |
| Timeout | 报文 `state=INITIAL`，`gamePhase=TIMEOUT` |
| `secsTillUnpenalised` | 标准移除罚在操作员"开始计时"之前为 **0**，但 `penalty` 仍非 0 → **只用 `penalty==PENALTY_NONE` 判断是否可入场** |
| Motion in Set 计时 | 仅在 READY 或 PLAYING 中流逝，到时自动解除 |
| `secsRemaining` / `secondaryTime` | `int16`，**可为负**（补时、超时） |
| `messageBudget` | 本队剩余队内消息数；耗尽后再发即违规 |
| `cautions` | 黄牌数；第二张黄牌转 `PENALTY_SENT_OFF` 并清零 cautions |
| 返回包校验 | 长度必须 32、header/version 正确、playerNum ∈ 1..20、**`fallen` 只能 0/1（构造函数默认 255 会被拒收！）**、pose/ballAge/ball 不得为 NaN |

### 9.4 版本差异（易踩坑）

| 版本 | 使用场合 | 与 v20 差异 |
|------|---------|-----------|
| HL v12（`HlRoboCupGameControlData`） | 旧 HL（≤ 2025）；**本地 `refs/robocup_demo` main 分支 `game_controller_node.cpp` 仍按此结构解析并校验 version==12** | 字段完全不同：`uint16 version`、`gameType`、`kickOffTeam`（`DROPBALL=255`）、`secondaryState`/`secondaryStateInfo[4]`、`dropInTeam/Time`、`coachMessage`，`HL_MAX_NUM_PLAYERS=11`；返回包 HL v2 只有 `message` 字段 → **无法解析 HSL v20 包** |
| SPL 旧版（本地 `robocup_demo` 头文件中为 v15） | 旧 SPL | 结构与 v20 接近（`competitionPhase` 等字段、无 `stopped`），常量不同 |
| **v19**（GC v6.0.0，German Open 2026） | Booster Champion 仿真 JSON 也标注 "v19 semantics" | `RobotInfo` 多一个 `warnings` 字节；**罚则常量编号不同**：v19 中 LOCAL_GAME_STUCK=3、INCAPABLE=4、PICK_UP=5、BALL_HOLDING=6、LEAVING=7、ARMS_HANDS=8、PUSHING=9、SENT_OFF=10、SUBSTITUTE=11；无 MOTION_IN_STOP、CAUTIONED |
| **v20**（GC v7.0.0，RoboCup 2026 起） | HSL 正式比赛 | 见 9.1 |

- Booster 官方 `robocup_demo` 分支 `sandbox/support_2026_game_controller`（2026-06-26 提交 "compatible with HSL game_controller v7.0"）同时定义 V19/V20 常量，并含 5v5、哨声检测支持（README 称点球策略尚未实现）。
- 建议：解析器按 `version` 字段分派，v19/v20 各自映射罚则枚举到内部统一枚举；未知版本直接丢弃并告警。

### 9.5 GC HL→HSL 迁移表摘要（S5）
`kickOffTeam`→`kickingTeam`（`DROPBALL`→`KICKING_TEAM_NONE`）；`secondaryState` 拆为 `gamePhase` + `setPlay`；`secsRemaining/secondaryTime` 改 `int16`；删除 `dropInTeam/dropInTime/coach*`；`MAX_NUM_PLAYERS` 11→20；新增 `competitionType`、`stopped`、`goalkeeperColour`、`goalkeeper`、`messageBudget`；`yellowCardCount`→`cautions`，红牌＝`penalty==PENALTY_SENT_OFF`，`goalKeeper` 标志移到 `TeamInfo::goalkeeper`；返回包删除 `message`（机器人不能再自行改变状态），新增 `fallen/pose/ballAge/ball`。

---

## 10. 技术挑战与体能测试

### 10.1 HSL 2026【S3】
- **Technical Challenges**：仅 **Open Research Challenge**（10 min 报告，队长 Condorcet 投票；须在 2026-10-15 前完整开源代码）。2026 冠军：Ruhrbot Devils（S11）。
- **Fitness Tests（2026 试行，不计分，但须按时到场）**：在 Small 场地进行，每项最多 3 次取最好：
  | 项目 | 内容 | 计分 |
  |------|------|------|
  | Fastest Walk | 从一侧球门线后 50 cm 起，直线自主走到对侧球门线 | 用时（≤ 1 min；跌倒 20 s 未起结束，记距离） |
  | Kick Accuracy | 球在球门区边中点，机器人在门线中点；分别踢向中点、对侧左角、右角，单键启动，60 s | 球停点到目标距离 |
  | Recovery from Fall | 俯卧、仰卧各一次，单键启动 | 至双脚站立并稳定 3 s 的用时 |
- 旧 HL 2025 技术挑战（Push recovery、High kick、Parkour、Goal kick from moving ball 等）在 HSL 2026 **未保留**。

### 10.2 RoboCup 中国赛 2026 类人组技术挑战【S14】
Small/Middle/Large 各自独立排名，5 项：抗推恢复（1–10 kg 沙袋摆锤前/后/侧）、动态踢运动球（角落传出、罚球点附近一次触球射门）、跑酷（平台 ≥ 身高 1/5，站 5 s 后下台，跳下为完全成功）、高踢球（罚球点，宣布目标高度，最低为球径 2/3）、障碍物导航（5 个随机障碍，不得碰撞）。

---

## 11. 赛事组织规则（RoboCup 国际赛）【S1 competition_rules】

| 项目 | 规定 |
|------|------|
| 赛制 | 2026 各组先 Swiss 轮（Small 5 轮/18 队，Middle 5 轮/16 队，Large 4 轮/22 队）+ play-in + 淘汰赛；低名次队进 Consolation Cup（S11） |
| 检录 | 每种平台/配置带一台；预批准平台（含 K1）免测量但需确认未改装、演示急停 |
| 裁判义务 | 每队至少出 1 名熟悉规则者担任裁判；缺席记"qualification penalty" |
| 代码开源 | 强烈鼓励；须于 **2026-10-15** 前在邮件列表公布（未公布记 qualification penalty），"will become a requirement in the following years" |
| 弃权 | 赛前 < 2 h 弃权或缺席 → 对手对空场比赛 |
| 申诉 | 赛后 30 min 内向 TC 提出；赛前 1 h 可检查对手机器人 |
| 场上人员 | 仅裁判与每队 1–2 名 handler；技术区仅队长 + 至多 2 人；GC contact 坐在 GC 操作员旁 |

---

## 12. 国内赛事与 Booster 生态赛事

### 12.1 RoboCup 中国赛（中国机器人大赛暨 RoboCup 机器人世界杯中国赛）

| 年份 / 赛区 | 时间地点 | 与 Booster 相关组别 | 要点 |
|------------|---------|-------------------|------|
| 2025 | 2025-10-17～19，石家庄国际会展中心【报道】 | "3V3 AI 足球—加速进化平台组"（Booster T1 标准平台，首个标准平台赛项）【报道，原新闻页已 404】 | 规则细节【待核实】 |
| **2026（RoboCup 赛区）** | **2026-05-02～04，北京首都国际会议中心**（S16） | **类人组按 HSL 分 Small / Middle / Large 三组分别排名**（K1 → Middle） | 见下表 |
| 2026 标准平台组 | 同上 | 仍为 **NAO v6**，沿用 2025 规则（非 Booster） | 每队 ≤ 5 人，10.4 × 7.4 m 草坪 |
| 2026 仿真 3D 组 | 同上 | 改用 MuJoCo + rcsservermj，标准模型换为 **Booster T1**，每队 7 人 | 与实体 K1 无直接关系 |

**中国赛 2026 类人组 vs HSL 2026 差异**（S14）：

| 项目 | 中国赛 2026 类人组 | HSL 2026 |
|------|-------------------|----------|
| 分组 | Small ≤ 110 cm & ≤ 15 kg；Middle ≤ 125 cm & ≤ 25 kg；Large ≤ 190 cm & ≤ 80 kg | 同 |
| 场地 | **Small 与 Middle 共用 9 × 6 m**（草皮 11 × 8 m，草高 0.8–1.2 cm，四周 1 m 高围栏）；Large 14 × 9 m | Middle 可 S 或 M-Field |
| 球门宽 | Small&Middle 1.9 m，Large 2.6 m；深 1 m | Middle 2.4–2.6 m |
| 禁区 | 小禁区 1 × 3 m（L：1 × 5 m）；大禁区 2 × 4 m（L：3 × 6 m）；罚球点 1.5 m；中圈直径 1.5 m（L：3.0 m） | 见 §3 |
| 每队人数 | **规则 PDF 未写明【待核实】** | 3 / 5 |
| 时长 | 上下半场各 10 min；小组赛平局即平；淘汰赛 2 × 5 min 加时后点球 | 同 |
| 电池 | 容量 < 15000 mAh | 无 |
| 通信 | WiFi 局域网 UDP；每场地一台主机 + 路由器 | GC + 预算 |
| 传感器 | 类人传感器；主动光相机不鼓励、明年可能禁止 | 同方向 |
| 安全 | 机身醒目位置急停按钮；每队每场最多 1 人进场，违规进场直接判负 | 1–2 handler |
| 排名 | 小组单循环（3/1/0 分）→ 淘汰赛决 1–4 名，5 名后点球大战排位 | Swiss + 淘汰 |
| 资格 | 技术报告 ≥ 800 字、单机进球演示视频、往届获奖证明；每队 ≤ 16 名学生、≤ 3 名指导教师 | TDP + 视频等 |
| GameController 版本 | **未说明【待核实】**（建议同时兼容 v19/v20） | v20 |

### 12.2 Booster 相关赛事

| 赛事 | 形式 | 要点 | 来源 |
|------|------|------|------|
| **Booster Champion 仿真赛第一季 · 3v3 足球锦标赛**（"冠军之夜"） | 仿真，Booster Studio 虚拟机器人，3v3 | 2026-07 启动；Agent 基于 `booster_agent_framework`；裁判状态经 ROS2 `/soccer/game_controller`（`std_msgs/String`，GC **v19** 语义 JSON，含 `stopped`、`setPlay`、`kickingTeam`、`messageBudget`、`warnings`）；默认 M-Field 14 × 9 m；本队坐标系 +x 为进攻方向；>2 s 无 GC 消息须停止。具体赛程、奖金、机型【待核实】 | S18、本地 `refs/booster_champion_example` |
| **RoBoLeague 机器人足球联赛（"机超"）** | 实体 | 2025-06-28 北京亦庄首届 3v3 AI 赛，Booster T1 统一平台，全程无 handler 干预、优化判罚，清华火神 5:3 中国农大山海夺冠。2026 全国系列赛：华中（5-30 武汉）、华北（7 月北京亦庄）等大区预赛 + 年底北京总决赛；组别"人形全自主 3V3 U19 组""人形全自主 5V5 自由竞技组（**身高 ≥ 1 m**）"；上下半场各 15 min、中场 5 min、无越位、允许合理冲撞、5 min 金球加时后点球 | S20【报道】 |
| RoboCup 2026（仁川） | 实体 HSL | Booster 提供 K1/T1 借用池：带 2 台 K1 的队可再借最多 3 台（池 12 台）；带 1 台 T1 可借最多 2 台（池 8 台）；59 支人形队中 38 队用 Booster；Small 冠军 Invic（K1 Air【报道】）、Middle 冠军 B-Human（K1）、Large 冠军清华火神（T1） | S10、S11、【报道】 |

> 注意：RoBoLeague 5v5 组要求身高 ≥ 1 m，K1（0.95 m）是否可参赛【待核实】。

---

## 13. 规则 → 软件开发检查清单（K1 / HSL 2026）

### 13.1 GameController 与网络
- [ ] 监听 UDP **3838** 广播；校验 header `"RGme"`、`version`（v20 为正式，兼容 v19），长度 158（v20）；丢弃其它长度/版本。
- [ ] 按 `teamNumber` 查找本队（不要用 `teams[0]`）；`players[jersey-1]` 取本机罚则。
- [ ] 以 0.5–2 Hz（建议 1–2 Hz）**单播**返回包到最近一个控制包的源 IP:**3939**；`fallen` 只填 0/1；pose 单位 mm、以本队进攻方向为 +x；ballAge 未见球填 -1；禁止 NaN。
- [ ] GC 包超时（建议 > 2 s）→ 安全停止或保持最后安全状态，并告警。
- [ ] 队号、球衣号、IP 段、SSID 从配置读取，**不要硬编码**；团队端口 = 10000 + teamNumber。
- [ ] 旧 `refs/robocup_demo` main 分支是 HL v12 解析器 → 正式比赛须改用 v20（参考 Booster `sandbox/support_2026_game_controller` 分支或自写）。
- [ ] 关闭罗盘/磁力计融合；比赛中不使用蓝牙手柄/遥控（急停除外，且需放在技术区标记处）。

### 13.2 状态行为
- [ ] **INITIAL**：不迈腿；可转头、标定、自检；可做初始定位（handler 摆放位置在本方半场，规则未给精确坐标【待核实】）。
- [ ] **READY**（≤ 45 s）：自主走位到合法开球位（见 13.3），尽量在 30–35 s 内到位，防碰撞，别出界；到时不合法 → Illegal Positioning。
- [ ] **SET**：立即停止腿部运动（允许头/手臂、跌倒起身）；进入 SET 前把步态平稳收脚，避免"惯性步"被判 Motion in Set。
- [ ] **SET→PLAYING 哨声检测**：对 kick-off / dropped ball / penalty kick 开启；GC 延迟 10 s；哨声检测需**抗邻场哨声**（结合 GC 状态、方位/音量阈值），误触发代价＝原地 15 s。
- [ ] 无哨声检测时：以 GC `state==PLAYING` 为准（晚 10 s，开球优势基本丧失）。
- [ ] **`stopped==1`**：尽快安全停下，**连起身都不做**，直到 `stopped==0`；GC 在 stop 时 5 Hz 发包，响应延迟应 < 0.5 s。
- [ ] **FINISHED**：停止；半场后可能换边，定位需依赖 `firstHalf`/GC 与重新摆放。
- [ ] Timeout（`gamePhase==TIMEOUT`）按 INITIAL 处理。

### 13.3 开球/定位球站位
- [ ] Kick-off 我方：全员本方半场；最多 1 台进中圈（可跨中线，但必须在中圈内），该台必须是开球者；**不能直接射门**，≥ 3 台时需传给第二台再射。
- [ ] Kick-off 对方：全员本方半场且**中圈外**；球 in play（被踢且明显移动或哨后 10 s）前不得进入中圈。
- [ ] Dropped ball（`kickingTeam==255`）：双方都不得进中圈，哨后立即可抢、可直接射门。
- [ ] 任意球（`setPlay!=NONE` 且 `state==PLAYING`）：若 `kickingTeam!=本队` → 立即撤出球周围中圈半径（S-Field 0.75 m / M-Field 1.5 m）；Goal kick 对方须离开整个罚球区；允许站在本方门线门柱之间；`secondaryTime` 内（45 s）不得进入。
- [ ] 我方任意球：45 s 内完成；间接（THROW_IN / INDIRECT）不能直接射门、同一机器人不能连续两次触球（≥ 3 台时）。
- [ ] 本方球门区同时 ≤ **3** 台（5v5 防守时重要）。
- [ ] 点球（`setPlay==PENALTY_KICK`）：防守门将 READY 中走到门线上（双脚在线），PLAYING 中射手触球前**不能扑倒/离线**；进攻方仅 1 台进罚球区、不挡罚球点；其余在罚球点后且离罚球点 ≥ 中圈半径。射手只能触球一次。
- [ ] 点球大战：`gamePhase==PENALTY_SHOOT_OUT`；`penalty==SUBSTITUTE` 的机器人保持静止；射手被摆在罚球区边缘面向球门，SET 中不得移动。

### 13.4 罚下与重新入场
- [ ] `penalty!=NONE` 时：除站起/坐下外**不得任何移动**；区分 **MOTION_IN_SET（原地，不离场）** 与其它（被抱出场）。
- [ ] 只用 `penalty==PENALTY_NONE` 判断解除（`secsTillUnpenalised` 在计时开始前为 0）。
- [ ] 解除后定位先验：**本方半场、罚球点高度、边线外、面向对侧边线**（左右边线两个假设都要考虑；被占用时附近但仍在本方半场）。S-Field 本方罚球点 x = −3.0 m；M-Field x = −5.0 m；y ≈ ±（半场宽 + 若干 cm）。
- [ ] 入场路径：从边线外走入场内，"合理努力返回场内"时不判 Illegal Position；避免直线冲向球造成 pushing。
- [ ] 替补/timeout 后入场同样从标准 re-entry 点。

### 13.5 比赛中行为约束
- [ ] 跌倒检测 → **20 s 内开始起身**，最多 3 次；每次失败要有退避策略；返回包 `fallen=1`。
- [ ] 不活动 ≤ 10 s：没球时也要持续找球/转头/走动，避免 Incapable。
- [ ] 站姿宽度 ≤ 约 1.5 倍肩宽（守门员下蹲姿态也不能长时间过宽）。
- [ ] Ball holding：场上 < 5 s（建议 < 3 s 即踢/带离）；守门员在本方罚球区 < 10 s；不要"放-控"反复。
- [ ] 不要走出铺草区域（场线外 ≥ 1 m 缓冲）；撞门柱/网 ≤ 5 s；手臂远离球网。
- [ ] 非守门员不主动用手臂触球；守门员出罚球区后禁止用手。
- [ ] Pushing：接近对手时减速；接触 > 5 s 即犯规；踢球动作开始时球须在可踢范围内（静止踢球者不算推人）。
- [ ] Local game stuck：球 10 s 未动且多人围抢 → 离球最近者被罚；策略上避免长时间顶牛（换角度/后撤）。
- [ ] Global game stuck：30 s 无人靠近球 1 m → dropped ball；找球策略需覆盖全场。

### 13.6 队内通信
- [ ] 广播到 10000+teamNumber，payload ≤ 512 B（留余量，含序列化头）。
- [ ] 依据 `messageBudget` 与剩余比赛时间动态限速；预留补时/加时额度；耗尽前进入"静默/仅关键事件"模式。
- [ ] READY/SET/PLAYING 才计数；INITIAL/FINISHED/点球大战可自由发（但点球大战非上场机器人不得在网上）。
- [ ] 通信丢失时单机也能独立决策（不依赖队友消息）。
- [ ] Debug 数据仅发给本队有线设备，≤ 1 包/s/台。

### 13.7 硬件/安全/检录
- [ ] K1 保持未改装（否则失去预批准，需测量）；球衣覆盖 ≥ 50% 上身，号码 1–20，前后可见；守门员可区分。
- [ ] 急停流程可随时演示；handler 急停只在裁判命令或危险时使用。
- [ ] 电池：K1 2Ah 版续航官方文档写 20 min（@1.1 m/s，S21），Booster RoboCup 页写 40 min（S17），均偏紧；5Ah 版约 70–80 min。**建议比赛用 5Ah 版或每半场换电**，半场休息 10 min 内完成换电/换机。
- [ ] Advanced（5v5）需 5 台可用 K1 + 替补（Middle 1/4 决赛起强制 5v5）。

---

## 14. 存疑与待核实清单

| # | 问题 | 现状 |
|---|------|------|
| 1 | RoboCup 2026 仁川 Middle 组实际用 S-Field（9×6）还是 M-Field（14×9）、size 3 还是 size 4 球 | 规则允许两者，官方页面未写明【待核实】 |
| 2 | 点球 READY 时长 30 s（规则正文）vs 45 s（GC 参数、规则变量） | 以 GC 行为为准，规则存在不一致（GitHub issue 未见修正） |
| 3 | 2027 HSL 规则 / 草案 | 截至 2026-09-24 未发布 |
| 4 | "K1 Air" 规格（是否 ≤ 15 kg） | 仅新闻报道 |
| 5 | K1 深度相机为被动双目还是主动红外 | 影响"discouraged"分类；K1 为预批准平台，当前不影响参赛 |
| 6 | 中国赛 2026 类人组每队人数、GC 版本 | 规则 PDF 未写 |
| 7 | 2025 中国赛 "3V3 AI 足球—加速进化平台组" 规则细节 | 仅新闻（原页已 404） |
| 8 | Booster Champion 仿真赛赛程、奖金、机型 | 官网为 SPA，未能抓取正文 |
| 9 | INITIAL 阶段标准摆放位置 | HSL 规则未给出精确坐标（"placed in their starting positions by robot handlers"） |
| 10 | 罚下机器人放在哪一侧边线 | 规则只说"the touchline at the height of the penalty mark of its own half"，未指明左右 |
| 11 | GC 开源仓库 HEAD（2026-09-03）mercy rule 已改为可选 | 后续赛事（如 German Open 2027）参数可能变化 |
