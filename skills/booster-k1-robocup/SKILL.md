---
name: booster-k1-robocup
description: Use when developing, debugging, or deploying code for the Booster K1 humanoid robot or for humanoid robot soccer matches (the team's 3v3 K1 event, 2026 全球数字贸易创新大赛足球赛项, HSL-style rules) — Booster SDK (B1LocoClient, ChannelFactory, RPC, rt/* DDS topics), low-level joint control (LowCmd/LowState, rt/joint_ctrl, Custom mode, kp/kd), the organizer's K1_5v5_demo_1.7 / robocup_demo (vision/brain/game_controller, BehaviorTree, localization, kick, config.yaml, calibration), match-day deployment and GameController 7.0 referee operation, RL gait training or policy deployment (booster_gym, booster_train, booster_deploy, MuJoCo sim2sim), team communication, competition rules, or K1 onboard operations (SSH, Wi-Fi, firmware upgrade, services, logs).
---

# Booster K1 × RoboCup 开发参考

## 安装后的路径约定

本 skill 可安装到 Claude Code、Codex、Cursor 等支持 Agent Skills 的工具，支持项目级或全局安装。
- `SKILL_DIR` 指 agent 实际加载的本 `SKILL.md` 所在目录；运行脚本前将它设为该目录的绝对路径，不要假定安装在 `.claude/` 下。
- `ROBOCUP_ROOT` 指用户当前的 RoboCup 项目根目录；`refs/`、赛事 PDF 和主办方软件包均相对该目录。运行命令前将它设为项目绝对路径。
- `bootstrap_refs.sh [ROOT]` 优先使用显式参数，其次 `ROBOCUP_ROOT` 环境变量，最后当前工作目录；`find_ref.sh` 使用 `ROBOCUP_ROOT` 环境变量或当前工作目录。全局安装目录不用于存放语料库。
- 安装即包含全部 `references/` 文档。需要核对源码时才运行 bootstrap：它会联网克隆/更新官方仓库并抓取文档，需要 Git、Bash、Python 3、curl、unzip 和网络访问。Windows 请在 WSL 中运行这些辅助脚本。
- 固件、`K1_5v5_demo_1.7.zip`、`sdk_release.zip` 和赛事 PDF 不随 skill 分发，请向队内获取并放到项目根目录。缺少主办方 Demo 时，不能把公开 main 分支当作比赛程序。

## 概览

本 skill 是 Booster K1 人形机器人足球开发的**开发索引**。所有结论来自本地语料库 `refs/`（官方仓库 + 官方文档快照 + HSL 规则/GameController + 主办方发放的软件包），参考文件逐条标注了出处路径。

**本队赛事**：**2026 全球数字贸易创新大赛（具身智能机器人挑战赛）足球赛项**，区级赛事（不是正式 RoboCup），阵容 **3v3**，全部使用 K1。主办方讲义（仓库根目录的 PDF）的整理与代码核对见 `event-sop.md`。规则条文还没拿到（`issues.md` C 组）：`robocup-rules.md`（HSL 2026）只作参考基线，回答规则问题时要说明这一点；但**裁判机是 HSL GameController 7.0.0-rc.3**，它内置的时长、罚时、通信额度会自动执行。

**本队技术栈 = 主办方指定的 1.7 栈**（2026-09-24 起；v1.6 栈已废弃）：

| 组件 | 版本 | 本地对应 |
|---|---|---|
| K1 固件 | **≥ 1.7**（1.8 也可以）；发放的升级包 `1.7.2.0-dev-yunlong-…single.run`（仓库根目录，dev 构建） | changelog 在 `refs/booster_docs/`；兼容性见 `fw1.7-demo-v1.7.md` §2 |
| SDK | `sdk_release.zip`（仓库根目录） | **= 公开 SDK 提交 `d5d8f7a`（"update for 1.7.0 firmware"），已核实逐字节相同** → `refs/booster_robotics_sdk@fw1.7` |
| Demo | `K1_5v5_demo_1.7.zip`（包名 5v5，按 3v3 配置） | `refs/K1_5v5_demo_1.7`（无 .git）。属于公开分支 `feat/k1_3v3_demo` → `support_T2` 那条线，**不是** main/gc2026/autocal 线 |
| GameController | HSL GC **7.0.0-rc.3**，发 **struct v20**（158 B） | `refs/robocup_league/GameController@v7.0.0-rc.3`。Demo 1.7 同时能收 HL v12 和 v20 |

**其它参考文件是按最新 SDK 1.6.3 / 固件 1.8 写的**；在固件 1.7 上不存在或行为不同的地方，以 `fw1.7-demo-v1.7.md` 为准（勘误表 §4，文中标【fw1.7 #N】）。`robocup-demo.md` 分析的是公开 main 分支，**改比赛程序时以 `refs/K1_5v5_demo_1.7` 为准**。

**核心原则：写任何会下发到机器人的代码前，先在 `refs/` 里找到对应的源码或文档依据；参考文件里标「待实机验证」的点，不能当成事实写进代码或回答。**

以下情况运行 `bash "$SKILL_DIR/scripts/bootstrap_refs.sh" "$ROBOCUP_ROOT"`（克隆/更新全部仓库和分支、建立版本 worktree、解压主办方 Demo 包，重新抓取 docs.booster.tech，并提示官方新发布的仓库）：`refs/` 不存在；机器人固件升级过；主办方发了新包；距上次更新超过 30 天（看 `git -C refs/robocup_demo log -1 --format=%cd origin/main` 和 `refs/booster_docs` 的修改时间）。更新后要检查参考文件里引用的行号和结论是否仍然成立。
在语料库里搜索：`ROBOCUP_ROOT="$ROBOCUP_ROOT" bash "$SKILL_DIR/scripts/find_ref.sh" <正则> [子目录]`（已排除 mesh、三方库、二进制）。

## 按问题找参考文件

路径均相对本 skill 的 `references/`。

| 你要做的事 | 先读 |
|---|---|
| **赛事现场操作**：连网、升级固件/装 SDK、部署和配置 Demo 1.7、相机与手眼标定、看日志、上场按键、换电、**裁判机（GC 7.0）操作与判罚按钮** | `event-sop.md` |
| 本队 1.7 栈：固件 1.7 上哪些 API/话题/行为不同、Demo 1.7 与公开代码的差异和仍存在的 bug、其它参考文件的勘误 | `fw1.7-demo-v1.7.md` |
| 调用高层运动接口（走、转头、起身、踢球、切模式）、RPC 返回码、Python/ROS 2 SDK 选型 | `sdk-api.md` |
| 直接发关节指令、自研步态/控制器、绕过 SDK 用 DDS/ROS 2 收发、部署 RL 策略到真机 | `low-level-control.md` |
| 关节下标/名称/限位/力矩、默认站姿、kp/kd、腿长、质心、并联踝、IMU/相机坐标系 | `k1-hardware.md` |
| 比赛程序的整体架构：视觉检测与测距、行为树、角色分配、自定位、踢球决策（按公开 main 写，行号以 Demo 1.7 为准） | `robocup-demo.md` |
| 公开 robocup_demo 各分支里某个修复/功能的来龙去脉（哨声检测等可移植的想法） | `robocup-demo-branches.md` |
| 训练 RL 行走/踢球、sim2sim、booster_deploy 接入自己的策略、3v3 仿真赛 | `rl-sim-deploy.md` |
| 规则参考（HSL 2026）：场地、状态机、罚则、**GC v20 结构体与队内通信预算**、赛前检查清单 | `robocup-rules.md`（先看 `issues.md` C 组里本赛事已确认的规则） |
| 连机器人（IP/SSH/Wi-Fi）、模式与遥控器、服务启停、日志、固件升级与版本兼容 | `k1-operations.md` |
| 问题库：待问主办方的规则（C）、版本与物料（V）、待实机验证的技术点（P0–P4）、开发待办（T）；记录结论 | `issues.md` |

参考文件都很长（300–770 行）：先 `grep -n '^#' <file>` 看目录，再读相关小节，不要整篇读入。

## 硬性事实（违反会导致事故、丢分或隐蔽 bug）

**本赛事与 Demo 1.7（上场前必查，详见 `event-sop.md` §0）**
- 🔴 **队内通信额度**：Demo 1.7 每台机器人每 100 ms 广播一条队内消息（`brain_communication.h:65`），3 台约 30 条/s；GC7 每队每场只有 **12000 条**（只在 READY/SET/PLAYING 计数），约 7 分钟用完。**用完后 GC 会把本队比分清零，之后进球也不算**（GC7 `actions/team_message.rs:18-20`）。上场前必须降到 ≥ 400 ms 一条，或按 GC 包里的 `message_budget` 限速（`issues.md` T10）。
- 🔴 **`team_id`** 要和裁判机里选的队号一致，而且和对手不同（Demo 默认 70，也就是 GC 表里的 `B-Team`）。**裁判机 IP 要改两处**：`config.yaml` 的 `game_control_ip`，和 `game_controller/launch/launch.py` 的白名单。白名单默认开启，只放行 `172.169.80.24`，不改就收不到任何裁判包。
- `number_of_players` 默认是 5，要改成 3；`field_type` 默认 `robo_league`（22×14），按场地改；守门员用 `player_id: 1`（GC 默认 1 号是守门员）。改任何配置都要 `stop.sh → build.sh → start.sh`：`build.sh` 不带 `--symlink-install`，运行时读的是 `install/` 里的副本。
- **`/opt/booster/vision.yaml` 在运行时不会被读取**（`start.sh` 不传 `vision_config_path`），讲义 p.18「优先于 Demo 配置」的说法是错的。视觉参数和标定结果要写进 `src/vision/config/vision.yaml`（标定时第一个问题答 `y` 就会直接改写它），然后 build。d-robotics 相机的模板是 `vision_d.yaml`。
- 上场顺序：PREP → 放到场边 → WALK → **LT+A**（切 kSoccer 并定位，只有这一步会切足球模式）→ 头部稳定跟球 → **LT+B**（自动策略）。LT+X = 人工接管（机器人可能还在执行最后一条速度指令，轻推摇杆打断）；LT+Y 会切换角色，比赛中别误按。
- `start.sh` 会 `sudo pkill -9 python3`，并**永久禁用** `booster-agent-manager.service`。自己的 Python 程序不要和 Demo 同时跑；赛后要用 App/Agent 时，手动 `sudo systemctl enable --now booster-agent-manager.service`。
- Demo 1.7 的 brain include 了 `booster_internal/robot/b1/b1_loco_internal_api.hpp`：它**不在任何公开 SDK 里**（`sdk_release` 也没有），**1.7.2 升级包也不安装它**（包内只有运控库里的枚举定义，值 `kEnableRobocupWalkMode = 100008`）。它只被从未调用的 `RobotClient::walkMode()` 使用（`robot_client.cpp:105-113`；include 在 `robot_client.h:10`、`robot_client.cpp:3`）。编译报找不到这个头文件时：删掉这两行 include 和 `walkMode()`，或把枚举换成常量 `100008`（`issues.md` V6）。Demo 依赖机器人上的 ROS 2 包和 TensorRT，按主办方流程在机器人上编译。
- Demo 1.7 里**仍存在**的定位 bug：`brain_tree.cpp:3361` 的 `dy`、`:3673-3674`、`:3702`、`:3551/:3669`（`issues.md` T4）；`setVelocity` 会把小于 0.3 的速度抬到 0.3（`robot_client.cpp:195-200`）。
- GC7 进入 PLAYING 后，最多 10 s 内仍然发旧状态（`delayAfterPlaying`），而 Demo 没有哨声检测，所以开球后机器人会多站最多 10 s，除非裁判机勾了 `Testing → No Delay`（`issues.md` C12）。

**固件 1.7 专属（本队）**
- SDK `d5d8f7a`（固件 1.7）**有**：`kSoccer`、`VisualKick(start, kV1|kV2)`（请求必须带 `version`）、`GetUp(GetUpVersion)`/`GetUpWithMode(mode, GetUpVersion)`（kV2 = BMM 稳定起身）、`GaitType::kWholeBodyHumanlikeGaitV2`、`RotateHeadWithTime`、`GetSensors/GetHands/GetRobotModel`、话题 `rt/odom`/`rt/imu/data`/`rt/joint_states`、`HandEyeCalibClient`、`CameraClient`、`SetLEDLightColors`、`kJointCntK1`、`MoveCommand`。其中 1.7 新增的这些接口在文档里默认要求 **固件 ≥ 1.7.1**，1.7.0.x 上先实测返回码。**没有**（1.8 才有）：`ResetOdometryTo`（只能 `ResetOdometry()` 清零）、异步 Operation RPC（`RpcCallMode`/`AsyncSendApiRequest`）、返回码 503、`GetTrainedTrajStatus`/`rt/trained_traj_status`；LocoApiId 最大到 2046。Python 固定 `booster_robotics_sdk_python==1.5.6`（有 `kJointCntK1`，`b1-cli` 入口拼错不能用）。完整对照见 `fw1.7-demo-v1.7.md` §1。
- 固件 1.7.x 上**仍存在**、1.8.0 才修的问题：kSoccer 下头部高速追球会 **CAN 掉线**；**kV1 踢球时里程计冻结**（Demo 默认 kV2，保持）；进入 Custom **不会**自动保持站立（必须预发保持帧）。IMU 偶发异常数据导致摔倒的问题 1.7.1 已修。
- 固件 1.7 上**可以用**：`boosteros`（要先 `pip install boosteros`，1.8 起内置）、Agent/Booster Studio 比赛框架（`min_api_level 10700`）；App 手眼自动标定（≥ 1.7.1）；`booster_deploy`（README 要求 ≥ 1.7.2，1.7.2.0 刚好满足）。

**底层控制**
- K1 底层数组长度是 **22**（`kJointCntK1`）；`kJointCnt` 是 T1 的 **23**，**官方 SDK 示例和 ArmController 用的都是 23，不能照抄**。顺序：头 2 → 左臂 4 → 右臂 4 → 左腿 6 → 右腿 6。髋链顺序是 **pitch-roll-yaw**。
- `rt/joint_ctrl`（LowCmd）只在 **Custom 模式**下生效。进入流程：在 Prepare 下先发一帧「当前角度 + 较高 kp/kd」的保持指令，再 `ChangeMode(kCustom)`，之后以稳定频率持续发布（完整流程见 `low-level-control.md`）。Custom 下 `weight` 字段无效；PD 在机器人侧执行。
- 踝是**并联双曲柄**机构。C++ `LowCmd` 默认 `cmd_type = PARALLEL`；按 URDF 的 ankle_pitch/roll 发指令时必须设成 **SERIAL**（booster_deploy 的做法），否则踝会乱动。
- 退出 Custom 一律切到 **Prepare 或 Damping**。CUSTOM → WALK 手册说不允许，booster_deploy 却这么做；在当前固件上实测之前（`issues.md` S5）不要依赖它。
- **断流不会自动停机**：没有文档说明有看门狗，源码注释显示机器人会保留最后一帧指令。控制进程必须有退出/异常处理，能把机器人切回 Damping。
- **DDS 没有鉴权**：所有 K1 默认都在 domain 0，同一网段里任何人发的 `rt/joint_ctrl` 都会被处于 Custom 的机器人执行。在赛场或共享网络中，必须隔离 domain 或网络。
- SDK 底层就是 Fast DDS，类型名是 ROS 2 风格（`booster_interface::msg::dds_::LowCmd_`），`rt/joint_ctrl` 就是 ROS 2 的 `/joint_ctrl`，因此可以不用 SDK，直接用 ROS 2 或原生 DDS 收发。
- 策略观测里不能用机身线速度（真机不提供）；各仓库观测顺序不同（booster_gym `[gravity, ang_vel…]` vs booster_deploy `[ang_vel, gravity…]`），移植策略必须逐项对齐。
- `booster_assets` 在 2026-08-28 把 K1 关节/link 名改成了小写；`booster_train` 仍用旧名，训练时要固定到旧提交 `508cbee6ca`。

**高层 SDK**
- 先 `ChannelFactory::Instance()->Init(domain, ip)`，再 `B1LocoClient::Init()`；K1 也用 `B1LocoClient`。
- 上电后的模式顺序：`kDamping → kPrepare → kWalking`，不能从 Damping 直接进 Walking。`kSoccer` 能从哪个模式进入尚待实机验证（`issues.md` V7）；Demo 是在 WALK 下由 LT+A 切入的。
- 连续速度控制用 `MoveCommand()`（不等回复）；`Move()` 会阻塞等回复。Demo 不走 SDK 客户端，而是把 RPC 请求（`booster_msgs/RpcReqMsg`）发到 ROS 2 话题 `LocoApiTopicReq`。
- **K1 上不要调用 `LieDown()`**：可能返回成功，实际执行的却是零位轨迹。

**比赛程序与规则**
- **GameController 版本必须和 Demo 的解析代码匹配**，否则机器人收不到裁判包、一直不动。本赛事 GC7 发 v20，Demo 1.7 按包长同时接受 v12（688 B）和 v20（158 B）。赛前务必用赛事实际的裁判机实测收包：`game_controller.log` 里应出现 `version=20`，GC 界面队员格显示绿勾（`issues.md` T11）。
- 队内通信规则（GC7 与 HSL 2026 一致）：UDP 广播，端口 `10000 + 队号`，单包 ≤ 512 B，额度见上；回包 `RGrt` v4 单播到 GC 的 3939，0.5–2 Hz，`fallen` 只能取 0/1。
- Demo 1.7 自带 TensorRT engine（文件名带 `10.3`），不需要 `git lfs pull`；公开 robocup_demo 的模型才要 `git lfs pull`。

**运维**
- 有线：机器人 `192.168.10.102`，开发机设 `192.168.10.x/24`（x ≠ 102）；SSH `booster` / `<机器人当前密码，请向队内获取>`。比赛时用 `sudo nmtui` 让机器人连上和裁判机同一个 Wi-Fi（极客版选 `wlan0`），之后用无线 IP 操作。同一网络多台机器人要用不同的 DDS/ROS domain 隔离（Demo 本身没做）。
- 固件与 SDK 必须配套：开发前在每台机器人上 `cat /opt/booster/version.txt` 核对（必须 ≥ 1.7，3 台一致）。`version.txt` 是追加写入的，看最后一段。SDK 只在缺失或编译报版本错误时装 `sdk_release`（固件包不含 C++ SDK）。主办方的 1.7.2 dev 包**必须联网安装**，会停运控（机器人必须有可靠支撑）、覆盖 `Gait/configs`（含 F1 键，不备份）、清空蓝牙配对，并可能自动重启（`fw1.7-demo-v1.7.md` §2.1）。全队固件版本必须一致。

## 开发流程

1. **定位依据**：用 `find_ref.sh` 在 `refs/` 找到要调用的接口或要修改的代码，记下文件路径和行号。比赛程序优先在 `refs/K1_5v5_demo_1.7` 里找。
2. **核对版本**：确认机器人固件版本与所用 SDK/分支配套；API 或话题在不同固件版本里行为不同（`fw1.7-demo-v1.7.md`）。
3. **先仿真后真机**：底层控制和 RL 策略先在 MuJoCo 里跑通（`booster_deploy --mujoco` 或 `booster_gym/play_mujoco.py`）；比赛决策逻辑先在本地起 GC 7.0.0-rc.3 联调状态机。
4. **真机底层测试的安全规范**：机器人挂在吊架/保护绳上；先只订阅 `rt/low_state` 验证数据；指令从当前姿态平滑插值，kp 从小往上加；准备好随时切回 Damping（软急停：遥控器 L2+Back 或背部 F1，只有软急停、没有硬件急停，见 `k1-operations.md` §2.3）；程序退出或异常时必须能让机器人回到阻尼状态。
5. **回答问题或写代码时**，引用参考文件或 `refs/` 里的出处；属于「待实机验证」的点要明确说出来，并给出验证方法（`issues.md` 有现成的方法）。
6. **问题入库**：开发中发现的新问题（待确认规则、待验证技术点、待办任务）追加到 `issues.md` 对应分组；有结论后更新该行状态（日期 + 结论，技术点加固件版本），并修改原参考文件里的标注。

## 语料库地图（`refs/`）

| 路径 | 内容 |
|---|---|
| **`K1_5v5_demo_1.7/`** | **本队比赛程序基线**：主办方 Demo 1.7 解压（`src/{brain,vision,game_controller,booster_ros2_interface,booster_msgs,robocup_ros2_interface}`、`scripts/`、`configs/`；含 TensorRT engine） |
| **`booster_robotics_sdk@fw1.7/`** | **本队 SDK**：提交 `d5d8f7a` 的 git worktree（= `sdk_release.zip`） |
| **`robocup_league/GameController@v7.0.0-rc.3/`** | **本赛事裁判机源码**：HSL GC tag `v7.0.0-rc.3`（`config/{large,middle,small}_{foundation,advanced}/params.yaml`、`game_controller_msgs/headers/RoboCupGameControlData.h`） |
| `booster_robotics_sdk/` | 最新 C++ SDK（1.6.3，固件 1.8）：`include/booster/robot/b1/`（LocoClient、常量、MoveController）、`include/booster/idl/`（DDS 消息）、`example/{high_level,low_level}`、`lib/{x86_64,aarch64}` |
| `booster_robotics_sdk_ros2/` | ROS 2 接口包 `booster_interface`（msg/srv）与示例 |
| `robocup_demo/` | 公开比赛 Demo（ROS 2 Humble）：`src/{vision,brain,game_controller,detection_converter,interface}`、`configs/`、`scripts/`；全部远程分支已 fetch 到 `origin/*`（Demo 1.7 的近亲是 `origin/sandbox/feat/k1_3v3_demo`、`origin/sandbox/support_T2`） |
| `booster_deploy/` | sim2sim/sim2real 统一部署框架，含 K1 行走策略 `k1_walk` |
| `booster_gym/` | Isaac Gym RL 行走（仅 T1 配置）+ MuJoCo 回放 + 旧版真机 deploy |
| `booster_train/` | Isaac Lab 任务（K1 动作跟踪 BeyondMimic） |
| `booster_assets/` | K1/T1/T2 URDF、MJCF（串联/并联踝）、动作数据 |
| `sim-3v3-simple-framework/`、`booster_champion_example/` | Booster Studio 3v3 仿真赛 Agent 框架与示例（仅高层策略） |
| `booster_docs/` | docs.booster.tech 快照（文件名 = URL 路径，`__` 分隔）：K1 手册、C++ SDK、Booster OS Python SDK、开源项目、固件 changelog |
| `robocup_league/` | HSL `HSL-Rules`（Rules.tex/pdf）、`GameController`（HSL GC master，v7.0.0+）、`RobotInspection`；`GameController-HL-2025`（旧 HL GC，发 HL v12） |
| `booster_robotics_sdk@fw1.6/`、`robocup_demo@v1.6.0.4/` | 已废弃的 v1.6 栈（SDK `324946e`、分支 `sandbox/support_k1_v1.6.0.4+`），只用于对比旧代码 |

## 常见错误

| 错误 | 后果 | 正确做法 |
|---|---|---|
| 队内通信保持 Demo 默认的 10 Hz × 3 台 | 约 7 分钟耗尽 12000 条额度，GC 把本队比分清零 | 降频或按 `message_budget` 限速，比赛中盯住 GC 界面的 Messages |
| 只改了 `game_control_ip`，没改 GC 白名单（或反过来）；`team_id` 与裁判机不一致或与对手相同 | 收不到裁判包或回包，机器人一直不动；GC 界面显示红叉 | 两处 IP 都填裁判机实际广播网卡的 IPv4；队号与主办方分配一致；改完重新 build |
| 标定后只更新了 `/opt/booster/vision.yaml` | 运行时读不到，测距仍是旧参数 | 改 `src/vision/config/vision.yaml`，然后 `build.sh` 并重启 |
| 跳过 LT+A 直接按 LT+B | 机器人在 WALK 模式下踢比赛，没有进 kSoccer，也没定位 | 先 LT+A，等头部稳定跟球后再 LT+B |
| 照搬 T1 示例的 `kJointCnt` / T1 配置 | 指令数组错位，驱动错误关节 | 用 `kJointCntK1` 和 `k1-hardware.md` 的关节表 |
| 在非 Custom 模式发 LowCmd | 指令被忽略，以为是代码 bug | 先确认 `GetMode()` 返回 Custom |
| 用最新 SDK（1.6.3）的接口写代码，跑在固件 1.7 的机器人上 | 调用了 1.7 上不存在的接口，返回错误或行为不符 | 头文件以 `refs/booster_robotics_sdk@fw1.7` 为准，接口先查 `fw1.7-demo-v1.7.md` §1 |
| 把 `booster_gym` 训练的策略直接塞进 `booster_deploy` 的现成行走 Policy | 观测顺序不一致，真机失稳 | 自己写 Policy 类，逐项对齐观测/动作 |
| 按 `robocup-demo.md` 的行号去改 Demo 1.7 | 找不到代码或改错位置（Demo 1.7 是另一条谱系） | 在 `refs/K1_5v5_demo_1.7` 里重新定位 |
| 把「待实机验证」的推断写成确定结论 | 真机上出错，排查方向被误导 | 标出不确定性，并给出验证步骤 |
| 把 HSL 2026 规则条文当成本赛事规则 | 按错误规则设计行为 | 以主办方规则为准；未确认的记入 `issues.md` C 组（GC 自动执行的参数除外） |
