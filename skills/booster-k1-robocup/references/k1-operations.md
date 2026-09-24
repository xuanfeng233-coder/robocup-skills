# K1 产品手册与日常运维速查

> ⚠ **本队栈（2026-09-24 起）：固件 ≥ 1.7（主办方发放 `1.7.2.0-dev-yunlong-…` 升级包）+ 主办方 `K1_5v5_demo_1.7` + `sdk_release`（= SDK `d5d8f7a`）+ HSL GameController 7.0.0-rc.3。** 本文按最新 SDK 1.6.3 / 固件 1.8 撰写，在 1.7 上不同的地方用【fw1.7 #N】标出，完整说明见 `fw1.7-demo-v1.7.md` §4。**赛事现场的完整操作流程（部署、上场、裁判机）见 `event-sop.md`**，本文只保留通用运维知识。

> 适用对象：用 Booster K1 参加 RoboCup 人形组的开发/运维人员。
> 基线：官方文档快照，最新固件 **v1.8.0.9（2026-09-15）**、C++ SDK **v1.6.3**。
> 规则：所有结论都标注了来源；「⚠待实机验证」表示文档没写清或只是推断；「3P」表示第三方资料（非官方）。

## 0. 来源标记约定

| 标记 | 本地文件（`refs/...`） | 在线 URL |
| --- | --- | --- |
| `PM/<slug>` | `booster_docs/product-manual__k1__<section>__<slug>.md` | `https://docs.booster.tech/docs/product-manual/k1/<section>/<slug>/` |
| `CL/<ver>` | `booster_docs/changelog__v<ver>-*.md` | `https://docs.booster.tech/docs/changelog/...` |
| `DG/<path>` | `booster_docs/developer-guide__<path>.md` | `https://docs.booster.tech/docs/developer-guide/<path>/` |
| `RD` | `booster_docs/developer-guide__open-source__robocup-demo.md` | `.../developer-guide/open-source/robocup-demo/` |
| `README/<repo>` | `<repo>/README.md`（如 `robocup_demo`、`booster_deploy`） | GitHub BoosterRobotics |
| `IMG/<page>` | 官方页面截图（本地 md 没有，是从 docs-cdn 下载后查看的） | 见对应页面 |
| `3P/HSL` | Ruhrbot Devils 提交的 K1 硬件规格 PDF（HSL 2026） | `https://hsl.robocup.org/wp-content/uploads/2026/03/mid_Ruhrbot_Devils-specs-697e834b1f8bd.pdf` |

---

## 1. K1 规格速查（以官方 `PM/specifications` 为准）

| 项 | Geek | Education | Professional |
| --- | --- | --- | --- |
| 身高 / 重量 | 0.95 m / 约 19.5 kg | 同左 | 同左 |
| 自由度 | 22 = 头 2 + 臂 4×2 + 腿 6×2 | 同左 | 同左 |
| 步行 / 转向速度 | 1.1 m/s / 1.5 rad/s | 同左 | 同左 |
| 电池容量 | **2Ah** | 5Ah | 5Ah |
| 续航（1.1 m/s 下） | **20 min** | 1 h 10 min | 1 h 10 min |
| 充电时间 / 循环寿命 | ≤2 h / ≥500 次 | 同左 | 同左 |
| 处理器 | "High-performance ARM Processor"（`1×GoldP@3.2GHz + 4×Gold@2.8GHz + 3×Silver@2.0GHz`） | Jetson Orin NX 8GB（6 核 `A78AE@2GHz`） | Jetson AGX Orin 32GB（8 核 `A78AE@2.2GHz`） |
| AI 算力 | 48 TOPS (Dense) | 117 TOPS | 200 TOPS |
| 内存 / 存储 | 8GB / 128GB | 8GB / 512GB | 32GB / 512GB |
| 传感器 | 深度相机、麦克风阵列、扬声器×1 | 同左 | 同左 |
| 按键 / 指示灯 | 电源×1 + 交互键×3；RGB LED×1 | 同左 | 同左 |
| 声音告警 | 低电量告警、关节过热告警 | 同左 | 同左 |
| 通信 | 千兆以太网×1、Wi-Fi 6、蓝牙 5.2 | 同左 | 同左 |
| 行走噪声 / 环境 | ≤70 dB；-10~45 ℃；湿度 5~90%（无凝露） | 同左 | 同左 |

- 相机、IMU 与电池的补充信息（3P/HSL，非官方）：相机为 D-Robotics 广角双目，分辨率 544×488，FOV 105°×94°；IMU 为 HiPNUC HI13R4N；电池 13s 48V；执行器走 CAN 总线。⚠待实机验证。
- Geek 版官方只写了 "ARM Processor"。Agent 构建平台有 `real_jetson` 和 `real_qcom` 两种（`DG/agent-development__quick-start`），因此 Geek 版很可能是高通平台，**不能用 CUDA/TensorRT**。robocup_demo 在这种板子上要用 `build_no_cuda.sh` + ONNX。⚠待实机验证。

**关节 ID 与限位（度）**（`PM/specifications`；注意 Elbow、Hip Roll 的左右限位符号相反）

| ID | 关节 | Max / Min | ID | 关节 | Max / Min |
| --- | --- | --- | --- | --- | --- |
| 0 | Head Yaw | 59 / -59 | 11 | Left Hip Roll | 89 / -22 |
| 1 | Head Pitch | 49 / -19 | 12 | Left Hip Yaw | 59 / -59 |
| 2 | Left Shoulder Pitch | 69 / -169 | 13 | Left Knee | 133 / 0 |
| 3 | Left Shoulder Roll | 94 / -94 | 14 | Left Ankle Up | 38 / -17 |
| 4 | Left Shoulder Yaw | 109 / -109 | 15 | Left Ankle Down | 41 / -16 |
| 5 | Left Elbow | 39 / -129 | 16 | Right Hip Pitch | 128 / -170 |
| 6 | Right Shoulder Pitch | 69 / -169 | 17 | Right Hip Roll | 22 / -89 |
| 7 | Right Shoulder Roll | 94 / -94 | 18 | Right Hip Yaw | 59 / -59 |
| 8 | Right Shoulder Yaw | 109 / -109 | 19 | Right Knee | 133 / 0 |
| 9 | Right Elbow | 129 / -39 | 20 | Right Ankle Up | 38 / -17 |
| 10 | Left Hip Pitch | 128 / -170 | 21 | Right Ankle Down | 41 / -16 |

---

## 2. 开机、关机、充电、电池与安全

### 2.1 开机与关机（`PM/quick-start`、`PM/body-operations`）

| 步骤 | 操作 | 要点 |
| --- | --- | --- |
| 装电池 | 指示灯一面朝上插入电池仓；换电时指示灯朝向头部，听到卡扣"咔哒"一声 | `RD §7.1` |
| 开机 | 长按电源键 **3 s**，灯亮后松开。**按超过 6 s 会关机** | |
| 等待自检 | 约 1 min，听到提示音后才可遥控。**这段时间保持机器人静止**，IMU 在初始化 | SDK 在开机后 30–60 s 才可连（`DG/booster-os-python-sdk__faq-and-debugging-tools__faq`） |
| 上电后的默认模式 | 自动进入 **DAMP** | `IMG/modes` 状态图 |
| 关机 | 先按 L2+Start 进入 PREP，再把机器人**平放在地上**，然后长按电源键 3 s。身体变软后即可收纳 | |
| 再次开机 | 关机后**至少等 6 s** 再开机 | |

### 2.2 充电与电池管理

| 项 | 内容 | 来源 |
| --- | --- | --- |
| 充电指示 | 红灯表示充电中，绿灯表示充满（2Ah、5Ah 电池相同） | `PM/charging` |
| 升级前电量 | 必须 >50%，且机器人处于 DAMP 或 PREP | `PM/software-upgrade` |
| 赛前电量 | >50%，且"fully charged"；5v5 场景建议每台至少配 2 块电池 | `RD §2.1`（配多块电池属于建议） |
| 低电量行为 | 有声音告警；v1.6.0 起的提示会说明机器人**将停止运动** | `PM/specifications`、`CL/1.6.0` |
| 低电量模式开关 | v1.6.0 起可通过配置启用或关闭低电量模式（标注 "For RoboCup"）。配置文件位置文档没写 | `CL/1.6.0`，⚠待实机验证 |
| 程序读取电量 | Python：`robot.get_battery()`，其中 `is_low` 表示 <20%，`is_critical` 表示 <10%；也可用 `subscribe_battery`。C++：订阅 `rt/battery_state`，示例 `example/low_level/battery_state_subscriber.cpp` | `DG/booster-os-python-sdk__common-data-types__sensor-and-state-data__battery-state`、`booster_robotics_sdk` |
| 安全换电流程 | 移到空旷处 → STAND/PREP 稳住 → 平放或上支架 → 按住卡扣取出电池 → 插入满电电池 → 开机等提示音 → PREP → 放回场地 → **重启策略程序** | `RD §7.1–7.2` |

### 2.3 与开发调试相关的安全要点

| 主题 | 要点 | 来源 |
| --- | --- | --- |
| 场地 | 至少 2 m×2 m 的平整空地；全身舞蹈等大动作在橡胶、水泥、瓷砖地面做，**地毯阻力大，容易摔倒** | `PM/quick-start`、`PM/safety-warnings` |
| 吊架/保护绳 | 进入 **CUSTOM 模式**（腿部也由用户代码控制）时，全程用 hoist 吊架保护；先在 Webots/Isaac 仿真验证，改双足控制尤其要小心 | `PM/safety-warnings`、`PM/modes` |
| 支架 | 升级、`bdb` 重启服务、换电、掉电恢复时关节会**不出力**，必须先放上支架或平放在地上 | `PM/software-upgrade`、`PM/service-control`、`RD §1` |
| 不要抬起 | **WALK 模式下不要把机器人抬离地面**，否则它检测不到地面，可能乱踢伤人 | `PM/quick-start`、`PM/safety-warnings` |
| 接触 | 运动中身体只能碰把手（handle），不能碰其他部位 | `PM/quick-start` |
| 软急停 | 官方只给出**软急停**，遥控器、App、背部按键都能触发。常用组合：L2+Back（Xbox 为 LT+Back）或背部 **F1**（默认进入 DAMP），会使关节阻尼、机器人瘫倒；STAND 键进入 PREP，会立即挺直站立 | `PM/overview`、`PM/body-operations` |
| 硬件急停 | 文档没有提到独立的硬件急停。最后手段是长按电源键 3 s 断电，机器人会直接瘫倒 | ⚠待实机验证 |
| 失控保护 | 机器人进入不可控状态时会自动切到 DAMP；出现超限、摔倒等运行时问题时自动进入 **PROTECT**（关节状态与 DAMP 相同） | `PM/overview`、`PM/modes` |
| 摔倒处理 | ① 状态图上 PROTECT 只有「电源键 → 关机」这一条出口，也就是要**断电重启**（有没有其他退出方式 ⚠待实机验证）；② 进入 PROTECT 后先查日志找原因（`RD §1`）；③ 在 DAMP/PREP 下按 L2+UP（LT+UP）执行 Get Up；程序里可用 `get_up()`（Python）或 `GetUp()`/`GetUpWithMode()`（C++，固件 ≥v1.4.0.7）；④ 摔倒状态可读 `rt/fall_down`，或 Python 的 `FallDownState`（`normal/falling/fallen/getting_up`，另有 `recoverable` 字段） | `IMG/modes`、`PM/joystick-control`、`DG/cpp__rpc__motion`、`DG/booster-os-python-sdk__common-data-types__sensor-and-state-data__fall-down-state` |
| 退出自定义控制 | 程序退出前切回 PREP 以安全释放控制（booster_gym）；booster_deploy 的 `exit_mode` 默认值是 `walking`，可设为 `damping` | `README/booster_gym/deploy`、`README/booster_deploy` |

---

## 3. 运动模式与遥控器

### 3.1 模式说明（`PM/modes`；SDK 枚举见 `booster_robotics_sdk/include/booster/robot/common/robot_shared.hpp`）

| 模式 | SDK `RobotMode` | 行为 | 能否站立 | 能切到 |
| --- | --- | --- | --- | --- |
| DAMP | `kDamping=0` | 关节阻尼，不主动保持位置 | 不能，需要支撑 | 只能到 PREP 或 CUSTOM，不能直接进 WALK |
| PREP | `kPrepare=1` | 保持站姿，刚度大；只保持姿态，不做平衡恢复 | 能，但抗扰弱 | 任意模式 |
| WALK | `kWalking=2` | 全向行走、转向、踏步、转头、预设动作；抗扰强 | 能 | 任意模式（进入前必须先 PREP 并站稳在平地） |
| CUSTOM | `kCustom=3` | 全身关节（含腿）交给用户的 `rt/joint_ctrl` 指令。**固件 ≥v1.8.0.9 起，进入后先保持站立，直到收到有效的 `rt/joint_ctrl`**【fw1.7 #14】1.7 上不会自动保持站立，必须先预发保持帧 | 取决于用户代码 | 只能从 PREP/DAMP 进入，也只能回到 PREP/DAMP |
| PROTECT | — | 异常时自动进入，关节状态同 DAMP | 不能 | 见 2.3「摔倒处理」 |
| Soccer | `kSoccer=4` | 足球步态与动作，支持 K1/T1 | 能 | 手册没有描述，⚠待实机验证 |

- `rt/joint_ctrl` **只在 CUSTOM 模式下生效**，要先调用 `ChangeMode(kCustom)`（`DG/cpp__low-level-topics`）。
- C++ 典型启动顺序：`ChangeMode(kPrepare)` → `GetUp()` → `ChangeMode(kWalking)`（`DG/cpp__rpc__motion`）。

**模式切换路径**（`IMG/modes` 状态图，图中用 Xbox 键名；Booster 手柄上 LT=L2、RT=R2）

| 从 → 到 | 触发方式 |
| --- | --- |
| 上电 → DAMP | 自动 |
| DAMP → PREP / CUSTOM → PREP / WALK → PREP | LT+Start（背部 STAND 键也可进入 PREP） |
| PREP → DAMP / WALK → DAMP / CUSTOM → DAMP | LT+Back（背部 F1 默认也是 DAMP） |
| PREP → WALK | RT+A（背部 WALK 键也可） |
| DAMP/PREP → CUSTOM | 状态图里没有对应按键，只能用 SDK `ChangeMode(kCustom)`（booster_deploy 把它绑在 `X` 键上） |
| 任意 → PROTECT | 出错时自动进入；之后只能用电源键关机 |

背部 F1 键可以在 `/opt/booster/Gait/configs/K1/task_instruction.yaml` 里自定义（`PM/body-operations`）。

### 3.2 遥控器：通用操作（`PM/joystick-control`；**按键映射随软件版本变化，先查版本**）

| 功能 | Booster 手柄 | Xbox 手柄 | 前提 |
| --- | --- | --- | --- |
| 手柄开关机 | 长按 Home 5 s。开机时 LED1–4 全亮，开机完成后 LED1 常亮 | 必须用接收器模式，3 个灯常亮 | — |
| 手柄电量 | LED2 闪烁表示低电或充电中，常亮表示充满 | — | — |
| 进入 DAMP | L2 + Back | LT + Back | — |
| 进入 PREP | L2 + Start | LT + Start | — |
| 进入 WALK | R2 + A | RT + A | PREP 下 |
| 自动起身 Get Up | L2 + UP | LT + UP | DAMP/PREP 下（Booster/Soccer Agent）。起身后自动进入 WALK（`PM/quick-start`） |
| 平移 / 转向 / 转头 | 左摇杆 / 右摇杆 / 方向键 | 同左 | WALK 下 |
| 切到 Booster / Soccer / Hi Chat / Dance / Lion Dance Agent | L2+R2+ A / B / X / Y / UP | LT+RT+ A / B / X / Y / UP | Hi Chat 需要联网 |

### 3.3 遥控器：Soccer Agent 与比赛程序的按键

| 场景 | 按键（Booster；Xbox 把 L2→LT、L→LB） | 功能 | 来源 |
| --- | --- | --- | --- |
| 固件 Soccer Agent | L2+A / L2+B / L2+X / L2+Y | Track Ball / Chase Ball / Kick Ball（Shoot）/ Power Kick（WALK 下） | `PM/joystick-control`、`CL/1.6.1` |
| 固件 Soccer Agent | A / B；L+Y / L+B / L+UP / L+DOWN | 握手 / 挥手；庆祝动作 Siuuu / Arms Crossed / Point to Sky / Cradle Dance | `PM/agents` |
| robocup_demo `brain_node` | LT+A | 重定位，并进入 kSoccer 模式（必须先按这个） | `RD §6.2`；Demo 1.7：`src/brain/src/brain.cpp` `joystickCallback` 置 `control_state=2`，`behavior_trees/game.xml:26-33` 的 `RunOnce<RobocupWalk>` 调 `ChangeMode(kSoccer)` |
| robocup_demo `brain_node` | LT+B | 进入自动比赛策略，之后按 GameController 状态行动 | 同上 |
| robocup_demo `brain_node` | LT+X | 人工接管（取消 AI）。接管后机器人可能继续执行 AI 的最后一条速度指令，要轻推摇杆打断 | `RD §6.3` |
| robocup_demo `brain_node` | LT+Y | 在 striker 和 goal_keeper 之间切换角色（仅代码中有，比赛中别误按） | `brain.cpp` |
| robocup_demo `brain_node` | LT+方向键 上/下、左/右 | 在线微调 `vxFactor`、`yawOffset`（每次 ±0.01，只改内存，重启失效） | Demo 1.7 `brain.cpp` `joystickCallback` |
| robocup_demo `brain_node` | LB / RB（单按） | 辅助追球 / 辅助踢球（`assist_chase`/`assist_kick`，属于人工模式） | 同上 |
| robocup_demo `brain_node` | 任一摇杆 >0.1 | 置 `go_manual=true`，即人工覆盖 | `brain.cpp` |
| booster_deploy | X / A（键盘 x / r，空格清零速度，Ctrl+C 退出） | 进入 Custom 准备 / 启动 RL 策略 | `README/booster_deploy` |

⚠**按键冲突（待实机验证）**：固件 Soccer Agent 的 L2+A/B/X/Y 与 robocup_demo 的 LT+A/B/X/Y 是同一组物理按键。Demo 1.7 的 `scripts/start.sh:19` 会执行 `sudo systemctl disable --now booster-agent-manager.service`，推测就是为了避开这个冲突（副作用：该服务被**永久**禁用，赛后要手动 `enable --now`）。实机确认见 `issues.md` V12。

---

## 4. 连接机器人

### 4.1 网络速查

| 项 | 值 | 来源 |
| --- | --- | --- |
| 有线：机器人 IP | `192.168.10.102`（网口在背部按键旁） | `PM/connect-robot`、`IMG/body-operations` |
| 有线：开发机静态 IP | address `192.168.10.10`，netmask `255.255.255.0`，gateway `192.168.10.1` | `PM/connect-robot` |
| SSH 账号 | `booster` / 初始密码 `<机器人当前密码，请向队内获取>`；`sudo` 可用 | `PM/connect-robot`、`PM/software-upgrade` |
| 无线 | 先用 App 给机器人配 Wi-Fi，App 里会显示机器人 IP，再 `ssh booster@<IP>` | `PM/connect-robot` |
| App 直连模式 | 手机连机器人热点，适合没有网络的场地。热点 SSID/密码文档没写 | `PM/connect-robot`，⚠待实机验证 |
| App 发现设备 | 手机需开启蓝牙和定位权限 | `PM/connect-robot` |
| 主机名 | 官方截图的提示符是 `booster@tegra-ubuntu`（v1.0.6 时期的示例） | `IMG/check-version`，⚠待实机验证 |
| DDS | Fast DDS，与 ROS 2 DDS 兼容；默认 domain 0；`ChannelFactory::Instance()->Init(0, "<network_ip>")`，在机器人上运行时 IP 用 `127.0.0.1` | `DG/cpp__quick-start`、`DG/cpp__architecture` |
| 多机隔离 | 同一局域网有多台机器人时，给每台设不同的 `ROS_DOMAIN_ID`，避免话题串扰（Python 用 `BoosterRobot(domain_id=...)`） | `DG/booster-os-python-sdk__booster-robot-client-reference__initialization` |
| 机载 DDS profile | `FASTRTPS_DEFAULT_PROFILES_FILE=/opt/booster/BoosterRos2/fastdds_profile_udp_only.xml` | `robocup_demo/scripts/start.sh` |
| 比赛局域网示例 | 路由器（5GHz）统一分配 IP，GameController 机器与机器人在同一 LAN，UDP 广播可达 | `RD` 网络环境一节 |
| 本赛事连 Wi-Fi | 有线 SSH 登录后 `sudo nmtui` → Activate a connection → 在 Wi-Fi 栏选**和裁判机同一个** SSID；**极客版要选 `Wi-Fi (wlan0)`**；退出后 `ifconfig` 记下无线 IP，之后优先走无线 SSH | `event-sop.md` §4（讲义 p.8-10） |

- 开发机远程运行 SDK（不在机器人上）时，`<network_ip>` 应填开发机网卡 IP 还是机器人 IP，文档示例给的是 `192.168.10.102`，没说清楚。⚠待实机验证。
- `robocup_demo/configs/fastdds.xml` 的 interfaceWhiteList 只有 `127.0.0.1`、`192.168.10.101`、`192.168.10.102`。main 的脚本没有引用这个文件；Demo 1.7 的 `start.sh` 也不用它（用 `/opt/booster/BoosterRos2/fastdds_profile_udp_only.xml`），但 `start_brain.sh`、`start_game_controller.sh`、`assist.sh`、`chase.sh`、`calibrate.sh` 会用它。用这些脚本并走无线 IP 时，要先把无线 IP 加进白名单。

**比赛指定静态 IP**（`RD §8.5`，以 TC/OC 通知为准。例：GameController 为 `192.168.50.217`，机器人为 `192.168.<team>.<player>/16`）

```bash
nmcli device wifi connect "<SSID>"               # 先连上赛场 Wi-Fi
sudo nmtui                                        # Edit a connection → IPv4 CONFIGURATION: Manual
# Addresses: 192.168.66.87/16   Gateway: 192.168.50.1   勾选 Automatically connect
sudo nmcli connection down "<SSID>" && sudo nmcli connection up "<SSID>"
ip -4 address; ip route; ping -c 4 <GC_IP>
```

### 4.2 板载系统与目录

| 项 | 结论 | 依据 |
| --- | --- | --- |
| OS | Ubuntu **22.04** aarch64 | 固件包名 `...-global.22.04.aarch64-unsealed.single.run`（`PM/software-upgrade`）；SDK 支持 Ubuntu 22.04/24.04（`DG/cpp__quick-start`） |
| ROS | ROS 2 **Humble**，已预装 | `DG/open-source__booster-deploy`；robocup_demo 脚本里 `source /opt/ros/humble/setup.bash` |
| JetPack | robocup_demo 写的是 "support jetpack 6.2"，文档没有明确说明机器人自带的 JetPack 版本【fw1.7 #35】1.7.2 包为 "Booster K1 Orin NX" 机型装内核 5.15.148-rt-tegra（对应 L4T R36.4，即 JetPack 6.1/6.2，推断）；内置 Soccer Agent 按 JetPack 6.0/6.2 分别带了模型 | `README/robocup_demo`，⚠待实机验证 |
| Python | 3.10+，已预装 | `README/booster_deploy` |
| 时区 | 默认 UTC+8，导出日志时要换算 | `PM/logs` |
| `boosteros` | v1.7 固件未内置，需要 `pip install boosteros`；文档称 v1.8 会内置 | `DG/agent-development__quick-start` |

| 路径 | 用途 | 来源 |
| --- | --- | --- |
| `/opt/booster/version.txt` | 固件版本信息 | `PM/check-version` |
| `/opt/booster/env/activate` | `bdb` 等工具的环境，每次登录需 `source` 一次 | `PM/service-control` |
| `/opt/booster/Gait/configs/K1/task_instruction.yaml` | 背部 F1 键功能配置 | `PM/body-operations` |
| `/opt/booster/BoosterRos2Interface/install/setup.bash` | `booster_interface` ROS 2 消息包 | `README/booster_deploy` |
| `/opt/booster/BoosterRos2/fastdds_profile_udp_only.xml` | 仅 UDP 的 FastDDS profile | `robocup_demo/scripts/start.sh` |
| `/opt/booster/vision.yaml` | 系统级视觉标定文件，由 `calibration_node` 写入。`RD §4.1` 称它优先级高于 demo 的 `src/vision/config/vision.yaml`，但 **main 和 Demo 1.7 的 `start.sh` 运行时都不读它**（没有传 `vision_config_path`），实际生效的是 `install/vision/share/vision/config/vision.yaml`（见 `event-sop.md` §0 #4）。机器人被复用时可能被误删【fw1.7 #39】固件内置的 Soccer Agent 1.0.2 会读它（launch 传 `vision_config_path='/opt/booster'`），Demo 1.7 不读。 | `RD §4.1`；Demo 1.7 `scripts/start.sh:33` |
| `/opt/booster/RTCCli/*.toml` | 旧版 Hi Chat 配置，v1.7 起不再加载 | `PM/dialog-config` |
| `/etc/systemd/system/booster-daemon.service` | 升级时创建的 systemd 服务（1.7.2 包里是指向 `/opt/booster/config/systemd/` 的软链接） | `IMG/software-upgrade`（升级输出截图） |
| `/home/booster/Downloads` | 放升级包的示例目录（主办方流程用 `~/Workspace`，也可以） | `PM/software-upgrade` |
| `/home/booster/Documents/recovery` | 恢复出厂用的 `.run` 包 | `PM/restore-factory-settings` |
| `~/Workspace/` | 官方 demo 部署目录（约定俗成，不是系统目录） | `RD §2.3` |

---

## 5. 服务控制与日志（`PM/service-control`、`PM/logs`）

| 目的 | 命令或操作 | 说明 |
| --- | --- | --- |
| 准备环境 | `source /opt/booster/env/activate` | 每次登录后执行一次 |
| 启动全部机器人服务 | `bdb container boot-all` | |
| 停止全部机器人服务 | `bdb container kill-all` | 运控停止后关节不出力，**先上支架或平放** |
| 重启服务 | `bdb container kill-all && bdb container boot-all` | 相当于"完整重启固件" |
| App 重启 | 控制页 → Settings → Restart Robot | |
| 版本与 SDK | `booster-cli version`（RD 示例输出为 `Firmware: 1.6.x` / `SDK: 1.3.6`） | `RD §2.2` |
| 服务状态 | `booster-cli launch -c status/start/stop/restart` | **3P**（SVRC 设置指南），官方 K1 页没有，⚠待实机验证 |

- **跑自定义程序时不要关掉默认服务。** 官方做法是保留系统服务，用 SDK `ChangeMode(kCustom)` 接管关节，再发布 `rt/joint_ctrl`（`DG/cpp__low-level-topics`、`README/booster_deploy`）。`kill-all` 会把 SDK 依赖的 RPC/DDS 服务一起停掉，这一点是从"完整重启固件"推断的，⚠待实机验证。
- 只要上半身时，在 WALK 下开启上半身自定义控制：Python 用 `upper_body_control(True)` 加 `set_joints()` 发送前 10 个上半身关节，C++ 用 `UpperBodyCustomControl`（≥v1.4.0.7）。这时腿部仍由系统控制行走（`DG/booster-os-python-sdk__booster-robot-client-reference__motion-control-apis__upper-body-control`、`DG/cpp__rpc__motion`）。
- 板载有哪些系统服务、容器，官方文档**没有列出**。已知的只有 `bdb container`（容器化进程管理）、`booster-daemon.service`，以及 v1.6.0 上线的"process management framework"（`CL/1.6.0`）。可以在实机上用 `bdb container --help`、`systemctl status booster-daemon` 核实。⚠待实机验证。

#### 日志导出

```bash
# 在机器人上执行。时间格式 YYYYMMDD-HHMMSS，时区 UTC+8；不写 -et 时默认为 30000101-000000
booster-cli log -st 20260924-120800 -et 20260924-120820 -o /home/booster/Documents/issue.zip
# 在开发机上执行
scp booster@192.168.10.102:/home/booster/Documents/issue.zip ~/Downloads
```

- App 方式：Settings → Log Upload，选择时间范围，约 5–10 分钟，期间保持开机和联网。App 日志和机器人日志会一起上传。
- 发给技术支持时附上现象、发生时间和复现步骤。海外用户可用 WeTransfer 发到 `support@boosterobotics.com`。
- 系统日志的原始存放路径文档没写，⚠待实机验证。robocup_demo 的日志在工程根目录：`brain.log`、`vision.log`、`game_controller.log`（`nohup` 重定向产生）。

---

## 6. 固件版本：查看、升级与开发相关变更

### 6.1 查看版本

| 方式 | 操作 |
| --- | --- |
| App | Settings → About |
| 终端 | `cat /opt/booster/version.txt`，输出含 `Version: v1.x.x.x-release`、`Branch`、`Commit ID`、`Install time`（`IMG/check-version`）【fw1.7 #34】这个文件是**追加写入**的，每次安装加一段（以 `------------------` 分隔），要看**最后一段**：`tail -n 5 /opt/booster/version.txt`。本队 dev 包写的是 `Version: 1.7.2.0-dev-yunlong-…`（没有 `v`，也不是 `release`） |
| 终端 | `booster-cli version`（`RD`） |
| SDK | Python 用 `robot.robot_info`（含固件版本）；C++ 用 `GetRobotInfo`（≥v1.3.1.1） |

### 6.2 升级流程（`PM/software-upgrade`）

升级前准备：机器人进入 DAMP，或平放、上支架；电量 >50%；网络和终端连接稳定；确认升级包是 K1 的；**备份改过的配置和 `/opt/booster/vision.yaml`**；升级过程中不能断电。【fw1.7 #33】1.7.2 dev 包还会：覆盖 `/opt/booster/configs/*`（备份在 `configs/.config/<时间戳>/`）；**覆盖 `/opt/booster/Gait/configs`（含 F1 键的 `task_instruction.yaml`），不备份**；**清空蓝牙配对**（手柄要重新配对）；stop + disable hostapd 和 dnsmasq；更新内核并可能**自动重启**；不检查版本，也不阻止降级。

| 方式 | 步骤 |
| --- | --- |
| App | 机器人设置 → Firmware Update |
| `.run` 包 | `scp <pkg>.run booster@192.168.10.102:~/Workspace/`（或 `~/Downloads/`）→ 在机器人上 `chmod +x <pkg>.run` →（可选）`sh <pkg>.run --check` 只做 MD5 校验 → **联网状态下** `sudo ./<pkg>.run` → 扶好或支撑机器人（运控会停止）→ 如果自动重启就等它回来 → `tail -n 5 /opt/booster/version.txt` 复查。【fw1.7 #31】这类包**不能离线安装**：`install.sh` 会 `apt update` 和 `pip install`，失败直接退出（`fw1.7-demo-v1.7.md` §2.1） |
| **本队目标包** | 主办方发放 `1.7.2.0-dev-yunlong-1-7-2026-06-01-hM193-00464-2026-08-18.22.04.aarch64.single.run`（仓库根目录，3.26 GB，解压需要 `/tmp` 有约 6 GB 空间）。**dev 渠道**、国内版（china-single）、构建号 00464，2026-08-18 构建。行为细节见 `fw1.7-demo-v1.7.md` §2.1 |
| 在线命令 | `booster-cli upgrade`（≥v1.0.5.0）。输出 `Latest version installed, please enjoy booster robot !!!` 即表示成功（`IMG/software-upgrade`）【fw1.7 #32】App OTA 和 `booster-cli upgrade` 会装最新正式版（目前 1.8.0.9），讲义也允许；但**全队必须一致**：要么全用 1.7.2 dev 包，要么全用 1.8 |
| 最新包 | v1.8.0.9：`https://boosterobotics.s3.ap-southeast-1.amazonaws.com/ota_single/5dc1e2ab/1.8.0.9-release-02011-2026-09-14-global.22.04.aarch64-unsealed.single.run` |
| 历史版本 | 飞书 wiki：K1 Version History `https://booster.feishu.cn/wiki/JmYFwY6rKioHCckG3BTcJKL3ntd`（需要登录） |
| pip 下载慢 | `sudo su` → `pip config set global.index-url https://pypi.mirrors.ustc.edu.cn/simple` → 重新运行 `.run`（本队的国内版安装器已把 pip 源写死为阿里云，一般用不到） |
| apt update 失败 | `wget http://fishros.com/install -O fishros && . fishros`，依次选 [5] 一键换源 → [1] 仅换系统源 → [1] 添加 ROS/ROS2 源 |

### 6.3 版本兼容性要点

| 组件 | 固件要求 | 来源 |
| --- | --- | --- |
| BoosterOS Python SDK `boosteros` | ≥ v1.7（Python ≥3.10） | `DG/booster-os-python-sdk__sdk-overview` |
| Python Agent 安装 | ≥ v1.7（v1.7 需要手动 `pip install boosteros`） | `DG/agent-development__quick-start` |
| C++ SDK v1.6.3 新接口（LUI、`ResetOdometryTo`、`GetTrainedTrajStatus`） | ≥ v1.8.0.9【fw1.7 #36】本队 1.7.2 上不可用 | `DG/cpp__changelog` |
| booster_deploy | 官方文档写 ≥ v1.4，仓库 README 写 ≥ v1.7.2，**两处不一致，按高的来**【fw1.7 #36】1.7.2 两种说法都满足 | `DG/open-source__booster-deploy`、`README/booster_deploy` |
| robocup_demo `RLVisionKick.enableAutoVisualKick` | ≥ 1.5.2（仅 K1） | `README/robocup_demo` |
| K1 5v5 Demo v1.6 | 固件 1.6 + SDK 1.3.6，**不匹配会导致编译失败或崩溃** | `RD` 软件要求 |
| **K1_5v5_demo_1.7（本队）** | 固件 ≥ 1.7（讲义：1.8 也可以）+ `sdk_release`（= SDK `d5d8f7a`）。`get_up_version: kV2` 要求 ≥ 1.7.1。Demo 发往 `LocoApiTopicReq` 的请求由固件自带的 `booster_rpc_bridge` 接收（1.7.2 包里有） | `event-sop.md` §1；`fw1.7-demo-v1.7.md` §2.2 |
| 关键 RPC 的最低固件 | `VisualKick` ≥1.5.2.1；`ResetOdometry`、`EnterWBCGait` ≥1.5.0.9；`SwitchGait` ≥1.6.0.10；`GetUpWithMode`、`UpperBodyCustomControl` ≥1.4.0.7 | `DG/cpp__rpc__motion` |

### 6.4 Changelog 中与开发相关的变更（按版本）

| 版本（日期） | 开发相关变更 |
| --- | --- |
| **1.6.0**（2026-04-18） | 上线 K1 半身行走/跑步步态；Agent 切换从 4–10 s 缩短到 1–2 s；Agent 支持参数配置；支持自研遥控器；上线进程管理框架；通信延迟从 11 ms 降到 9 ms；自主踢球改为 power kick；新增音频服务与 SDK API；SDK 新增舞狮接口；关节反馈滤波可配置开关；**低电量模式可配置开关（For RoboCup）**；**统一不同相机型号的通信话题**；修复 `/robot_description` 缺 mesh、ROS TF 不连续、相机 ROS 消息缺 frame、步态与踢球切换时需抬头、开启运控数据录制后运控崩溃 |
| **1.6.1**（2026-04-29） | Soccer Agent：Power Kick 为 L2+Y，Shoot 为 L2+X；Android App 支持群控；修复手机 AP 直连长时间异常断连后 OOM 导致摔倒；关闭 `vision_log` |
| 1.6.2（2026-05-13，仅 App） | iOS 群控，需要固件 ≥1.6.1 |
| **1.7.1**（2026-07-28） | App 支持 K1 手眼标定；K1 新增敏捷行走步态和稳定起身，并提供 API；**里程计、IMU、电机发布标准 ROS 2 消息**；新增设备元数据 API（关节、IMU、相机）；降低算法控制链路延迟；修复 IMU 偶发异常数据导致摔倒、教育版 Wi-Fi 偶发断连、灯带青色且无法启动；Hi Chat 改为使用 HICHAT HUB |
| **1.7.2**（2026-08-04） | 优化 K1 Get Up 稳定性【fw1.7 #37】**本队目标版本**；主办方的 dev 包 2026-08-18 构建，比 GA 晚两周，是否含回合修复无法核实。下一行 1.8.0 的各项在 1.7.2 上都没有 |
| **1.8.0 / v1.8.0.9**（2026-09-15） | **进入 Custom Mode 后默认保持站立**，直到收到有效的 `rt/joint_ctrl`；LUI 新增文本转音频文件、音频文件转文本接口；ASR/TTS 支持会话隔离；里程计可重置为指定值（`ResetOdometryTo`）；新增动作状态回调；修复 Visual Kick V1 模式下里程计不更新、**K1 足球模式头部高速追球时 CAN 掉线**、调用 `MoveHandEndEffectorV2` 后头部控制失效 |

---

## 7. 故障排查与恢复出厂

| 症状 | 排查与处理 | 来源 |
| --- | --- | --- |
| SSH 连不上 | 依次确认：已开机且听到提示音 → 开发机与机器人在同一网段（有线用 `192.168.10.102`，开发机为 `192.168.10.10/24`）→ 无线 IP 以 App 显示为准 → 用户 `booster`、密码 `<机器人当前密码，请向队内获取>` | `RD §8.1` |
| SDK 报 `LocoClientInitError` 或 `WaitForService` 超时 | 开机后等 30–60 s；调大 `timeout`；检查 DDS domain 和 IP | `DG/booster-os-python-sdk__faq-and-debugging-tools__faq` |
| `get_xxx()` 报 `DataNotReadyError` | 调大 timeout；部分数据通道在虚拟机器人或直连电源时不可用 | 同上 |
| `set_velocity` 后不动 | 没在运动模式，或速度太小（建议从 0.1 起逐步加） | 同上 |
| 发布 `rt/joint_ctrl` 无效 | 没有 `ChangeMode(kCustom)`；关节数量或索引错误 | `DG/cpp__low-level-topics` |
| 机器人突然瘫软 | 可能进入了 PROTECT（超限、摔倒）。先导出日志找原因，再断电重启 | `PM/modes`、`RD §1` |
| 开机失败，灯带青色 | 1.7.1 已修复，升级固件 | `CL/1.7.1` |
| 教育版 Wi-Fi 偶发断连 | 1.7.1 已修复 | `CL/1.7.1` |
| 头部追球时运控异常或 CAN 掉线 | 1.8.0 已修复【fw1.7 #38】1.7.2 上仍存在：限制头部角速度和指令频率，赛前做 ≥ 10 分钟追球压力测试（`issues.md` V8），或全队升级到 1.8 | `CL/1.8.0` |
| 改了 demo 配置不生效 | 改完要重新 `./scripts/build.sh`，再 `stop.sh` + `start.sh`；确认改的是机器人上的文件 | `RD §3.5/§8.1` |
| 比赛状态在 ready/initial/set/playing 之间乱跳 | 局域网里有多台 GameController 在广播；开启白名单并填对 GC IP | `RD §5.6/§8.3` |
| 收不到 GameController | 同一 LAN、GC 选对网卡、GC IP 与白名单一致；robocup_demo 在 UDP **3838** 端口监听 GC 广播（回传端口 3939） | `RD §8.3`、`robocup_demo/src/game_controller/launch/launch.py` |
| 找不到球、头一直转、测距不准 | 检查 `vision.log`、`/opt/booster/vision.yaml` 与相机是否匹配、话题是否为 `/boostercamera/head/rgb`（深度为 `/boostercamera/head/depth`）、模型路径是否正确；重做手眼标定 | `RD §4/§8.2` |
| Hi Chat 无响应 | 需要联网；自定义人设可能与语音指令冲突 | `PM/voice-interaction__intro` |
| 升级失败 | 见 6.2 的 pip 换源和 fishros；仍失败就导出日志联系支持 | `PM/software-upgrade` |

**恢复出厂**（`PM/restore-factory-settings`）：只在"改配置后无法回滚"、技术支持建议、或需要回到接近出厂状态时使用。

```bash
# 先备份：自定义配置、日志、~/Workspace、/opt/booster/vision.yaml；机器人放稳，电源和网络保持稳定，全程不断电
cd /home/booster/Documents/recovery
sudo ./v1.0.1.30-release-single-aarch64.run   # 文件名以目录中与设备匹配的那个为准
```

完成后按提示重启 → 确认基础服务和网络恢复 → 重新配置网络、App、语音和自定义参数。恢复包版本（示例为 v1.0.1.30）很可能比当前固件旧，恢复后通常需要**再升级到目标固件**（推断，⚠待实机验证）。

**远程支持**（`PM/remote-support`）：准备好设备状态、现象、时间、日志；可以让开发机 SSH 到机器人后开远程桌面给支持人员，也可以在机器人上装向日葵（`https://sunlogin.oray.com/download`，个人版），把 Device ID 和一次性密码提供给支持。

---

## 8. 比赛落地

### 8.1 赛前检查清单（依据 `RD §2.1/§6.1`、`PM/*`，加以整理和补充）

| # | 类别 | 检查项 | 通过标准 |
| --- | --- | --- | --- |
| 1 | 外观 | 关节、相机、控制器无可见损伤；把手、外壳紧固 | 目视 |
| 2 | 电池 | 每台电池 >50%（正式上场建议满电）；备用电池已充满；充电器就位 | App/`get_battery()` |
| 3 | 手柄 | 手柄已充电并与本机配对；Xbox 手柄处于接收器模式、3 灯常亮 | L2+Start 有响应 |
| 4 | 版本 | 全队固件与 SDK 版本一致，且与代码要求匹配（见 6.3） | `cat /opt/booster/version.txt`【fw1.7 #34】看最后一段，全队的 Version 和 Commit ID 一致 |
| 5 | 开机自检 | 开机时保持静止约 1 min；能进 PREP 并站稳；RT+A 进 WALK 能走；相机画面正常 | `RD §2.1` |
| 6 | 网络 | 按 TC/OC 要求配置 Wi-Fi 和静态 IP；`ping <GC_IP>` 通；5GHz 路由 | `RD §8.5` |
| 7 | DDS 隔离 | 场上多台机器人时各自 domain 不冲突，或确认不会跨机串扰 | ⚠待实机验证 |
| 8 | 队伍配置 | `team_id` 与 GC 一致；`player_id` 队内唯一；`number_of_players`、`field_type`、GC IP 填写正确 | `RD §3.2–3.3` |
| 9 | GC 白名单 | `launch.py` 中 `enable_ip_white_list: True`，`ip_white_list` 含 GC 的 IPv4 地址 | `RD §3.3` |
| 10 | 通信合规 | 新规则禁止机器人之间单播，并限制包大小，需要修改 `brain_communication.cpp` | `README/robocup_demo` NOTICE |
| 11 | 视觉 | `/opt/booster/vision.yaml` 存在且与相机匹配；必要时现场重做手眼标定（标定板距机器人 0.8–1 m） | `RD §4` |
| 12 | 构建 | 在机器人上最新 `build.sh` 成功；改完配置后已重新 build | `RD §3.5` |
| 13 | 运行 | `start.sh` 后 `brain.log` 无报错、`vision.log` 持续刷新、`game_controller.log` 能收到状态 | `RD §3.5/§6.1` |
| 14 | 上场流程 | 启动 demo → PREP → 放到场边 → RT+A → LT+A（等定位完成）→ LT+B；紧急时 LT+X 接管 | `RD §6.2–6.3` |
| 15 | 安全 | 场地无无关人员；不在 WALK 下抬机器人；换电后要重启策略 | `PM/safety-warnings`、`RD §7` |
| 16 | 备份 | 每台机器人的 `config.yaml`、`vision.yaml` 已备份到开发机 | 建议 |

### 8.2 开发机与机器人的部署流程

**官方路线是在机器人上原生编译。** RD 和 robocup_demo 的做法都是把源码传到机器人，在机器人上用 `colcon build` 编译。C++ SDK 自带 `lib/aarch64` 与 `lib/x86_64` 预编译库，`install.sh` 按 `uname -m` 选择（`booster_robotics_sdk/install.sh`）。**官方没有交叉编译文档**，交叉编译可行性 ⚠待实机验证。另外 `.engine`（TensorRT）模型与目标 GPU 和 TensorRT 版本绑定，应在机器人上生成或使用官方提供的版本（推断）。

| 阶段 | 开发机 | 机器人 |
| --- | --- | --- |
| 1. 仿真验证 | Booster Studio、Webots、Isaac、MuJoCo（`deploy.py --mujoco`） | — |
| 2. 同步代码 | `scp -r` 或 `rsync`（见下方示例） | — |
| 3. 依赖 | — | `sudo ./install.sh`（C++ SDK）；Python 用 venv + `pip install -r requirements.txt`；`sudo apt-get install ros-humble-backward-ros`（robocup_demo） |
| 4. 编译 | — | `source /opt/ros/humble/setup.bash && ./scripts/build.sh`（`colcon build --symlink-install --base-paths src`）；没有 CUDA 时用 `build_no_cuda.sh` |
| 5. 运行 | — | `./scripts/start.sh`（先 `stop.sh`，再 `nohup ros2 launch` 启动 vision、brain、game_controller） |
| 6. 观察 | `ssh ... tail -f brain.log` | 日志在工程根目录 |
| 7. 停止 | — | `./scripts/stop.sh`，之后视情况进入 PREP 或 DAMP |

```bash
# 开发机 → 机器人（有线示例）。rsync 属通用做法、文档没写，确认机器人已装 rsync（⚠待实机验证）
rsync -avz --delete --exclude build/ --exclude install/ --exclude log/ --exclude '*.log' \
      ./robocup_demo/ booster@192.168.10.102:~/Workspace/robocup_demo/
# 或者按官方做法：scp 压缩包过去再解压
scp K1_5v5_Demo_v1.6.zip booster@192.168.10.102:~/Workspace/ && ssh booster@192.168.10.102 'cd ~/Workspace && unzip -o K1_5v5_Demo_v1.6.zip'
# 在机器人上编译并运行
ssh booster@192.168.10.102
cd ~/Workspace/robocup_demo && ./scripts/build.sh && ./scripts/start.sh && tail -f brain.log
```

- **不要把 `build/`、`install/` 从开发机（x86_64）同步到机器人**，架构不同，而且 `--symlink-install` 生成的软链接指向开发机上的绝对路径。
- 从 Windows 拷来的脚本如果报 `/bin/bash^M`，执行 `find . -type f -print0 | xargs -0 sed -i 's/\r$//'`（`README/robocup_demo`）。
- booster_deploy 实机运行：`source .venv/bin/activate` → `source /opt/booster/BoosterRos2Interface/install/setup.bash` → `python3 scripts/deploy.py --task <TASK>`（`README/booster_deploy`）。
- 开机自启动策略程序（systemd 或 Agent）文档没有给出比赛用的做法。换电后要手动执行 `start.sh`（`RD §7.2`）。⚠待实机验证。

---

## 9. 存疑点汇总（⚠待实机验证）

1. PROTECT 模式能否不断电退出（状态图上只有电源键关机一条出口）。
2. 板载系统服务、容器清单与日志原始路径；`booster-cli launch -c ...`（第三方资料）在 K1 上是否存在。
3. 主机名（截图为 `tegra-ubuntu`）、JetPack 具体版本、Geek 版的 SoC 和 CUDA 可用性。
4. App 直连热点的 SSID/密码；远程运行 SDK 时 `ChannelFactory::Init` 的 IP 参数语义。
5. "低电量模式（For RoboCup）"的配置文件位置和键名。
6. 跑 robocup_demo 时应激活哪个 Agent，LT+A/B/X/Y 是否与固件 Soccer Agent 冲突。
7. booster_deploy 的最低固件要求：文档写 v1.4，README 写 v1.7.2。（本队固件 1.7.2，两者都满足，可关闭）
8. 恢复出厂后固件回退到哪个版本；`/opt/booster/vision.yaml` 是否会被清除（升级安装器既不创建也不删除它，已从 1.7.2 包的脚本确认）。
