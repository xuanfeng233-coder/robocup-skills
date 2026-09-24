# 问题库：待确认、待验证、待办

> 本队参加的是**区级赛事（非正式 RoboCup），阵容 3v3**：**2026 全球数字贸易创新大赛（具身智能机器人挑战赛）足球赛项**。主办方于 2026-09 发放技术分享讲义，并指定技术栈：固件 ≥ 1.7、`K1_5v5_demo_1.7.zip`、`sdk_release.zip`、HSL GameController 7.0.0-rc.3（整理见 `event-sop.md`）。**v1.6 栈（Demo v1.6 / 固件 1.6 / GC 1.0.1）已废弃**（2026-09-24）。
> 本文件汇总四类问题：**C** = 要问主办方的赛事规则；**V** = 版本与物料；**P0–P4** = 要在真机上验证的技术点（汇总自各参考文件的「存疑 / 待实机验证」小节）；**T** = 已知要做的开发任务。每条都注明出处，细节去原文件看。
> **有结论后**：在该行「状态」一栏写 `✅ YYYY-MM-DD 结论`（技术点还要写固件版本），并同步修改原参考文件里的对应标注。新发现的问题直接追加到对应分组，编号顺延。
> 优先级：C = 定方案前先问清；V = 版本与物料；P0 = 首次在真机上跑底层程序**之前**必须弄清；P1 = 自研底层控制/步态前；P2 = 改高层行为前；P3 = 用 Demo 参赛前；P4 = 运维。**标 🔴 的是不处理就会直接影响比赛结果的。**

## C 赛事规则（问主办方）

规则条文以 HSL 2026（`robocup-rules.md`）作参考基线。**裁判机已确定是 HSL GC 7.0.0-rc.3**，它自带的时长、罚时、通信额度等参数会自动执行。

| # | 问题 | 为什么重要 | 状态 |
|---|---|---|---|
| C1 | 规则条文依据什么：HSL 2026、RoboCup 中国赛，还是主办方自拟？能否拿到规则原文 | 决定其余所有规则细节 | 部分确认：讲义的判罚按钮说明与 HSL 2026 一致（`event-sop.md` §9.3），规则原文仍未拿到 |
| C2 | 正式比赛用哪个 GameController | 决定 Demo 的协议解析 | ✅ 2026-09-24 讲义：HSL GC **7.0.0-rc.3**（struct v20）；Demo 1.7 同时支持 v12/v20（`event-sop.md` §0 #2） |
| C3 | 场地尺寸、球门尺寸、用球规格、场地线和地毯材质 | `field_type`（`kid_size` 9×6 / `adult_size` 14×9 / `robo_league` 22×14）、视觉模型、踢球力度 | 讲义只说「按比赛场地设置，以赛事要求为准」 |
| C4 | 比赛时长、中场休息、平局如何处理（加时/点球） | 电量规划、点球逻辑 | 部分确认：讲义截图为每半场 10:00（GC 默认 600 s，加时 2×300 s，点球 3 轮） |
| C5 | 开球、定位球、界外球、点球规则；READY 阶段是否自主走位 | Demo 的站位与状态机 | 部分确认：GC 使用直接/间接任意球、点球、界外球、球门球、角球；Ready 时「机器人执行上场逻辑」（`event-sop.md` §9.2） |
| C6 | 犯规与罚下；摔倒后的起身时限；pick-up 规定 | 行为约束、起身逻辑 | 部分确认：判罚按钮 21–33 与 HSL 一致，Pickup 流程见 `event-sop.md` §9.4 |
| C7 | 是否强制守门员；3 台机器人的角色是否有限制 | 角色配置 | GC 默认 1 号为守门员 |
| C8 | 赛场网络：路由器与频段、是否允许机器人之间通信、带宽或包数限制 | 队内通信、DDS 隔离 | 部分确认：所有设备接同一台比赛路由器，机器人用 Wi-Fi（`event-sop.md` §4）；包数限制见 C13 |
| C9 | 是否要求全自主？比赛中能否遥控或人工干预 | 能否用遥控器兜底 | 讲义把 LT+X 人工接管作为安全手段，比赛中能否使用未说明 |
| C10 | 机器人硬件限制：能否改装；电池能否中场更换 | 检录与备赛 | 讲义有换电流程（§8），未说明比赛中何时允许 |
| C11 | **各队的 `team_id` 怎么分配？和 GC 队伍表里的哪个队对应？** Demo 默认 70（GC 表里是 `B-Team`），两队不能相同 | 队号不一致或两队相同时，收不到裁判包、队内通信串包 | 🔴 |
| C12 | 技术裁判是否勾选启动页 `Testing → No Delay`？ | 不勾选时，每次进入 PLAYING 后机器人最多多站 10 s（Demo 没有哨声检测） | |
| C13 | GC 选哪个组别：`Large/Middle - Foundation`（每队 3 人）还是 `Advanced`（5 人，讲义截图用的是这个）？队内通信额度是否维持 12000 条/场？ | 影响替补编号，以及 T10 要降到多少频率 | 🔴 额度直接关系到比分会不会被清零 |
| C14 | 裁判机 IP 和比赛 Wi-Fi（SSID/密码/频段）何时公布；是否允许赛前在现场联调 | 每台机器人要改 `game_control_ip` 和白名单并重新编译 | |

## V 版本与物料

详细说明和依据见 `fw1.7-demo-v1.7.md`。

| # | 事项 | 怎么做 | 为什么重要 | 状态 |
|---|---|---|---|---|
| V1 | 主办方的 Demo 包本体 | — | 基线 | ✅ 2026-09-24 `K1_5v5_demo_1.7.zip` → `refs/K1_5v5_demo_1.7/`（与公开分支的关系见 `fw1.7-demo-v1.7.md` §3） |
| V2 | 裁判机二进制 `game_controller-7.0.0-rc.3-4-x86_64-unknown-linux-gnu.zip` | 向主办方索取（讲义里有，仓库里还没有）；本地搭裁判机联调，`tcpdump -i <网卡> udp port 3838 -X` 确认包长 158、`RGme` 后是 `14`（v20） | 赛前联调；确认主办方有没有改 `config/*/params.yaml` 或 `teams.yaml` | 源码已有：`refs/robocup_league/GameController@v7.0.0-rc.3` |
| V3 | 每台 K1 的精确固件版本 | `tail -n 5 /opt/booster/version.txt`（文件是追加写入的，看最后一段的 Version 和 Commit ID） | 必须 ≥ 1.7（1.7 新接口要 ≥ 1.7.1）；3 台要一致 | 发放的是 **dev** 包 `1.7.2.0-dev-yunlong-…`（2026-08-18 构建，Commit `263509d0…`），比官方 1.7.2 GA 晚两周；向主办方确认它就是指定版本 |
| V4 | 机器人上的 SDK 是否就是 `d5d8f7a`（= `sdk_release.zip`） | `diff -r /usr/local/include/booster refs/booster_robotics_sdk@fw1.7/include/booster`；比较 `libbooster_robotics_sdk.a` 的 md5 | 决定能否直接用 `@fw1.7` 查头文件、编译 | `sdk_release.zip` 与 `d5d8f7a` 已核实逐字节相同 |
| V5 | 是否允许升级到固件 1.8 | 讲义：1.8 也可以 | 1.8.0 修掉了 CAN 掉线、kV1 里程计冻结；但 Demo 1.7 是按 1.7 验证的。App OTA 会装 1.8.0.9，**全队必须同一版本** | ✅ 2026-09-24 允许（讲义 p.2）；待决定：全队 1.7.2 还是全队 1.8 |
| V6 | 机器人上有没有 `booster_internal/robot/b1/b1_loco_internal_api.hpp` | `find / -path '*booster_internal*' 2>/dev/null`；或直接 `build.sh` 看是否报错 | Demo 1.7 的 brain 要 include 它（`robot_client.h:10`、`robot_client.cpp:3`）。公开 SDK、`sdk_release`、1.7.2 升级包里都没有 → 缺了就编译失败 | 已知绕法：只有未被调用的 `walkMode()` 用到它（值 `kEnableRobocupWalkMode = 100008`，从固件运控库 DWARF 读出），删掉 include 和该函数即可 |
| V7 | kSoccer 的合法前置模式；起身后回到 kWalking 还是 kSoccer | 吊架上测试，同时 `ros2 topic echo /robot_states` | 比赛模式切换逻辑 | |
| V8 | kSoccer 下长时间追球会不会 CAN 掉线（1.8.0 才修复） | 连续追球 ≥ 10 分钟并看日志 | 比赛中途掉线 = 机器人失控 | |
| V9 | kV1 踢球时里程计是否冻结（1.8.0 才修复）；kV1 与 kV2 的实际踢球距离 | 踢球时 `ros2 topic echo /odometer_state`；量距离 | 决定 `visual_kick_version`（Demo 默认 kV2） | |
| V10 | 1.7 上 Custom 模式会不会保留预发帧（自动保持站立 1.8.0 才加入）；手柄急停在 Custom 下是否有效 | 吊架上测试（同 S1、S2） | 底层控制安全 | |
| V11 | 低电量返回码 503 与低电量模式配置 | 低电量时调 `Move` 看返回码；问官方 | 电量策略 | |
| V12 | Demo 的 `start.sh` 会 `disable --now booster-agent-manager.service`：固件 Soccer Agent 的按键（L2+X/Y 等）是否还会被触发；赛后如何恢复 App/Agent | 跑 Demo 时实机按键测试；`systemctl status booster-agent-manager` | 按键冲突、赛后环境恢复 | |
| V13 | `get_up_version: kV2` 在 1.7.2 上的起身成功率 | 实机摔倒测试，对比 kV1 | 讲义：「以现场验证后的发布配置为准」 | |
| V14 | 机器人上有没有 `booster_rpc_service`；`LocoApiTopicReq` 桥接在 1.7 上是否正常 | `ros2 service list`；`ros2 topic info LocoApiTopicReq` | Demo 的全部运动指令都走这个话题 | 1.7.2 包里有 `/opt/booster/ros2/booster_rpc_bridge`（`topic_prefix: LocoApiTopic`、`service_name: booster_rpc_service`），实机待确认 |
| V15 | 升级 1.7.2 包后的恢复工作：F1 键配置（`Gait/configs` 被覆盖且不备份）、手柄蓝牙重新配对、hostapd/dnsmasq 被禁用后 App 直连热点是否还能用 | 升级后逐项检查；升级前备份 `/opt/booster/Gait/configs` | 升级会改动这些，赛前别临时升级 | |

## T 开发待办（backlog）

| # | 任务 | 前置条件 | 出处 | 状态 |
|---|---|---|---|---|
| T1 | **以 `K1_5v5_demo_1.7` 为基线开发**：在机器人上解压后先 `git init` 做初始提交；开发机对照 `refs/K1_5v5_demo_1.7` | — | `event-sop.md` §6.1；`fw1.7-demo-v1.7.md` | 已定：Demo 1.7（2026-09-24） |
| T2 | **上场前逐台改配置**：`config.yaml` 的 `team_id`（C11）、`player_id`（1 = 守门员）、`player_role`、`number_of_players: 3`、`field_type`（C3）、`game_control_ip`、`player_start_pos`；`game_controller/launch/launch.py` 的白名单；相机类型对应的 `vision.yaml` 与 `cam_*`；改完 `build.sh` | C3、C11、C14 | `event-sop.md` §6.2–6.4 | |
| T3 | **确认视觉模型能加载**：Demo 1.7 自带 7 个 TensorRT engine（文件名带 `10.3`，说明是按 TensorRT 10.3 生成的）；每台机器人看 `vision.log` 里模型初始化完成 | V3 | `event-sop.md` §6.4 | |
| T4 | **修 Demo 1.7 里仍存在的定位 bug**（READY/SET/定位球阶段都会执行）：`SelfLocate2X` 的 `dy`（`brain_tree.cpp:3361`，应为 `-(p0.y+p1.y)/2`）；`SelfLocatePT` 两个条件都比 x（:3673-3674）、模板点应为 `fd.length/2`（:3702）；LT/PT 内层循环 `j=i+1` → `j=0`（:3551、:3669）。修完用实机录包验证误定位率 | T1 | `fw1.7-demo-v1.7.md` §3.3 | |
| T5 | **3v3 角色与站位调参**：角色分配代价函数、开球站位、`far_set_play_search`/`set_play_stand` 参数（按 C3/C5/C7 的结论） | C3、C5、C7 | `robocup-demo.md` §3.5–3.6；Demo 1.7 `config.yaml:100-119` | |
| T6 | **底层安全基建**（开始底层开发前）：独立看门狗进程（心跳超时就切 Damping）、每台机器人隔离 DDS domain、发送端关节/力矩限幅 | S1、S4 | `low-level-control.md` §4.5–4.6、§6.5 | |
| T7 | **自研步态（长期）**：把 booster_gym 移植到 K1（官方没有公开 K1 行走/踢球训练代码），经 MuJoCo sim2sim 后用 booster_deploy 上真机（固件 1.7.2 满足 booster_deploy 的 ≥ v1.7.2 要求） | T6 | `rl-sim-deploy.md` §2.9、§7 | |
| T8 | **加时赛与点球大战**：Demo 1.7 对 v20 的 `game_phase` 1/2 已单独处理（标成 PENALTYSHOOT/OVERTIME，按正常比赛流程走，点球时 `penalty_kick_active`），但需要在 GC 里模拟加时和点球大战，实测行为 | V2、C4 | Demo 1.7 `src/brain/src/brain.cpp` `gameControlCallback` | 部分完成（代码已处理，待测） |
| T9 | **规避固件 1.7 上仍存在的已知问题**（除非升级到 1.8）：kSoccer 头部高速追球会 CAN 掉线 → 限制头部转速；kV1 踢球时里程计冻结 → 保持 kV2；进入 Custom 不会自动保持站立 → 必须预发保持帧 | V8、V9、V10 | `fw1.7-demo-v1.7.md` §2 | |
| T10 | 🔴 **队内通信降频**：Demo 1.7 每台 10 Hz 广播（`brain_communication.h:65` `TEAM_COMMUNICATION_INTERVAL_MS = 100`），3 台约 7 分钟就会耗尽 GC 的 12000 条额度，**GC 会把本队比分清零**。改成 ≥ 400 ms，或读 `msg.teams[i].message_budget` 动态限速（剩余额度 / 剩余时间 / 在场人数）；比赛中盯住 GC 界面的 Messages | C13 | `event-sop.md` §0 #3；GC7 `actions/team_message.rs:18-20` | |
| T11 | 🔴 **赛前联调清单**：本地起 GC 7.0.0-rc.3（选对网卡），3 台机器人上看 `game_controller.log` 里有 `version=20`；GC 界面 6 号区 3 台全部显示绿勾；走一遍 Initial→Ready→Set→Playing→定位球→Pickup→Finish | V2、T2 | `event-sop.md` §6.6、§9 | |
| T12 | **弄清 `start.sh` 的副作用**：`pkill -9 python3`、禁用 `booster-agent-manager`、mask apt。自己的 Python 程序不要和 Demo 同时跑；需要时改 `start.sh` | — | `event-sop.md` §0 #8 | |
| T13 | 手眼标定后同步配置：确认 `src/vision/config/vision.yaml` 已被标定程序改写 → `build.sh` → 重启；`/opt/booster/vision.yaml` 在运行时不生效 | — | `event-sop.md` §6.5 | |

## P0 安全（首次上机前）

| # | 问题 | 建议验证方法 | 出处 | 状态 |
|---|---|---|---|---|
| S1 | 控制进程断流/崩溃后机器人的行为（推断：保持最后一帧，无看门狗） | 吊架上，Custom 下发保持帧后 `kill -9` 控制进程，观察并记录 | `low-level-control.md` §4.6、§8#3 | |
| S2 | 遥控器软急停（L2+Back）在 Custom 模式下是否有效 | 吊架上，Custom 下按急停 | `low-level-control.md` §4.4、§8#10 | |
| S3 | 超出关节限位或力矩时，固件是否截断/进入 PROTECT；PROTECT 能否不断电退出 | 吊架上，低 kp 下给接近限位的目标；观察模式 | `low-level-control.md` §8#9；`k1-operations.md` §9#1 | |
| S4 | 机器人服务端 DDS domain 能否修改（多机隔离） | 询问官方；检查 `/opt/booster` 下的配置、fastdds.xml | `sdk-api.md` §9#7；`low-level-control.md` §6.5 | |
| S5 | CUSTOM → WALK 能否直接切换（手册说不行，booster_deploy 却这么做） | 在当前固件上用 `ChangeMode` 尝试并读取返回码；在此之前一律退到 PREP/DAMP | `low-level-control.md` §4.1；`rl-sim-deploy.md` §9#4 | |

## P1 底层控制参数

| # | 问题 | 建议验证方法 | 出处 | 状态 |
|---|---|---|---|---|
| L1 | `rt/low_state` 实际频率（推断约 500 Hz） | `ros2 topic hz /low_state` | `low-level-control.md` §8#1 | |
| L2 | 机器人端 QoS（low_state writer / joint_ctrl reader） | `ros2 topic info -v /low_state /joint_ctrl` | §8#2、#12 | |
| L3 | PD 在驱动板还是主控上执行、执行频率 | 阶跃响应测试；查 `reserve[1]` | §8#4 | |
| L4 | `MotorCmd.mode` 的含义（样例里有 0 和 0x0A） | 问官方；对比实验 | §8#5 | |
| L5 | SERIAL 模式下踝 kp 如何映射到两个曲柄电机 | 比较两种方式下的踝跟踪误差 | §8#8 | |
| L6 | 并联踝 A/B 与 Up/Down 电机的对应关系和符号 | DAMP 模式下手动掰动脚板，看两个电机角的变化 | `k1-hardware.md` §7#10 | |
| L7 | IMU 安装位姿与 acc 的定义 | 机器人静置在水平面上读取 acc/rpy | `k1-hardware.md` §7#6 | |
| L8 | 膝力矩上限（112 vs 60 N·m）、髋 roll 力矩（43 vs 76） | 在找到依据前按保守值限幅 | `k1-hardware.md` §7#1-2 | |
| L9 | 肘、踝限位口径不一致 | 读 `motor_state_serial`/`parallel` 实测标定 | `k1-hardware.md` §7#3-4 | |
| L10 | 整机质量（19.5 vs 19.666 kg） | 称重 | `k1-hardware.md` §7#9 | |

## P2 高层 SDK

| # | 问题 | 建议验证方法 | 出处 | 状态 |
|---|---|---|---|---|
| H1 | `ChannelFactory::Init` 第二个参数跨机时填本机 IP 还是机器人 IP | 开发机上两种都试，看能否收到 `rt/low_state` | `sdk-api.md` §9#1 | |
| H2 | `ChangeMode(kSoccer)` 的合法前置模式；比赛用 kWalking 还是 kSoccer | 在各模式下尝试并读返回码 | §9#2 | |
| H3 | `Shoot()` 在 K1 上是否可用 | 实测 | §9#2 | |
| H4 | `VisualKick` / `rt/kick_ball` 的发布频率要求与 `power` 的物理含义 | 不同 power 下量出球速 | §9#3 | |
| H5 | `Move` / `MoveCommand` 的速度上限、死区；429 的触发阈值 | 扫速度并用里程计测量 | §9#4 | |
| H6 | PREP 和 WALK 之间是否需要 `GetUp()` | 实测 | §9#5 | |
| H7 | `fall_down_recovery_state`、`current_planner_index`（1/2/8/10/20）的含义 | 问官方；记录话题值 | §9#6；`robocup-demo.md` §8 | |

## P3 robocup_demo 参赛前

| # | 问题 | 建议验证方法 | 出处 | 状态 |
|---|---|---|---|---|
| D1 | `/head_pose` 的参考系、是否含躯干倾角、频率，时间戳与图像是否同钟 | `ros2 topic echo`，对照 IMU | `robocup-demo.md` §8 | |
| D2 | 相机实际分辨率、帧率、内参主点 | `camera_info`；`ros2 topic hz` | `robocup-demo.md` §8；`k1-hardware.md` §7#7 | |
| D3 | brain 的 `vision.cam_pixel_*`/`cam_fov_*` 与实际相机是否一致（Demo 1.7 不再从 CameraInfo 取图像尺寸；讲义给的 d-robotics 视场角 69.4×42.5 与内参不符，内参对应约 104.7×93.7） | 球放在画面边缘，看头部追球是否过冲或过慢；对比两组值 | `event-sop.md` §6.4、§10 E4 | |
| D4 | TensorRT 推理耗时；Geek 版（非 Jetson）能否用 TRT | 在各型号上测量 | `robocup-demo.md` §8 | |
| D5 | 自动标定依赖（`booster-cli`、`/opt/booster/perception_info.yaml`、URDF）在本队机器人上是否齐全 | 按分支 README 检查 | `robocup-demo-branches.md` §5 | 不适用于 Demo 1.7（它用自带的 `calibration_node handeye`，不读 App 标定结果） |
| D6 | 哨声检测：各台 K1 麦克风阵列/声卡编号是否一致；赛场噪声下的误检率 | 现场录音回放测试 | `robocup-demo-branches.md` §2 | Demo 1.7 没有哨声检测；是否值得移植取决于 C12 |
| D7 | Demo 1.7 把 v20 罚则码原样存进 `data->penalty`，但替补判断用的是 HL 常量 `SUBSTITUTE`=14（v20 为 13，`brain_communication.cpp:320`）。影响：v20 下被换下的队友不会被跳过，但它的 `penalty != 0`，仍按受罚处理 | 在 GC 里做一次 Substitute，看队友状态和角色分配 | Demo 1.7 `include/RoboCupGameControlData.h:63`；GC7 `RoboCupGameControlData.h:63` | |
| D8 | 对方开球的 SET 阶段 brain 可能自行切到 PLAY（×100、+100 m 疑似调试遗留）→ Motion-in-Set 罚则风险 | 读代码并在 GC 模拟下测试 | `robocup-demo-branches.md` §2 | ✅ 2026-09-24 Demo 1.7 中不存在（`gc_game_state` 只由 GC 写入，`brain.cpp:2035`） |
| D10 | Demo 1.7 的 `setVelocity` 把小于 0.3 的非零速度抬到 0.3（`robot_client.cpp:195-200`，3v3 版是 0.05/0.08/0.05）：靠近目标点、对球微调时是否来回抖动 | 实机走到站位点、对球，观察是否振荡；必要时调小并测试不响应的下限 | `fw1.7-demo-v1.7.md` §3.2 | |
| D9 | LT+A/B/X/Y 与固件 Soccer Agent 的按键冲突；跑 demo 时应激活哪个 Agent | 实测 | `k1-operations.md` §9#6 | 并入 V12（Demo 1.7 的 `start.sh` 会禁用 `booster-agent-manager`） |

## P4 运维

| # | 问题 | 出处 | 状态 |
|---|---|---|---|
| O1 | 主机名、JetPack 版本、Geek 版 SoC 与 CUDA 是否可用 | `k1-operations.md` §9#3 | 1.7.2 包给 K1 Orin NX 装内核 5.15.148-rt-tegra（推断 JetPack 6.1/6.2），实机 `cat /etc/nv_tegra_release` 确认 |
| O2 | 板载服务/容器清单、系统日志原始路径 | §9#2 | |
| O3 | 低电量模式（For RoboCup）的配置位置 | §9#5 | |
| O4 | 恢复出厂后固件回退到哪个版本；`/opt/booster/vision.yaml` 是否被清除 | §9#8 | |
| O5 | booster_deploy 的最低固件（v1.4 还是 v1.7.2）；先统一升级到最新固件 | §9#7；`rl-sim-deploy.md` §9 | 固件 1.7.2 已满足两种说法（2026-09-24） |
| O6 | App 直连热点的 SSID/密码 | §9#4 | |

## 附：HSL 2026 规则本身的存疑点（仅在参考 HSL 规则时有用）

| # | 问题 | 出处 |
|---|---|---|
| R1 | 点球 READY 时长：规则正文 30 s，GC 参数 45 s | `robocup-rules.md` §14#2 |
| R2 | 被罚下的机器人放在哪一侧边线 | §14#10 |
| R3 | 超长队内通信包（> 512 B）按哪一级违规处理 | §8 |
