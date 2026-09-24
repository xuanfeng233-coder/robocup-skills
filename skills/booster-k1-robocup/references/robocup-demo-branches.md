# robocup_demo 非 main 分支解析与 K1 参赛基线选择

> ⚠ **本队栈（2026-09-24 起）是主办方的 `K1_5v5_demo_1.7` + HSL GameController 7.0.0-rc.3（v20）。** `K1_5v5_demo_1.7` **不属于本文分析的 main / gc2026 / autocal / v1604 这条线**，而是 `3v3`（`sandbox/feat/k1_3v3_demo`）→ Booster 内部仓 → `T2` 那条线的后续版本（`fw1.7-demo-v1.7.md` §3.1），而且已经自带 v12/v20 双协议解析。所以**不要再按 §0、§4 选基线或 cherry-pick**；本文只用于：① 查某个修复或功能在公开分支里的来龙去脉；② 从 `gc2026`（哨声检测）等分支挑想法手工移植到 Demo 1.7。行号对 Demo 1.7 不成立。

> 分析对象：`refs/robocup_demo` 完整克隆，已 fetch 全部 `origin/*` 分支。分析日期 2026-09-24，此时 main HEAD 为 `fa4f31c`（2026-06-26）。
> main 分支的架构、话题、参数见 `robocup-demo.md`。本文只写各分支**相对 main 的差异**。
> 引用格式：`<分支简称>:<路径>:<行号>`，或 commit hash。行号取分支 tip 版本。「待验证」表示仅凭代码无法确认。
> 分支简称：
> - `gc2026` = `sandbox/support_2026_game_controller`
> - `autocal` = `sandbox/support_app_auto_calibration`
> - `v1604` = `sandbox/support_k1_v1.6.0.4+`
> - `3v3` = `sandbox/feat/k1_3v3_demo`
> - `sim` = `sandbox/support_sim`
> - `T2` = `sandbox/support_T2`

---

## 0. 结论速览

- **推荐 K1 2026+ 参赛基线：`autocal`（tip `7b4ed35`，2026-09-16）。**
  - 它包含 `gc2026` 的全部代码提交（`ec0d4da`→`2f49a40`→`5ba299e`→`aac541d`），只缺 `gc2026` 末尾两个 README 提交（`2819b13`、`45b0e16`）。
  - 在此之上，它又加了 App 自动标定适配（`ac022f0`）和 show_det 显示坐标（`7b4ed35`）。
  - 相对 main 只落后 2 个提交（`2e30645`、`fa4f31c`），两者都只改 README。
- **需要叠加的提交**：cherry-pick `7d5be7b`（模拟合并无冲突）。可选：手工移植 `1e1acac` 里的 locator 阈值。
- **不要**整体合并 `v1604`：会产生冲突，还会重复定义 `RobocupWalk`，导致编译失败（§4）。
- **不要**合并 `3v3`、`sim`、`T2`：`3v3` 模拟合并有 523 处冲突；`sim` 和 `T2` 与 main 没有共同祖先。
- **上场前必须修改的硬编码**（`gc2026`/`autocal` 都有）：
  - GC 白名单 `192.168.30.170`；
  - `team_id: 66`；
  - `game_control_ip: 192.168.30.170`；
  - 仓库自带的 `vision.yaml` 是某台机器的自动标定结果，不能直接用在你的机器上。

## 1. 分支总览

ahead/behind 用 `git rev-list --left-right --count origin/main...<branch>` 计算：behind 指 main 有而该分支没有的提交数，ahead 指该分支独有的提交数。

| 分支 | 最后提交 | merge-base（与 main） | behind / ahead | 一句话用途 | 适用 K1？ |
|---|---|---|---|---|---|
| `sandbox/support_2026_game_controller` | 2026-09-09 `45b0e16` | `74d611f`（2026-03-10） | 2 / 6 | 新 GC 协议 v19/v20；规则合规的队内广播；哨声检测；任意球阶段机 / 二次触球 / 防守站位；VisualKick kV1/kV2 | 是（README：T1 与 K1） |
| `sandbox/support_app_auto_calibration` | 2026-09-16 `7b4ed35` | `74d611f` | 2 / 6（其中 4 个与 gc2026 相同） | gc2026 全部代码 + 读取 App 自动标定结果（URDF 适配 head_pose） | 是（K1/T1；自动标定依赖固件工具，待验证） |
| `sandbox/support_T2` | 2026-09-04 `2d56d36` | **无共同祖先**（单个 orphan 提交） | — / 1 | T2 专用整仓快照：GC v20、rerun、SDK 兼容测试 | 否（gc2026 README 称其为 T2 分支） |
| `sandbox/support_k1_v1.6.0.4+` | 2026-04-21 `7d5be7b` | `74d611f` | 2 / 2 | 适配 K1 固件 ≥ v1.6.0.4 的 VisualKick 接口；kSoccer 模式；相机统一话题 | 是，但仍是旧 GC（提交信息称 "version 25 of gamecontroller"，推测为 2025 版 HL v12，待验证） |
| `sandbox/feat/k1_3v3_demo` | 2025-12-24 `d2e326e` | `b1e27ca`（2025-09-23） | 9 / 5 | 2025 年 K1 3v3 官方 demo 快照：HL v12、单播通信、语音、rerun | 已过时，由 main `dbcbc34` 取代（推断） |
| `sandbox/support_sim` | 2025-12-09 `7965dbe` | **无共同祖先**（22 提交，根 `ee1e49b` 2024-11-15） | — / 22 | 老一代 brain + 仿真 `sim_detection_bridge` | 仅作仿真参考，不能合并 |
| `jetpack6.2` | 2025-05-28 `2e86981` | `3868952` | 17 / 1 | JetPack 6.2 编译、ZED 话题 | 已被 main `642faf9` 取代（推断） |
| `sandbox/support-jetpack6.2` | 2025-07-08 `8a59a52` | `beb156f` | 12 / 4 | JetPack 6.0/6.2 支持 | 已合入：tree 与 main `642faf9` 完全相同（`git diff` 为空） |
| `sandbox/add_kick_demo` | 2025-06-19 `9bdbe8f` | `9bdbe8f` | 14 / 0 | 不稳定的踢球动作 demo | 已合入 main，随后被 `aa0d742` revert |
| `sandbox/support_auto_standup` | 2025-05-23 `b681724` | `b681724` | 18 / 0 | 摔倒自起 | 已合入（PR #3，`3868952`） |
| `sandbox/support_sim_vision_model` | 2025-04-30 `0579259` | `0579259` | 20 / 0 | 仿真视觉配置 | 已合入（PR #2，`cd42d99`） |
| `sim_stable` | 2025-04-30 `0579259` | `0579259` | 20 / 0 | 与上一行指向同一提交 | 已合入 |

提交谱系：

```
main:  … b1e27ca ─ … ─ dbcbc34 ─ 6b15ee2 ─ ecb6be9 ─ 74d611f ─ 2e30645 ─ fa4f31c (main, 仅 README)
         │                                              ├─ ec0d4da ─ 2f49a40 ─ 5ba299e ─ aac541d ─┬─ 2819b13 ─ 45b0e16   (gc2026)
         │                                              │                                          └─ ac022f0 ─ 7b4ed35   (autocal)
         │                                              └─ 1e1acac ─ 7d5be7b                                              (v1604)
         └─ 2c7f4f2 ─ 622f74d ─ 96ed289 ─ 950ff5a ─ d2e326e                                                              (3v3)
orphan:  ee1e49b … 7e22de5 ─ a5d37b2 ─ 42d4cc5 ─ fec77e8 ─ 7965dbe (sim)      2d56d36 (T2)
```

---

## 2. 重点分支深入解析

### 2.1 `gc2026`：新 GameController、哨声、2026 规则适配

**提交**（均基于 `74d611f`）：

| commit | 日期 | 内容 |
|---|---|---|
| `ec0d4da` | 2026-04-16 | 提交信息称基于 v1.5.2 固件，兼容 2026 版 GC。改动：GC 协议 v19；brain 状态映射；本地任意球阶段机；规则合规的队内广播；GC 白名单 |
| `2f49a40` | 2026-06-22 | 提交信息"WIP: freekick双触迁移 + kV1/kV2（同步前快照）"。新增 `src/whistle_detection` 包；brain 接入哨声；任意球防守大改（`brain_tree.cpp` +2890 行）；VisualKick 版本可配；`RobocupWalk` |
| `5ba299e` | 2026-06-22 | 任意球站位时 `setVelocity` 可跳过最小速度抬升；`team_comm_frequency_hz` 改为 1.0 |
| `aac541d` | 2026-06-26 | 提交信息"compatible with HSL game_controller v7.0"。GC 节点同时解析 v19 和 v20 |
| `2819b13`、`45b0e16` | 2026-09-09 | 仅 README：增加一行，指明 T2 分支 |

**新增/修改的包与关键文件**：
- 新包：`src/whistle_detection/`，含 `src/*.cpp|h`，以及 `third_party/lib/libduerwen_wakeup_DOA*.so`（这两个是真实二进制，不是 LFS 指针）。
- `src/game_controller/include/RoboCupGameControlData.h`：重写。
- `src/game_controller/src/game_controller_node.cpp`、`launch/launch.py`。
- `src/interface/game_controller_interface/msg/{GameControlData,TeamInfo,RobotInfo}.msg`。
- `src/brain/{src/brain.cpp,src/brain_communication.cpp,src/brain_tree.cpp,src/robot_client.cpp,src/main.cpp,config/config.yaml,behavior_trees/game.xml}`。
- `scripts/{start,stop,build}.sh`、`src/vision/config/vision.yaml`（相机话题改为 `/boostercamera/head/*`）。

#### 2.1.1 新协议对比（main HL v12 → gc2026 v19/v20）

| 项 | main | gc2026 |
|---|---|---|
| header 校验 | 不校验 | 必须是 `"RGme"`，且包长 ≥ 5（`gc2026:src/game_controller/src/game_controller_node.cpp:21`） |
| 版本 | `version == 12` | 读 `buffer[4]`：等于 19 按 V19 解析，等于 20 按 V20 解析，其它值丢弃（`:171, :184`） |
| 包长 | `sizeof(HlRoboCupGameControlData)` | V19 = 198 B，V20 = 158 B（`static_assert`，`:13-16`），必须严格相等 |
| 端口 | 3838 收 / 3939 回 | 相同（`RoboCupGameControlData.h`：`GAMECONTROLLER_DATA_PORT` / `RETURN_PORT`） |
| ROS 话题 | `/booster_soccer/game_controller` | **`/robocup/game_controller`**（gc 节点 `:87`；brain `src/brain/src/main.cpp:43`） |
| IP 白名单 | 默认关闭 | **默认开启**，只接受 `192.168.30.170`（`launch.py:21, 25`） |
| 回包（brain 发出） | `RGrt` v2，message=2（ALIVE），1Hz | `RGrt` **v4**，结构为 `{playerNum, teamNum, fallen, pose[3], ballAge, ball[2]}`（32 B），**2Hz**。`fallen` 固定为 0，pose/ball 固定为 0，ballAge = -1（`brain_communication.cpp:83-98`） |

V19 与 V20 的结构差异（`gc2026:src/game_controller/include/RoboCupGameControlData.h`）：
- 公共头部：`header[4], version, packetNumber, playersPerTeam, competitionType, stopped, gamePhase, state, setPlay, firstHalf, kickingTeam`（都是 uint8），以及 `secsRemaining, secondaryTime`（int16）。
- `TeamInfo`：`teamNumber, fieldPlayerColour, goalkeeperColour, goalkeeper, score, penaltyShot`（uint8），`singleShots, messageBudget`（uint16），`players[20]`。
- `RobotInfo`：V19 为 `{penalty, secsTillUnpenalised, warnings, cautions}`；V20 去掉了 `warnings`，只剩 3 字节。
- 罚则枚举：V20 在 3 号插入了 `MOTION_IN_STOP`，在 11 号插入了 `CAUTIONED`，后面的值依次后移。`normalize_v20_penalty`（`game_controller_node.cpp:27`）把 V20 值归一化成 V19 语义：
  - `MOTION_IN_STOP` → `MOTION_IN_SET`（`:37`）；
  - **`CAUTIONED` → `PUSHING`**（`:53`）。这意味着 brain 会把被警告的机器人当作被罚下，是否符合规则待验证。

ROS msg 字段变化（`src/interface/game_controller_interface/msg/`）：

| msg | 删除 | 新增 / 改动 |
|---|---|---|
| `GameControlData` | `game_type`、`kick_off_team`、`secondary_state`、`secondary_state_info[4]`、`drop_in_team`、`drop_in_time` | `version` 从 uint16 改为 uint8；新增 `competition_type`、`stopped`、`game_phase`、`set_play`、`kicking_team`；`secs_remaining`/`secondary_time` 改为 int16 |
| `TeamInfo` | `coach_sequence`、`coach_message[]`、`coach` | 新增 `goalkeeper_colour`、`goalkeeper`、`message_budget`；`players` 改为定长 `RobotInfo[20]` |
| `RobotInfo` | `number_of_warnings`、`yellow_card_count`、`red_card_count`、`goal_keeper` | `warnings`、`cautions`。V20 的包 `warnings` 恒为 0 |

**解析要点**：
- 接收缓冲 512 B，先校验 header，再按版本分发。
- 流程是先 `memcpy` 到 packed 结构体，逐字段复制到 msg，**然后才做白名单过滤**，通过后发布。
- 每个包都会打一条 INFO 日志。

#### 2.1.2 brain 侧映射（`gc2026:src/brain/src/brain.cpp:1811` `gameControlCallback`）

| GC 字段 | brain 黑板 / 数据 |
|---|---|
| `state` 0..4 | `gc_game_state` ∈ {INITIAL, READY, SET, PLAY, END}。仍然没有越界检查 |
| `kicking_team == team_id` | `gc_is_kickoff_side` |
| `set_play` | 0 → `NONE`；1 → `DIRECT_FREEKICK`（`isDirectShoot`）；2 → `INDIRECT_FREEKICK`；3 → `PENALTY_KICK`（直接射门）；4 → `THROW_IN`；5 → `GOAL_KICK`（直接射门）；6 → `CORNER_KICK`；其它 → NONE。1..6 都映射为 `gc_game_sub_state_type = FREE_KICK`，细分类型写入新键 `gc_real_game_sub_state` |
| `stopped` | 仅当类型为 FREE_KICK 时使用：`stopped != 0` → `gc_game_sub_state = STOP`，否则为 `GET_READY`（`:1929`）。v19 不再有 SET 子阶段 |
| FREE_KICK 且 `kicking_team == team_id` | `gc_is_sub_state_kickoff_side` |
| `players[i].penalty` | `penalty[i]`，`SENT_OFF` 视为 `SUBSTITUTE`（`:1994`）。`playerId > 0` 时才判断 `gc_is_under_penalty` |
| `game_phase` | **未使用**。TIMEOUT 分支写成 `case -1`（`:1883`），而 `set_play` 是 uint8，所以永远走不到。`game.xml:38` 的 TIMEOUT 子树因此是死代码。点球大战 / 加时同样没有处理（README：点球策略未实现） |

另外两处行为变化：
- 删除了 main 中「agent 模式忽略 GC」的判断（main `brain.cpp:1100`）。在 gc2026 上，agent 模式下 GC 包仍然生效。
- 不再写 `secsRemaining`。

#### 2.1.3 队内通信（`gc2026:src/brain/src/brain_communication.cpp`）

- **取消 discovery 和单播**：改为向 `255.255.255.255:(10000+team_id)` 广播（`:24, :125`），收发同端口，按 `teamId` 过滤，并丢弃自己的包。
- 广播频率 = `team_comm_frequency_hz`：代码声明默认 2.0，yaml 设为 **1.0**（`config.yaml:109`），见 `:139`。只统计 READY/SET/PLAY 状态下的发包数量；**不读取 GC 的 `message_budget`**。
- 报文仍是原始 C struct `TeamCommunicationMsg`（`team_communication_msg.h`），新增 `isInVisualKick`。有 `static_assert(sizeof <= 512)`。按字段推算约 128 B，待编译确认。

#### 2.1.4 whistle_detection（`gc2026:src/whistle_detection/`）

- **数据链路**（`src/main.cpp`）：
  1. ALSA 设备 `hw:1,0`（硬编码），6 通道，16 kHz，S16，每帧 1024 样本。
  2. 取 ch0-2 作为麦克风、ch4 作为参考信号，送入 Duerwen DSP（`Duerwen_wakeup_three_write_data`）做 AEC，得到 3 通道输出。
  3. 3 通道送入 `WhistleDetector::processFrame`。
  4. 检测到哨声时向 **`/whistle_detected`**（`std_msgs/String`，内容 `"whistle_detected"`）发布一次，然后 `reset()`。
  - 可执行文件名 `whistle`，由 `start.sh` 用 `ros2 run whistle_detection whistle` 启动。
  - `-r out.wav` 参数可以录下 3 通道音频。
- **算法**（`src/whistle_detection.cpp`）：
  - 只用 AEC 后的 ch0，每 160 样本（10 ms）做一次 FFTW r2c，得到 81 个 bin，分辨率 100 Hz。
  - 幅值取 `|Re|`，**不是模长**。
  - 每 10 个 bin 相加为 1 个特征，即每个频段 1 kHz，共 8 段；只有前 6 段（0–6 kHz）参与打分。
  - 特征先做 60 帧（0.6 s）滑动累加。噪声基线是最近 1000 帧（10 s）的平均能量。
  - 打分：`score = sigmoid(0.605 + Σ coef_i · acc_i / (noise_avg·10))`，其中 `coef = [-19.17, -19.17, +16.82, +15.64, +1.14, -19.17]`。也就是说，2–4 kHz 能量相对噪声显著升高、0–2 kHz 和 5–6 kHz 不高时，判为哨声。
  - 阈值 `> 0.5`。每块都会 `printf` 一次分数，约 100 行/s，日志会迅速变大。
- **限制**：
  - 启动后需要 10 s 噪声标定才开始检测。
  - **每次检测到哨声后都会 `reset()` 并重新标定 10 s**，这期间检测不到第二声哨。
  - 每个 1024 样本的帧只处理 6 个 160 样本块，末尾 64 样本被丢弃。
- **依赖**：`libasound2-dev`、`libfftw3-dev`（需要 `fftw3f`）。aarch64 链接 `libduerwen_wakeup_DOA_v1.1.0_20251113.so`，x86_64 链接 `libduerwen_wakeup_DOA.so`（`CMakeLists.txt`）。K1 各硬件版本的麦克风阵列和声卡编号是否一致，待验证。
- **接入 brain**（均在 `brain.cpp`）：
  - 订阅 `/whistle_detected`（`:242`）。话题**不带** robot_name 后缀。
  - `whistleDetectionCallback`（`:1748`）：
    - 当 `gc_game_state == SET` 且我方开球：立即把本地状态设为 `PLAY`，置 `whistleTriggeredPlay`。之后 12 s 内，GC 发来的非 PLAY 状态被忽略（`:1857`）。
    - 当 `SET` 且对方开球：保持 SET，置 `opponentKickoffWhistlePending`，交给 `updateKickoffMemory`（`:1010`）做本地放行。放行条件是球移动、球离开中圈或 10 s 超时，放行时通过 `releaseOpponentKickoffWait(switchToPlay=true)`（`:1711`）本地切到 PLAY 并保持 override。
      - 注意：哨声后的「球移动」阈值因子是 100（`:1026`），中圈半径加了 100 m（`:1139`），两个条件实际都被关掉了，只剩 10 s 超时。疑为调试遗留，待验证。
      - 没有哨声时，只要检测到球移动（因子 0.15，连续 3 帧）也会在 SET 期间本地切到 PLAY。有 Motion-in-SET 的风险，待实机验证。
    - 当 `PLAY + FREE_KICK` 且我方开球：代码注释说 v19 不产生 SET 子阶段，所以这条分支实际不会生效。

#### 2.1.5 其它 brain 改动

- **本地任意球阶段机**：`updateLocalFreekickPhase`（`brain.cpp:388`）。
  - 状态顺序：`WAIT_RESUME`（GC 处于 STOP）→ `PLACEMENT`（见过 STOP 之后进入 GET_READY）→ `UNPLACEMENT`（开球方到位误差 ≤0.35 m 并稳定 800 ms，也可配置超时兜底）→ 1 s 后进入 `EXECUTE`。
  - `game.xml:45` 新增 `PlayUnified` 分支：普通 PLAY，或我方任意球处于 `EXECUTE` 时，都执行 StrikerPlay/GoalKeeperPlay。
  - 参数在 `strategy.freekick_phase.*`。
- **二次触球规避**：`updateFreekickKickerTouchCostPenalty`（`:532`）。
  - 我方任意球的主罚者：球距离先 < `close_dist`（yaml 0.40），再 > `release_dist`（0.70），判为已触球。
  - 之后 5 s 内 cost 加 100（在 cost 计算中生效，`:1388`），让队友接管球。
- **防守任意球站位**：`GoToFreekickPosition::onRunning`（`brain_tree.cpp:492`）重写，约 2800 行。
  - 规则避让半径、对方门球时冻结球位、沿避让圆弧移动、快速退圈等。
  - 参数在 `strategy.freekick_defense.*`，共 26 项（`config.yaml:41`）。
- **VisualKick**：
  - `RLVisionKick` 的 body 增加 `"version"`，由 `RLVisionKick.visualKickVersion`（默认 `kV2`，`config.yaml:102`）决定，kV1=0，kV2=1（`robot_client.cpp:50-64`）。
  - `robocupWalk()` 改为发送 `VisualKick(false)`，不再切到 kWalking（`:67`）。
  - 新增 `changeRobocupMode()`：先 `ChangeMode(kSoccer)`，再 `VisualKick(false)`（`:75-79`）。它由 BT 节点 `RobocupWalk`（`brain_tree.cpp:4240`）调用，在 `game.xml:22` 的 control_state==2（LT+A）分支里以 `RunOnce` 执行。`RunOnce` 在整个进程生命周期内是否只执行一次，待验证。
- **踢球力度**（`pubKickMsg`，`:1553`）：
  - 间接任意球、角球、界外球：用 `highPassPower`（2.5）传球；球在对方半场时，目标改为 (ball_x, 0)。
  - 开球：用 `lowPassPower`（1.8）。
  - 其余情况与 main 相同：距离 > 6 m 用 1.5，否则 6.0。
- 其它：
  - `strategy.soft_kickoff`（默认关）：开球时限速。
  - `setVelocity(..., applyMinX/Y/Theta)`：可以跳过最小速度抬升。
  - 相机话题改为 `/boostercamera/head/{rgb,depth,rgb/camera_info}`（`config.yaml`、`vision.yaml`），修正了 main 中 `image_camera_info_topic` 指向图像话题的问题。
  - `build.sh` 去掉了 `--symlink-install`，改 config 后必须重新编译。

#### 2.1.6 风险清单（gc2026）

- 硬编码：
  - `game_controller/launch/launch.py` 开启白名单，只放行 `192.168.30.170`；
  - `config.yaml` 中 `team_id: 66`、`game_control_ip: "192.168.30.170"`。
- `CAUTIONED` 被映射为 `PUSHING`；`game_phase` 没有处理，TIMEOUT 分支不可达。
- brain 自带一份 v19-only 的 `src/brain/include/RoboCupGameControlData.h`（`HL_MAX_NUM_PLAYERS 11`），与 gc 节点的 v19/v20 头文件并存，可能不同步。
- 哨声检测后需要 10 s 重新标定；对方开球 SET 阶段可能被本地放行（见上）。

### 2.2 `autocal`：App 自动标定结果接入（相机外参）

**关系**：`gc2026` 的前 4 个提交，加上 `ac022f0`（2026-09-15）和 `7b4ed35`（2026-09-16）。

**本仓库不做标定计算**，只是消费机器人 App 生成的标定文件。流程如下：

1. **配置入口**：`scripts/start.sh:15` 以 `vision_config_path:=/opt/booster` 启动 vision。
   - vision launch 在该目录下存在 `vision.yaml` 时优先使用，否则回退到包内默认文件。
   - 第三个参数 `~/agents/booster_soccer/vision.yaml` 被删除（`src/vision/launch/launch.py`）。
2. **开关**：`calibration.auto_calibrate: true`（`src/vision/config/vision.yaml:92`）。
3. **初始化**：`InitAutoCalibrationPoseAdapter`（`vision_node.cpp:940`）。
   1. 执行 `booster-cli robot_info`（`:956`），从 JSON 中取 `"Model"`：包含 k1 用 `K1_22dof.urdf`，包含 t1 用 `T1_23dof.urdf`。
   2. 读取 `/opt/booster/perception_info.yaml`（`:975`）判断相机类型；取不到时再看 yaml 的 `camera.type`。
      - realsense → `head_realsense_rgb_link`；
      - boostermipi / d-robotics → `head_booster_stereo_rgb_link`。
      - T1 只支持 realsense。
   3. 从 URDF 中解析该 link 相对 `aahead_pitch_link` 的固定关节。K1 为 `xyz=0.060138 0.0351 0.092774`，`rpy=-π/2 0 -π/2`，即光学系（`src/vision/config/K1_22dof.urdf:1343-1348`）。
4. **位姿适配**：`PoseCallBack`（`:1046`）把 `/head_pose` 替换为 `headpoint2base · headpoint2pitchlink⁻¹ · cameralink2pitchlink`（`:1039`）。
   - `headpoint2pitchlink` 是硬编码的 `(0.0613, 0, 0.108)`（`vision_node.h:79`），K1 和 T1 共用，T1 是否正确待验证。
   - 此时 yaml 中的 `camera.extrin` 只是**残差**，所以示例文件里接近单位阵；`p_headprime2head_` 被清零；`/booster_soccer/cal_param` 被忽略（`:1072`）。
   - 新增 `camera.x_compensation / y_compensation`，直接加到输出坐标上（`:269, :537`）。
5. **brain 联动**：brain 不再订阅 `/head_pose`，改订 vision 发布的 `/booster_soccer/t_head2base`（TransformStamped，`src/brain/src/brain.cpp:242, :2162`）。
   - 因此 **brain 的深度避障依赖 vision 在运行**。
   - brain 的默认深度话题改为 `/boostercamera/head/*`。
6. **容错**：新增 `camera_config.h::GetCameraTopic`，缺少话题时回退到统一话题。修复了 main 中 `save_data:=false` 时的空指针（`data_logger_` 判空）。
7. **`7b4ed35`**：`show_det` 在框下方显示机器人系 `x/y`，方便人工核对标定。`start_vision.sh` 改为从 `/opt/booster` 启动。

**风险**：
- 适配器初始化失败时，`Init` 直接 `return`（`vision_node.cpp:276`），检测器没有创建，**vision 整体不可用**。失败原因包括：没有 `booster-cli`、没有 `perception_info.yaml`、型号不识别、URDF 缺失。
- 仓库自带的 `vision.yaml` 是某台机器 2026-09-14 的自动标定结果，`auto_calibrate: true`，图像尺寸 544×448。**不要直接用于你的机器**。
  - 手动标定的旧格式模板保存在 `src/vision/config/vision_old.yaml`。
  - 使用手动标定时，把 `auto_calibrate` 设为 false，并确认 `/opt/booster/vision.yaml` 存在或已删除。
- `start.sh` 只给 vision 传了 `vision_config_path`，brain 仍读取包内的 `vision.yaml` 来取 `camToHead`，两者可能不一致。建议运行 `./scripts/start.sh vision_config_path:=/opt/booster`：`$@` 会转给 brain launch，brain launch 已支持该参数。
- `/opt/booster/vision.yaml` 由 App 写入。它是否包含 `detection_model` 等完整字段，决定 vision 能否启动，待验证。
- 提交里误带了 `launch/__pycache__/*.pyc`。

### 2.3 `v1604`：K1 固件 v1.6.0.4+ 适配

| 变更 | 位置 | 说明 |
|---|---|---|
| VisualKick 请求带 version | `robot_client.cpp` `RLVisionKick`（`1e1acac`） | body 由 `{"start":b}` 改为 `{"start":b,"version":1}`，固定为 kV2。SDK 的 `VisualKickParameter::FromJson` 直接读取 `json["version"]`（`booster_robotics_sdk/include/booster/robot/b1/b1_loco_api.hpp:1695-1698`），所以缺少这个字段时，新固件很可能解析失败（推断） |
| 退出视觉踢 | `robocupWalk()` | 由 `ChangeMode(kWalking)` 改为 `VisualKick(false)`，解决了 main 文档 §6.2 第 12 条 |
| kSoccer 模式 | 新增 `changeRobocupMode()` 和 BT 节点 `RobocupWalk` | 在 `game.xml` 的 control_state==2 分支中执行 `<RunOnce><RobocupWalk/></RunOnce>`。`RobotMode::kSoccer = 4`（SDK `robot_shared.hpp:13`） |
| 相机统一话题 | `vision.yaml`、`config.yaml` | 改为 `/boostercamera/head/rgb|depth|rgb/camera_info`；`7d5be7b` 修正了 `image_camera_info_topic` |
| 定位阈值 | `config.yaml` | `locator.min_marker_count` 5 → 3，`max_residual` 0.35 → 0.5 |
| 头部 pitch 下限 | `brain_config.cpp`（`7d5be7b`） | getter 默认值 0.45 → 0.2 rad。`robot.head_pitch_limit_up` 没有声明，实际取的就是这个默认值，所以 CamFindBall 的 0.2 和 READY 的 0.35 不再被截断 |

提交信息说明该分支**只适配 2025 版 GameController**。除「定位阈值」和「头部 pitch 下限」两项外，其余功能都已被 `gc2026` 的 `2f49a40` 吸收：`RobocupWalk`、`changeRobocupMode`、version 字段，其中 version 在 gc2026 上还改成了可配置的 kV1/kV2。

### 2.4 `3v3`：2025 年 K1 3v3 官方 demo 快照

- `2c7f4f2` 是整仓替换式提交（2025-09-26），目录结构与 main 不同：
  - 有 `src/booster_msgs`、`src/booster_ros2_interface`、`src/robocup_ros2_interface/`，以及 `src/sound_play`、`distribution/` 打包脚本、`chrony_patch.tar.gz`、`la.py`；
  - 行为树多了 `assist.xml`、`chase.xml`。
- `622f74d`/`96ed289`：标定结果写入系统文件；launch 支持 `vision_config_path`。main 已有同等功能（见 `robocup-demo.md` §2.4），推断已被吸收。
- `950ff5a`：新增 ONNX 分割模型 `best-seg.onnx`。
- **3v3 相关逻辑**：
  - 角色只有 `striker` / `goal_keeper`。`game.number_of_players` 声明默认 2、yaml 设 3。`enable_role_switch` 开启后按 GC 在场人数补位（`3v3:src/brain/src/brain.cpp:467-474`），与 main 的 `handleCooperation` 同源。
  - 队内通信：discovery 广播 `20000+team`（1 s），状态单播 `30000+team`（100 ms），`brain_communication.cpp:24-25`，与 main 相同，**不符合 2026 规则**；yaml 中 `enable_com: false`。
  - GC：HL v12，话题 `/robocup/game_controller`。
  - **没有 VisualKick**（brain 中 `grep VisualKick` 无结果）。
  - 独有功能：`Speak`/`PlaySound` BT 节点、`/play_sound` 话题、`sound_play` 包、rerun 日志（`find_package(rerun_sdk)`）。
- **结论**：main 的 `dbcbc34`（2026-03-03，统一 K1/T1、加入 VisualKick、支持 Booster Studio）是它的后继版本。只有在需要语音或 rerun 时，才值得手工移植相应部分。

### 2.5 `sim`：仿真 mock 检测

- **谱系**：独立历史（根提交 `ee1e49b`，2024-11-15），brain 是第一代代码。
  - 订阅 `/joy`、`/booster_vision/detection<suffix>`、`/camera/camera/color/image_raw`（`sim:src/brain/src/brain.cpp:60-72`）；
  - 配置文件为 `brain.yaml`；
  - 使用 rerun 日志。
  - 与 main 的 brain 不兼容，**无法合并**。
- **mock 检测**（`7965dbe`）：新包 `src/sim_detection_bridge`。
  - 订阅仿真器的 `visualization_msgs/MarkerArray`，话题 `/booster/detections/<robot>_rgbd_camera`。
  - 每个 marker 转成一个 `DetectedObject`：
    - `label` 取 `ns`，为空时取 `text`；
    - bbox 编码在 `color.r/g/b/a` 中，分别为 xmin/ymin/xmax/ymax；
    - `position = position_projection = pose.position`；
    - `confidence` 固定为 1.0。
  - 发布到 `/booster_vision/detection/<robot>`。
  - `robot.robot_name` 必填。
- **无真机测试流程**：
  - `scripts/sim_build_v2.sh`：`colcon build --packages-ignore vision`，不需要 CUDA/TRT。
  - `scripts/sim_start_v2.sh`：启动 joy_node、game_controller、`brain sim:=true` 和 bridge，完全不跑 vision。
  - `fec77e8`：`walkMode()` 改为 `ChangeMode{"mode":4}`（kSoccer），`ToWalkMode` 在毫秒时间戳为 1000 的整数倍时才调用。
- **移植到 main 或 autocal 时要改的地方**：
  1. 发布话题改为 `/booster_soccer/detection/<robot>`；
  2. `confidence` 改为 100。main 的 brain 阈值是 ×100 刻度的 50，填 1.0 会被全部过滤；
  3. bridge 不产生 `LineSegments`，所以 `Border` 等基于线的定位不可用。
  - main 或 autocal 已经有 `src/detection_converter`（Python，输入 JSON String，输出 Detections + LineSegments，confidence=99），配合 `sim_start_multi.sh` 可以做 3v3 仿真。**优先用它**。bridge 只在仿真器输出 MarkerArray 时才有用，待验证。
  - 在 autocal 上仿真时，由于 brain 改订了 `/booster_soccer/t_head2base`，不跑 vision 时 `camToRobot` 不会更新，深度避障失效。

### 2.6 其它

- **`T2`**：单个 orphan 提交。
  - GC 只接受 v20（`src/brain/include/RoboCupGameControlData.h:10`）。
  - 队内广播 `10000+team`；有 `odom_theta_auto_align`、SDK 兼容测试（`src/brain/test/`）、rerun 日志。
  - 没有哨声检测（`grep -i whistle` 无结果）。
  - yaml 注释写有「0.90 for k1」，但 README 与 gc2026 都把它定位为 T2 分支。K1 适配待验证，不推荐。
  -
- 其余老分支都已合入或被取代，见 §1 表格。

---

## 3. 冲突与互斥点

用 `git merge-tree <base> <ours> <theirs>`（只读模式）模拟合并，结果如下：

| 组合 | 文本冲突 | 隐性问题 | 结论 |
|---|---|---|---|
| autocal ← gc2026 | 0 | 无（只带入 README 两行） | 可以合并，但没有必要 |
| autocal ← main | 0（README 自动合并） | 无 | 可选，只同步 README |
| autocal ← v1604（`merge-base 74d611f`） | 2 个文件：`robot_client.cpp`（version 固定 kV2 vs 可配置）、`vision.yaml` | `brain_tree.h`/`brain_tree.cpp` 会**重复定义 `RobocupWalk` 类和 `REGISTER_BUILDER`**：两边插入位置不同，文本合并「成功」，但编译失败。`config.yaml` 能自动合并 | **不要 merge** |
| autocal ← cherry-pick `1e1acac` | 3 处（`config.yaml`、`robot_client.cpp`、`vision.yaml`），另有同样的重复定义 | 同上 | 不要 cherry-pick，改为手工移植 locator 参数 |
| autocal ← cherry-pick `7d5be7b` | 0 | `config.yaml` 的改动与 autocal 现有内容相同，是空操作；只有 `brain_config.cpp` 生效（pitch 下限 0.2） | 可以直接 cherry-pick |
| autocal ← 3v3（`merge-base b1e27ca`） | **523 个冲突块，约 55 个文件**（brain、game_controller、vision、scripts 基本全部冲突），另有 4 个二进制 engine 文件冲突 | 目录结构不同（`interface/` 与 `robocup_ros2_interface/`） | 不可合并 |
| autocal ← sim / T2 | 无共同祖先 | 整仓替换 | 不可合并，只能手工拷贝 |

互斥点：
- **GC 协议**：v12（main、v1604、3v3）、v19/v20（gc2026、autocal）、v20-only（T2）三者互斥。msg 字段和话题名都不同，brain 回调无法同时兼容。
- **head pose 来源**：autocal 让 brain 订阅 `/booster_soccer/t_head2base`，其它分支都订阅 `/head_pose`。
- **VisualKick 退出方式**：main 用 `ChangeMode(kWalking)`，v1604/gc2026 用 `VisualKick(false)`。
- **队内通信**：main 和 3v3 用单播加 discovery；gc2026、autocal、T2 用 `10000+team` 广播。队友之间必须用同一分支的程序，否则收不到对方的包。

## 4. 推荐基线与合并方案

**基线**：`origin/sandbox/support_app_auto_calibration` @ `7b4ed35`。

理由：
1. 包含 2026 规则所需的全部功能：新 GC v19/v20、合规广播、哨声、任意球阶段机和二次触球、kSoccer 模式与 kV2 VisualKick。
2. 它是所有 K1 分支中最新的一个。
3. 自动标定可以通过 yaml 关闭（`auto_calibrate: false`），关闭后 vision 仍然通过 `t_head2base` 把原始 head pose 发给 brain，**手动标定依然可用**。
   - 如果不想让 brain 依赖 vision 提供 head pose，可以退回 `gc2026` @ `45b0e16` 作为基线。两者差异仅限 `ac022f0`、`7b4ed35` 两个提交。

**建议操作顺序**（只给出命令，本文分析过程中未执行）：
1. `git switch -c k1-2026-base origin/sandbox/support_app_auto_calibration`
2. `git cherry-pick 7d5be7b`：头部 pitch 下限 0.2。无冲突，需要实机验证视野。
3. （可选）手工把 `locator.min_marker_count: 3`、`max_residual: 0.5` 写进 `config_local.yaml`。来源是 `1e1acac`，放宽后误定位风险变大，要实测。
4. （可选）`git merge origin/sandbox/support_2026_game_controller`：只带入 README（`2819b13`、`45b0e16`）。
5. 本地修改（不是 cherry-pick）：
   - GC 白名单：比赛现场 GC 的 IP，或者关闭白名单；
   - `team_id`、`player_id`、`game_control_ip`；
   - 删除 `__pycache__`；
   - 替换 `vision.yaml`：换成自己机器的标定，或设 `auto_calibrate: false` 并用 `vision_old.yaml` 作模板；
   - 启动时带上 `vision_config_path:=/opt/booster`，让 brain 和 vision 读同一份外参。
6. 需要补做的功能，所有分支都没有：点球大战（`game_phase == 1`）、timeout（`game_phase == 3`）的处理；`CAUTIONED` 的语义确认；`message_budget` 限流。

**cherry-pick / 移植清单**：

| commit | 来源分支 | 操作 | 说明 |
|---|---|---|---|
| `7d5be7b` | v1604 | cherry-pick | `get_head_pitch_limit_up` 默认值 0.45 → 0.2 |
| `1e1acac`（部分） | v1604 | 手工移植 | 只取 locator 阈值 3 / 0.5。其余内容 autocal 已经包含 |
| `2819b13`、`45b0e16` | gc2026 | 可选 merge | 仅 README |
| `7965dbe`（部分） | sim | 可选手工拷贝 `src/sim_detection_bridge/` | 按 §2.5 修改话题和 confidence 后使用；一般用 main 已有的 `detection_converter` 就够了 |
| — | 3v3 / T2 | 不取 | 需要语音或 rerun 时手工参考 |

## 5. 待验证清单

- `/opt/booster/perception_info.yaml` 和 `booster-cli robot_info` 在各 K1 固件版本上是否存在、格式是否一致；App 写入的 `/opt/booster/vision.yaml` 是否是完整配置。
- `headpoint2pitchlink = (0.0613, 0, 0.108)` 对 K1 是否准确：它与 `/head_pose` 的参考点定义有关。
- K1 的声卡编号（`hw:1,0`）、6 通道布局（ch4 是否为参考信号）；Duerwen 库与 K1 麦克风阵列是否匹配；比赛现场噪声下的误检率和漏检率；哨声检测后 10 s 盲区的影响。
- `PENALTY_V20_CAUTIONED` 映射为 `PUSHING` 是否符合 2026 HSL 规则；`game_phase` 为 TIMEOUT 或 PENALTY_SHOOT_OUT 时机器人实际会怎么动。
- 旧固件（v1.5.x、v1.6.0.4 之前）收到带 `version` 字段的 VisualKick 请求后是否兼容；kV1 与 kV2 在 K1 上的实际差异。
- `RunOnce<RobocupWalk>` 是否只在第一次按 LT+A 时触发；之后固件摔倒自起时回到 kWalking 还是 kSoccer。
- 对方开球 SET 阶段的「本地放行」会不会在 GC 仍为 SET 时让机器人移动（Motion-in-SET 风险）；是否要去掉 `×100` 和 `+100` 这两个调试常量。
- `TeamCommunicationMsg` 的实际大小，以及 1 Hz 广播是否满足 2026 规则的 message budget。
- v1604 提交信息中的 "version 25 of gamecontroller" 具体指哪一版协议。
