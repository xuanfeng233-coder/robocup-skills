# K1 硬件、关节与机构参考（面向底层控制）

> 读者：绕过高层 SDK、直接做关节控制、自研步态或部署 RL 策略的开发者。
> 路径约定：除 URL 外，文件路径都相对于 `refs/`；`:Lnn` 表示行号，`:La-b` 表示行区间。
> 标记约定：`⚠待实机验证` 表示源码或文档没写清，或者只是推断；`[计算]` 表示我用 URDF 自己算出的数（方法见 §5.3）；`3P` 表示第三方资料，不是官方来源。
> 相关文件：运维、网络、模式按键见 `k1-operations.md`；DDS 通信、控制律、Custom 流程和 RL 部署见 `low-level-control.md`。

来源缩写：

| 缩写 | 本地位置 |
| --- | --- |
| `SDK` | `booster_robotics_sdk/`（C++ SDK，头文件 + 静态库） |
| `AST` | `booster_assets/robots/K1/`（`K1_22dof.urdf`、`K1_22dof.xml`（串联踝 MJCF）、`K1_22dof_parallel.xml`（并联踝 MJCF）、`K1_locomotion.urdf`） |
| `DEP` | `booster_deploy/`（官方 RL 部署框架，K1 实机使用 ROS 2） |
| `GYM` | `booster_gym/deploy/`（旧版部署，**只有 T1 配置**，但它的流程和技巧同样适用于 K1） |
| `TRN` | `booster_train/source/booster_train/booster_train/`（Isaac Lab 训练，包含 K1 电机模型） |
| `DOC` | `booster_docs/`（官方文档快照） |
| `R2IF` | `booster_robotics_sdk_ros2/booster_ros2_interface/`（ROS 2 msg 定义） |
| `RCD` | `robocup_demo/` |
| `3P/HSL` | Ruhrbot Devils 提交的 K1 硬件规格 PDF（HSL 2026）：https://hsl.robocup.org/wp-content/uploads/2026/03/mid_Ruhrbot_Devils-specs-697e834b1f8bd.pdf |
| `WEB/K1` | 官网 https://www.booster.tech/booster-k1/ （2026-09 抓取） |

---

## 0. 速览：底层开发最常用的数

| 项 | 值 | 来源 |
| --- | --- | --- |
| 底层指令数组长度 | **22**，对应 `kJointCntK1`。不要用 `kJointCnt`，它是 T1 的 23；数组布局错了会驱动错误的执行器，或者整帧被拒收 | `SDK/include/booster/robot/b1/b1_api_const.hpp:14-24,212-214` |
| 关节顺序 | 头 2 → 左臂 4 → 右臂 4 → 左腿 6 → 右腿 6（见 §3.1） | 同上 `:151-174` |
| 腿部运动链 | trunk → hip_pitch → hip_roll → hip_yaw → knee → ankle_pitch → ankle_roll（**髋的顺序是 P-R-Y，与常见的 Y-R-P 不同**） | `AST/K1_22dof.urdf:684-986` |
| 踝关节 | **并联**，由上下两个曲柄电机（CrankUp/CrankDown）经连杆驱动；`SERIAL` 模式下固件把它等效成 ankle_pitch/ankle_roll | §4.5 |
| 大腿 / 小腿长 | 0.1915 m / 0.2452 m | [计算] 由 `K1_22dof.urdf` 关节偏置得出 |
| 两髋 pitch 轴间距 | 0.192 m（±0.096） | `K1_22dof.urdf:684` 附近 origin |
| 踝轴到脚底 | 0.038 m；脚底碰撞盒 0.18 m × 0.07 m，盒中心在踝轴前方 0.026 m | `AST/K1_22dof.xml:143` |
| 零位时 trunk 原点离地 | 0.552 m | [计算] |
| URDF 总质量 | 19.666 kg（规格书写约 19.5 kg） | [计算] / `DOC/product-manual__k1__getting-started__specifications.md:14` |
| 质心高度 | 零位 0.481 m；k1_walk 默认姿态 0.464 m | [计算] |
| IMU | HiPNUC **HI13R4N** | `SDK/include/booster/idl/b1/ImuInfo.h:92`、`DOC/...sensor-info.md:105`、`3P/HSL` |
| 膝关节力矩上限 | URDF 和电机模型 E6416 均为 112 N·m；官网写 "Max Peak Torque 60N·m" | §2 |
| 常见控制频率 | 策略 50 Hz；底层指令 50–500 Hz（详见 `low-level-control.md`） | `DEP/.../controller_cfg.py:102`、`GYM/configs/T1.yaml:2,52` |

---

## 1. 整机规格

| 项 | 值 | 来源 |
| --- | --- | --- |
| 身高 | 0.95 m | `DOC/product-manual__k1__getting-started__specifications.md:13` |
| 重量 | 约 19.5 kg；URDF 各连杆质量合计 19.666 kg；并联踝 MJCF 另加 4 个驱动臂和 4 根连杆，共 0.20 kg | 同上 `:14`；[计算] `AST/K1_22dof_parallel.xml:143,148,155,160` |
| 自由度 | 22：头 2（yaw、pitch）、单臂 4、单腿 6 | 同上 `:15-18`；`DOC/product-manual__k1__getting-started__overview.md` |
| 行走 / 转向速度 | 1.1 m/s / 1.5 rad/s | 同上 `:19-20` |
| 电池 | Geek 2Ah，Education/Pro 5Ah；续航 20 min / 1 h 10 min（1.1 m/s 下）；充电 ≤2 h | 同上 `:21-24` |
| 电池电压 | 13 串，标称 48 V | `3P/HSL` ⚠待实机验证 |
| 计算平台 | Geek：ARM 处理器，48 TOPS。Education：Jetson Orin NX 8GB，117 TOPS。Professional：Jetson AGX Orin 32GB，200 TOPS | 同上 `:25,75-119` |
| 存储 | 128 GB（Geek）/ 512 GB | 同上 `:101-104` |
| 执行器总线 | CAN | `3P/HSL` ⚠待实机验证 |
| 电机通信频率 | `MotorState.reserve[1]` 字段的说明是「当前电机通信频率（范围 0–800）」 | `R2IF/msg/MotorState.msg:10` |
| IMU | 9 轴，型号 HI13R4N（`IMU_MODEL_HI13R4N`） | `SDK/include/booster/idl/b1/ImuInfo.h:92`、`3P/HSL` |
| 相机 | 规格书只写 "Depth Camera"。3P 资料写的是 D-Robotics 广角双目，544×488，FOV 105°×94°。传感器目录里的型号字符串是 `CAMERA_Model_BOOSTER_MIPI` | 规格书 `:26`；`3P/HSL`；`DOC/...sensor-info.md:117` |
| 麦克风 / 扬声器 | 麦克风阵列（3P 写的是 6 麦环形阵列，官网写的是 3 麦）/ 1 个扬声器 | 规格书 `:27-28`；`3P/HSL`；`WEB/K1` |
| 有线网 / 无线 | 千兆以太网 ×1；Wi-Fi 6；蓝牙 5.2 | 规格书 `:32-34` |
| 机器人有线 IP / SSH | `192.168.10.102`，用户 `booster`，初始密码 `<机器人当前密码，请向队内获取>`；开发机设为 `192.168.10.10/24`，网关 `192.168.10.1` | `DOC/product-manual__k1__basic-operations__connect-robot.md:46-75` |
| 主机名 | `tegra-ubuntu`（来自旧版截图） | `k1-operations.md §4.1` ⚠待实机验证 |
| 第二个 IP | `RCD/configs/fastdds.xml:9-11` 的白名单里有 `192.168.10.101`。T1 有「运动板 + 感知板」两块板子（`DOC/developer-guide__open-source__booster-deploy.md:14`），K1 规格书只列了一个控制器，所以 .101 在 K1 上是否存在不确定 | ⚠待实机验证 |
| OS / ROS | Ubuntu 22.04 aarch64；ROS 2 Humble | `DOC/developer-guide__open-source__booster-deploy.md:27`；`RCD/scripts/start.sh:9` |
| 安全告警 | 低电量告警、关节过热告警 | 规格书 `:31` |

---

## 2. 执行器（电机型号与参数）

`TRN` 里的 K1 执行器配置写明了每个关节用的电机型号（`TRN/assets/robots/booster.py:46-101`），电机参数定义在 `TRN/assets/robots/actuator.py:321-397`（源码注释里写着 "K1 Hip Pitch"、"K1 Knee" 等）。

| 关节 | 电机型号 | 力矩上限 (N·m) | 速度上限 (rad/s) | 拐点速度 (rad/s) | 转子惯量 armature (kg·m²) | URDF effort / velocity | 来源行 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 头 yaw / pitch | HT4438 | 6.0 | 7.85 | 10.47 | 0.001（MJCF 里写的是 0.002） | 6.0 / 7.85 | `actuator.py:386-396`；`K1_22dof.xml:56,61` |
| 臂（idx 2–9） | R14 | 14 | 33.51 | 5.24 | 0.001 | 14.0 / 33.51 | `actuator.py:373-383` |
| 髋 pitch | E6408 | 68.0 | 14.66 | 1.88 | 0.0478125 | 68.0 / 14.66 | `actuator.py:321-331` |
| 髋 roll | E4315 | **76.0** | 12.57 | 2.62 | 0.0339552 | **43.0** / 12.57 | `actuator.py:334-344`；`K1_22dof.urdf:753` |
| 髋 yaw | E4310 | 38.3 | 17.59 | 7.85 | 0.0282528 | 38.3 / 17.59 | `actuator.py:347-357` |
| 膝 | E6416 | 112.0 | 12.57 | 2.09 | 0.095625 | 112.0 / 12.57 | `actuator.py:360-370` |
| 踝 pitch / roll（串联等效） | 2×E4310，并联，经 `BoosterK1AnkleParaWrapperCfg` 换算 | 38.3（effort_ratio 1.0） | 17.59（velocity_ratio 1.0） | 7.85 | 0.0565056（armature_ratio 2.0；串联 MJCF 写 0.0565） | 38.3 / 17.59 | `actuator.py:283-293`；`booster.py:63-84`；`K1_22dof.xml:136,140` |
| 踝驱动电机（并联 MJCF） | E4310 ×2/腿 | 38.3（`forcerange`） | — | — | 0.0282528 | — | `K1_22dof_parallel.xml:144,156,254-255` |

补充说明：

- 力矩-速度曲线：TRN 用分段线性的 T-N 曲线模拟电机。|v| ≤ 拐点速度时，可用力矩为峰值；超过拐点后线性下降，到速度上限时降为 0（`actuator.py:114-133`）。这意味着腿部电机高速时实际可用力矩远小于峰值：髋 pitch 的拐点只有 1.88 rad/s，膝只有 2.09 rad/s。
- 官网写 "Max Peak Torque 60N·m"，与 URDF 和 TRN 里膝关节的 112 N·m 不一致。可能是口径不同，⚠待实机验证。
- 髋 roll 的 URDF effort 是 43，TRN 的 E4315 是 76，两者不一致。DEP 部署时并不把 effort 下发给机器人，只在 MuJoCo 仿真里用它截断力矩：K1_CFG 里髋 roll 为 35，k1_walk 里为 20（`DEP/booster_deploy/robots/k1.py:41-44`、`DEP/tasks/locomotion/robots/k1/__init__.py:36-42`）。
- 头部电机可能不止一种：v1.6.0 固件的更新日志写了「支持头部使用 INNFOS 关节」（`DOC/changelog__v1-6-0-firmware-app-release.md:92`），所以不同批次的头部电机型号可能不同。⚠待实机验证。
- 执行器都是带双编码器、有力矩反馈的一体化伺服，驱动板为私有设计（`3P/HSL`）。

---

## 3. 完整关节表

### 3.1 索引与命名（LowCmd/LowState 数组下标 = idx）

同一个关节在不同来源里有 5 套命名。**写底层代码时只认 idx**；与仿真或训练对接时，再按名字映射。

| idx | SDK `JointIndexK1` | URDF / DEP 名 | 机器人上报名（`list_joints`，大小写有出入） | 规格书名 | 部位 | 零位时轴向（trunk 系） |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | `kHeadYaw` | `aahead_yaw_joint` | `AAHead_yaw` / `AAHead_Yaw` | Head Yaw | 头 | +Z |
| 1 | `kHeadPitch` | `aahead_pitch_joint` | `Head_pitch` / `Head_Pitch` | Head Pitch | 头 | +Y |
| 2 | `kLeftShoulderPitch` | `aaleft_shoulder_pitch_joint` | `ALeft_Shoulder_Pitch` | Left Shoulder Pitch | 左臂 | +Y |
| 3 | `kLeftShoulderRoll` | `left_shoulder_roll_joint` | `Left_Shoulder_Roll` | Left Shoulder Roll | 左臂 | +X |
| 4 | `kLeftElbowPitch` | `left_elbow_pitch_joint` | `Left_Elbow_Pitch` | **Left Shoulder Yaw** | 左臂 | +Y（零位是 T 字姿态，这根轴沿上臂方向，所以物理上是上臂自转） |
| 5 | `kLeftElbowYaw` | `left_elbow_yaw_joint` | `Left_Elbow_Yaw` | **Left Elbow** | 左臂 | +Z（物理上是肘屈伸） |
| 6 | `kRightShoulderPitch` | `aaright_shoulder_pitch_joint` | `ARight_Shoulder_Pitch` | Right Shoulder Pitch | 右臂 | +Y |
| 7 | `kRightShoulderRoll` | `right_shoulder_roll_joint` | `Right_Shoulder_Roll` | Right Shoulder Roll | 右臂 | +X |
| 8 | `kRightElbowPitch` | `right_elbow_pitch_joint` | `Right_Elbow_Pitch` | Right Shoulder Yaw | 右臂 | +Y |
| 9 | `kRightElbowYaw` | `right_elbow_yaw_joint` | `Right_Elbow_Yaw` | Right Elbow | 右臂 | +Z |
| 10 | `kLeftHipPitch` | `left_hip_pitch_joint` | `Left_Hip_Pitch` | Left Hip Pitch | 左腿 | +Y |
| 11 | `kLeftHipRoll` | `left_hip_roll_joint` | `Left_Hip_Roll` | Left Hip Roll | 左腿 | +X |
| 12 | `kLeftHipYaw` | `left_hip_yaw_joint` | `Left_Hip_Yaw` | Left Hip Yaw | 左腿 | +Z |
| 13 | `kLeftKneePitch` | `left_knee_pitch_joint` | `Left_Knee_Pitch` | Left Knee | 左腿 | +Y |
| 14 | `kCrankUpLeft` | `left_ankle_pitch_joint`（SERIAL） | `Left_Ankle_Pitch` | Left **Ankle Up** | 左腿 | SERIAL：+Y 踝 pitch；PARALLEL：上曲柄电机 |
| 15 | `kCrankDownLeft` | `left_ankle_roll_joint`（SERIAL） | `Left_Ankle_Roll` | Left **Ankle Down** | 左腿 | SERIAL：+X 踝 roll；PARALLEL：下曲柄电机 |
| 16 | `kRightHipPitch` | `right_hip_pitch_joint` | `Right_Hip_Pitch` | Right Hip Pitch | 右腿 | +Y |
| 17 | `kRightHipRoll` | `right_hip_roll_joint` | `Right_Hip_Roll` | Right Hip Roll | 右腿 | +X |
| 18 | `kRightHipYaw` | `right_hip_yaw_joint` | `Right_Hip_Yaw` | Right Hip Yaw | 右腿 | +Z |
| 19 | `kRightKneePitch` | `right_knee_pitch_joint` | `Right_Knee_Pitch` | Right Knee | 右腿 | +Y |
| 20 | `kCrankUpRight` | `right_ankle_pitch_joint`（SERIAL） | `Right_Ankle_Pitch` | Right Ankle Up | 右腿 | 同 14 |
| 21 | `kCrankDownRight` | `right_ankle_roll_joint`（SERIAL） | `Right_Ankle_Roll` | Right Ankle Down | 右腿 | 同 15 |

各列来源：
- SDK 枚举：`SDK/include/booster/robot/b1/b1_api_const.hpp:151-174`。
- URDF 名：`AST/K1_22dof.urdf`（各关节行号见 §3.2）；DEP 的关节顺序与 URDF 完全一致（`DEP/booster_deploy/robots/k1.py:7-17`）。
- 上报名：`DOC/developer-guide__open-source__booster-assets.md:67`（`AAHead_yaw, Head_pitch, ...`）；`DOC/developer-guide__booster-os-python-sdk__quick-start.md:65`（`'AAHead_Yaw', 'Head_Pitch', ...`）。
- 规格书名：`DOC/product-manual__k1__getting-started__specifications.md:48-69`。

命名陷阱：
- idx 4/5（以及 8/9）的 URDF 名字是按零位 T 姿态下的轴向起的：`elbow_pitch` 其实是上臂自转，`elbow_yaw` 才是真正的肘。规格书和 3P 资料用的是物理含义（Shoulder Yaw、Elbow）。
- 名字前面的 `aa`/`A` 前缀是为了让关节按字母排序时排在前面，没有物理含义。
- `booster_assets/src/booster_assets/motions.py` 里的 `K1_JOINT_NAMES` 写的是 `left_shoulder_pitch_joint`，没有 `aa` 前缀，与 URDF 对不上。
- TRN 的正则用的是 `Left_Hip_Pitch`、`Trunk`、`left_foot_link` 等名字（`TRN/assets/robots/booster.py:39-99`；`TRN/tasks/manager_based/beyond_mimic/robots/k1/mj_dance_002/env_cfg.py:18-34`），与本地 `K1_22dof.urdf` 里的小写名字**不匹配**。说明 TRN 依赖的是另一版 booster_assets。⚠待实机验证（或核对 booster_assets 的版本）。

### 3.2 位置限位

| idx | URDF lower / upper (rad) | 换算成度 | 规格书 (°) Min / Max | 官网 (°) | URDF 行 |
| --- | --- | --- | --- | --- | --- |
| 0 | -1.012 / 1.012 | -58.0 / 58.0 | -59 / 59 | — | `:121,132` |
| 1 | -0.314 / 0.794 | -18.0 / 45.5 | -19 / 49 | — | `:180,191` |
| 2 | -2.932 / 1.196 | -168.0 / 68.5 | -169 / 69 | — | `:230,241` |
| 3 | -1.642 / 1.629 | -94.1 / 93.3 | -94 / 94 | — | `:288,299` |
| 4 | -1.885 / 1.885 | -108.0 / 108.0 | -109 / 109 | — | `:347,358` |
| 5 | -2.242 / 0.816 | -128.5 / **46.8** | -129 / **39** | — | `:406,417` |
| 6 | -2.932 / 1.196 | -168.0 / 68.5 | -169 / 69 | — | `:457,468` |
| 7 | -1.642 / 1.629（左右没有镜像） | -94.1 / 93.3 | -94 / 94 | — | `:515,526` |
| 8 | -1.885 / 1.885 | ±108.0 | ±109 | — | `:574,585` |
| 9 | -0.816 / 2.242 | **-46.8** / 128.5 | **-39** / 129 | — | `:633,644` |
| 10 | -2.958 / 2.226 | -169.5 / 127.5 | -170 / 128 | P -171~126 | `:684,695` |
| 11 | -0.375 / 1.536 | -21.5 / 88.0 | -22 / 89 | R -22~89 | `:742,753` |
| 12 | -1.012 / 1.012 | ±58.0 | ±59 | Y ±59 | `:800,811` |
| 13 | 0 / 2.321 | 0 / 133.0 | 0 / 133 | **0~127** | `:866,877` |
| 14 | 踝 pitch -0.87 / 0.345 | -49.8 / 19.8 | Ankle **Up** -17 / 38（电机空间） | P -50~20 | `:916,927` |
| 15 | 踝 roll -0.345 / 0.345 | ±19.8 | Ankle **Down** -16 / 41（电机空间） | R ±20 | `:975,986` |
| 16 | -2.958 / 2.226 | -169.5 / 127.5 | -170 / 128 | — | `:1026,1037` |
| 17 | -1.536 / 0.375（与左侧镜像） | -88.0 / 21.5 | -89 / 22 | — | `:1084,1095` |
| 18 | -1.012 / 1.012 | ±58.0 | ±59 | — | `:1142,1153` |
| 19 | 0 / 2.321 | 0 / 133.0 | 0 / 133 | — | `:1208,1219` |
| 20 | -0.87 / 0.345 | -49.8 / 19.8 | Up -17 / 38 | — | `:1258,1269` |
| 21 | -0.345 / 0.345 | ±19.8 | Down -16 / 41 | — | `:1317,1328` |

- 规格书的数值与 URDF 大多相差约 1°（规格书四舍五入偏宽松）。**肘关节（idx 5/9）差了 7.8°**，规格书更保守。⚠待实机验证。
- 规格书 idx 14/15 给的是**电机（曲柄）角度**，URDF 给的是**串联等效的踝角度**，两者不能直接比较。并联 MJCF 中两个驱动关节的范围又是另一套：drive_a -0.55~0.8 rad（-31.5°~45.8°），drive_b -0.5~1.1 rad（-28.6°~63.0°）（`AST/K1_22dof_parallel.xml:144,156`）。三套数字的零点定义可能都不一样。⚠待实机验证。
- 固件会对部分控制器施加限位：ArmController 的注释写着 "The server applies configured joint-position limits"（`SDK/include/booster/robot/b1/arm_controller.hpp:60`）。**Custom 模式下固件会不会截断 `rt/joint_ctrl` 里的 q，没有文档说明**；超限后会进入 PROTECT 模式（`DOC/product-manual__k1__basic-operations__modes.md:68`）。建议自己在发送端做 clamp，并留出 5–10% 的余量；TRN 训练时用的软限位系数是 0.9（`TRN/assets/robots/booster.py:44`）。

### 3.3 力矩、速度与仿真截断值

| idx | URDF effort (N·m) | URDF velocity (rad/s) | DEP `K1_CFG.effort_limit` | DEP k1_walk `effort_limit` | 电机型号 |
| --- | --- | --- | --- | --- | --- |
| 0–1 | 6.0 | 7.85 | 6 | 6 | HT4438 |
| 2–9 | 14.0 | 33.51 | 14 | 14 | R14 |
| 10/16 髋 P | 68.0 | 14.66 | 30 | 30 | E6408 |
| 11/17 髋 R | 43.0 | 12.57 | 35 | 20 | E4315 |
| 12/18 髋 Y | 38.3 | 17.59 | 20 | 15 | E4310 |
| 13/19 膝 | 112.0 | 12.57 | 40 | 35 | E6416 |
| 14/20 踝 P | 38.3 | 17.59 | 20 | 24 | 2×E4310（并联） |
| 15/21 踝 R | 38.3 | 17.59 | 20 | 15 | 2×E4310（并联） |

来源：`AST/K1_22dof.urdf`（`<limit>` 行见 §3.2）；`DEP/booster_deploy/robots/k1.py:41-44`；`DEP/tasks/locomotion/robots/k1/__init__.py:36-42`。**DEP 的 effort_limit 只用于 MuJoCo 仿真里 `np.clip` 截断力矩**（`DEP/booster_deploy/controllers/mujoco_controller.py:237-243`），也用来计算 BeyondMimic 的 action_scale（`DEP/tasks/beyond_mimic/beyond_mimic.py:40-43`）。`LowCmd` 没有力矩上限字段，实机上的力矩饱和由固件和电机决定。

### 3.4 默认站姿（多个来源，单位 rad，按 idx 排列）

| idx | DEP `K1_CFG.default_joint_pos` | DEP `K1_CFG.prepare_state.joint_pos` | DEP k1_walk `default_joint_pos` | TRN `init_state` |
| --- | --- | --- | --- | --- |
| 0, 1 | 0, 0 | 0, 0 | 0, 0 | 0, 0 |
| 2, 3, 4, 5 | 0, **-1.3**, 0, 0 | 0, -1.3, 0, 0 | **0.2, -1.25, 0, -0.5** | 0, -1.3, 0, 0 |
| 6, 7, 8, 9 | 0, **1.3**, 0, 0 | 0, 1.3, 0, 0 | **0.2, 1.25, 0, 0.5** | 0, 1.3, 0, 0 |
| 10–15 | 0, 0, 0, 0, 0, 0 | 0, 0, 0, **0.105, -0.10**, 0 | **-0.15**, 0, 0, **0.3, -0.15**, 0 | 全 0 |
| 16–21 | 同左腿 | 0, 0, 0, 0.105, -0.10, 0 | -0.15, 0, 0, 0.3, -0.15, 0 | 全 0 |
| trunk 初始高度（仿真） | 0.6 m（`MujocoControllerCfg`） | — | — | 0.57 m |

来源：`DEP/booster_deploy/robots/k1.py:37-40,75-78`；`DEP/tasks/locomotion/robots/k1/__init__.py:15-21`；`TRN/assets/robots/booster.py:36-43`；`DEP/booster_deploy/controllers/controller_cfg.py:17`；BeyondMimic 仿真用 0.57 m（`DEP/tasks/beyond_mimic/robots/k1/__init__.py:35`）。

- 屈膝站姿满足「hip_pitch + knee + ankle_pitch = 0」时脚底水平，例如 -0.15 + 0.3 - 0.15 = 0。
- 腿全为 0 的直腿姿态是 BeyondMimic 类策略的 default，**不适合**作为步行策略的站姿，因为直腿会导致奇异、刚度差。自研步态建议从 k1_walk 的屈膝姿态出发。
- T1 可以参考 `GYM/configs/T1.yaml:19-26,74-81`（-0.2/0.4/-0.25），**不要直接套到 K1**，两者腿长不同。

### 3.5 建议 kp / kd（N·m/rad，N·m·s/rad）

| idx | DEP K1_CFG 基础（BeyondMimic 用） | DEP `prepare_state`（进入 Custom 时保持用） | DEP k1_walk（步行 RL） | DEP k1_mj2 / k1_fight | DOC set_joints 示例 | TRN 推导（armature × ω²） |
| --- | --- | --- | --- | --- | --- | --- |
| 0–1 头 | 4 / 1 | 40 / 1.5 | 4 / 1 | 10 / 2 | 40 / 2 | 3.95 / 0.25 |
| 2 肩 P | 4 / 1 | 40 / 0.5 | 20 / 2 | 4 / 1；3.95 / 0.3 | 20 / 1.5 | 3.95 / 0.25 |
| 3 肩 R | 4 / 1 | 50 / 1.5 | 20 / 2 | 同上 | 30 / 2 | 同上 |
| 4 上臂自转 | 4 / 1 | 20 / 0.2 | 20 / 2 | 同上 | 10 / 0.5 | 同上 |
| 5 肘 | 4 / 1 | 20 / 0.2 | 20 / 2 | 同上 | 10 / 0.5 | 同上 |
| 6–9 右臂 | 同 2–5 | 40/0.5, 50/1.5, 20/0.2, 20/0.2 | 20 / 2 | 同上 | 同左 | 同上 |
| 10/16 髋 P | 80 / 2 | 350 / 7.5 | 100 / 2 | 80 / 2 | 250 / 15 | 30.2 / 3.61 |
| 11/17 髋 R | 80 / 2 | 350 / 7.5 | 100 / 2 | 80 / 2 | 250 / 15 | 21.4 / 2.56 |
| 12/18 髋 Y | 80 / 2 | 180 / 3 | 100 / 2 | 80 / 2 | 150 / 8 | 17.8 / 2.13 |
| 13/19 膝 | 80 / 2 | 350 / 5.5 | 100 / 2 | 80 / 2 | 250 / 12 | 60.4 / 4.81 |
| 14/20 踝 P | 30 / 2 | 250 / 5.0 | 65 / **1** | 30 / 2 | 120 / 8 | 35.7 / 4.26 |
| 15/21 踝 R | 30 / 2 | 250 / 5.0 | 65 / **1** | 30 / 2 | 120 / 8 | 35.7 / 4.26 |

来源：
- DEP 基础：`DEP/booster_deploy/robots/k1.py:29-36`。
- prepare：`k1.py:66-74`。
- k1_walk：`DEP/tasks/locomotion/robots/k1/__init__.py:22-35`。
- mj2 / fight：`DEP/tasks/beyond_mimic/robots/k1/__init__.py:48-61,77-90`。
- DOC：`DOC/developer-guide__booster-os-python-sdk__booster-robot-client-reference__motion-control-apis__set-joints.md:57-83`，以及 `DOC/developer-guide__booster-os-python-sdk__faq-and-debugging-tools__debugging-tips-gain-tuning.md:14-20`。
- TRN：公式在 `TRN/assets/robots/actuator.py:159-163`（kp = J·(2πf)²，kd = 2ζ·J·(2πf)）。参数取值：腿 f = 4 Hz，髋和踝 ζ = 1.5，膝 ζ = 1.0（`booster.py:57-82`）；臂和头用默认值 f = 10 Hz、ζ = 2（`actuator.py:150-155`）。[计算]
- ArmController 固定给手臂 kp = 60、kd = 3（`SDK/include/booster/robot/b1/arm_controller.hpp:227-232`）。
- `SDK/example/low_level/b1_low_sdk_example.cpp:82-97` 里的增益是 **T1 的 23 关节布局**（含腰），K1 不能照搬。

怎么选：
- 位置保持 / 插值：用 prepare_state 这一套高增益。
- RL 策略：必须用**训练时的 kp/kd**。仿真 PD 与实机 PD 公式相同，只有踝的 kd 有例外，见下一条。
- 踝（并联）的 kd：DEP 的 README 明确说 "For parallel-actuated joints, `robot.joint_damping` is sent directly to the motors, so do not reuse the training-simulator `Kd`"，并建议用 `Kd = 2·ζ·J_eq·(2π·f_n)` 计算，其中 J_eq 取并联关节的 armature（`DEP/README.md:91-101`）。T2 的配置里也把腰和踝的 kd 单独写成了 "motor-side damping"（`DEP/tasks/beyond_mimic/robots/t2/__init__.py:89-110`）。K1 的 k1_walk 把踝 kd 设为 1.0，低于其他腿关节的 2.0，与这个做法一致。

---

## 4. 运动学结构

### 4.1 关节原点（child 相对 parent 的偏置；所有关节 rpy = 0，所以零位时各关节系都与 trunk 系平行）

| 关节 | parent → child | xyz (m) | 轴 |
| --- | --- | --- | --- |
| aahead_yaw | trunk → aahead_yaw_link | (0.0056, 0, 0.2149) | Z |
| aahead_pitch | aahead_yaw_link → aahead_pitch_link | (0, 0, 0.033) | Y |
| aaleft_shoulder_pitch | trunk → aaleft_shoulder_pitch_link | (0, 0.077, 0.1845) | Y |
| left_shoulder_roll | → left_shoulder_roll_link | (0.0025, 0.068, -0.0135) | X |
| left_elbow_pitch | → left_elbow_pitch_link | (0, 0.044428, 0) | Y |
| left_elbow_yaw | → left_elbow_yaw_link | (0, 0.1215, 0) | Z |
| left_hip_pitch | trunk → left_hip_pitch_link | (0, 0.096, -0.077) | Y |
| left_hip_roll | → left_hip_roll_link | (0, 0, -0.026) | X |
| left_hip_yaw | → left_hip_yaw_link | (0.012, 0, -0.0485) | Z |
| left_knee_pitch | → left_knee_pitch_link | (-0.014, 0, -0.117) | Y |
| left_ankle_pitch | → left_ankle_pitch_link | (0.00019706, 0.0002, -0.24519) | Y |
| left_ankle_roll | → left_ankle_roll_link（脚） | (0, 0, 0)，与 pitch 轴相交 | X |
| 相机（立体） | aahead_pitch_link → head_booster_stereo_rgb_link | (0.060138, 0.0351, 0.092774)，rpy (-π/2, 0, -π/2) | fixed |
| 相机（RealSense 位） | aahead_pitch_link → head_realsense_rgb_link | (0.053617, -0.0115, 0.10231)，rpy (-1.835388, 0, -π/2) | fixed |

右侧关节是左侧的 y 取反。来源：`AST/K1_22dof.urdf:121-1347`（由解析脚本读出，行号见 §3.2）。

### 4.2 关键尺寸 [计算]

| 量 | 值 |
| --- | --- |
| 髋 pitch 轴 → 膝轴（大腿） | 0.1915 m（竖直 0.1915，x 方向偏 -0.002） |
| 膝轴 → 踝轴（小腿） | 0.2452 m |
| 踝轴 → 脚底 | 0.038 m（MJCF 脚盒 `pos=(0.026,0,-0.02)`、`size` 半高 0.018） |
| 髋 pitch 轴 → 脚底（腿总长） | 0.4747 m |
| 髋 pitch 轴与髋 roll 轴 | **不相交**，roll 轴在 pitch 轴下方 0.026 m；hip_yaw 轴又在 roll 轴前方 0.012 m、下方 0.0485 m；膝轴在 yaw 轴后方 0.014 m |
| 踝 pitch 与 roll 轴 | 相交（十字轴，零偏置） |
| 两腿间距（髋 pitch 轴 y） | 0.192 m |
| trunk 原点 → 髋 pitch 轴 | 下方 0.077 m |
| 脚底板（碰撞盒） | 长 0.18 m × 宽 0.07 m，中心在踝轴前方 0.026 m：脚尖在踝前 0.116 m，脚跟在踝后 0.064 m |
| 零位时 trunk 原点离地 | 0.5517 m |
| 头 pitch 轴离地（零位） | 0.5517 + 0.2149 + 0.033 = 0.7996 m |
| 相机光心离地（零位，立体相机帧） | 0.892 m |

解析 IK 的注意点：
1. 髋是 P→R→Y 顺序，三轴不交于一点，不能直接套用「三轴共点的球形髋」闭式解。建议用数值 IK（如 Pinocchio 或 RBDL；固件内部的 motion stack 用的就是 RBDL，见 `SDK/include/booster/robot/b1/b1_loco_client.hpp:268`），或者推导带偏置的解析解。
2. 踝是两轴相交的十字轴，适合做「髋 + 膝定位踝心、踝定姿态」的分解。

### 4.3 正方向约定（右手定则 + URDF 轴向推导，零位为 T 字臂、直腿）

| 关节 | 正方向含义 | 依据 |
| --- | --- | --- |
| 头 yaw (+Z) | 正 = 向左转头 | 右手定则 |
| 头 pitch (+Y) | **正 = 低头**；范围 -18°（抬头）~ +45.5°（低头），向下的行程更大，适合看球 | 右手定则 + 限位；SDK 示例把 head pitch 设为 0.785，即低头约 45°（`SDK/example/low_level/low_level_publisher.cpp:36-43`） |
| 肩 pitch (+Y) | 负 = 手臂向前上抬 | 限位 -168°~68.5° |
| 左肩 roll (+X) | 从 T 字姿态出发，负 = 手臂下垂；默认 -1.3（右侧 +1.3） | `k1.py:38` |
| 髋 pitch (+Y) | **负 = 大腿前抬（屈髋）** | 推导：R_y(-θ)·(0,0,-1) 的 x 分量为正 |
| 左髋 roll (+X) | 正 = 外展（右侧为负） | 限位不对称：左 -21.5°~88° / 右 -88°~21.5° |
| 膝 (+Y) | 正 = 屈膝，范围 0~133°，不能反向 | 限位 |
| 踝 pitch (+Y) | 负 = 脚尖上抬（背屈）；正 = 脚尖下压 | R_y(θ)·(1,0,0) = (cosθ, 0, -sinθ) |
| 踝 roll (+X) | 正 = 脚底绕 +X 旋转，此时左脚外侧（+y 边）抬起 | 右手定则 ⚠待实机验证方向 |

### 4.4 质量与惯量

各连杆的质量、质心和惯量张量见 §5.1 以及 URDF 各 `<inertial>` 段。MJCF 的 `diaginertia` 是主惯量，与 URDF 里的全张量等价（`AST/K1_22dof_parallel.xml:43-135`）。

### 4.5 并联踝机构，以及 SERIAL / PARALLEL 的含义

**结论**：K1 每条腿的踝由两个装在小腿上的电机（E4310）驱动，它们通过「曲柄 + 连杆 + 球铰」拉动脚板，属于 2 自由度并联机构。

证据：
- SDK 把 idx 14/15 命名为 `kCrankUpLeft` / `kCrankDownLeft`（`b1_api_const.hpp:166-167`）。
- 规格书称之为 Ankle Up / Ankle Down（`specifications.md:62-63`）。
- 网格文件里有 `Left_Crank_Up.STL`、`Left_Crank_Down.STL`、`Left_Link_Long/Short.STL` 以及多个 `*_Ball.STL`（`AST/meshes/`）。
- `K1_22dof_parallel.xml` 用 `equality/connect` 闭链把这个机构建了出来（`:233-238`）。

并联 MJCF 中的左腿几何（以 knee_pitch_link 系表示，右腿 y 取反）：

| 部件 | 位置 / 尺寸 | 行 |
| --- | --- | --- |
| 驱动 A（推断为 CrankUp，上曲柄） | 转轴在膝下方 0.0816 m、y = +0.0242，轴向 Y；曲柄长 0.041 m；长连杆 0.158 m；范围 -0.55~0.8 rad | `K1_22dof_parallel.xml:142-153` |
| 驱动 B（推断为 CrankDown，下曲柄） | 转轴在膝下方 0.1401 m、y = -0.0238，轴向 Y；曲柄长 0.041 m；短连杆 0.082 m；范围 -0.5~1.1 rad | `:154-165` |
| 连杆在脚上的铰点 | 脚板系 (-0.029, ±0.024, 0.0175)，即踝轴后方 29 mm、左右各 24 mm、上方 17.5 mm | `:138-139` |
| 驱动电机 | 两个 `<motor>` 的 `forcerange` 都是 ±38.3，armature 0.0282528 | `:144,156,254-255` |

推断：两个曲柄同向转动 → 踝 pitch；反向转动 → 踝 roll（两个铰点分列踝轴左右 ±24 mm）。⚠待实机验证 A/B 与 Up/Down 的对应关系，以及符号。

`LowCmd.cmd_type` / `LowState` 的双数组：

| 概念 | PARALLEL（`CmdType::PARALLEL = 0`，也是 C++ IDL 的默认值） | SERIAL（`CmdType::SERIAL = 1`） |
| --- | --- | --- |
| idx 14/15、20/21 指什么 | 两个曲柄**电机**（Up/Down） | 串联等效的**踝 pitch / roll**，与 URDF 一致 |
| 其他关节 | 与 SERIAL 相同，都是直驱 | 同左 |
| 状态读取 | `LowState.motor_state_parallel[]` | `LowState.motor_state_serial[]` |
| 谁在用 | SDK 示例的默认值（`b1_low_sdk_example.cpp:68`）；ArmController 读 `motor_state_parallel`（`arm_controller.hpp:317`），手臂不受踝影响 | **DEP（K1 官方 RL 部署）**：`cmd_type = CMD_TYPE_SERIAL`，读 `motor_state_serial`（`DEP/booster_deploy/controllers/booster_robot_controller.py:224,270`）；GYM（T1）也用 SERIAL（`GYM/utils/command.py:5`） |
| 适用场景 | 自己做并联运动学或力矩映射，或做电机级辨识 | 用 URDF 串联模型训练出来的策略，或按串联关节写的步态和 IK |

- 串联 ↔ 并联的换算（包括位置 FK/IK 和 Jacobian 力矩映射）由固件完成。可见的依据：同时提供两套状态数组；DEP 发 SERIAL 就能直接控制踝。**换算发生在哪一层、kp 如何映射，文档没有写**。已知信息：
  1. DEP README 说并联关节的 kd「直接下发到电机」（`DEP/README.md:91-101`），即 kd 在电机侧生效，不经换算。
  2. GYM 在 SERIAL 模式下对并联关节（T1 的 idx 15、16、21、22）不交给固件做 PD：它令 `q = 实测串联角`、`kp = 0`，把 `tau = clip(kp·(q_des - q))` 作为前馈力矩下发，注释是 "Use series-parallel conversion for torque to avoid non-linearity"（`GYM/deploy.py:182-190`，`GYM/configs/T1.yaml:55`）。这说明固件对 SERIAL 下的 kp 做的是非线性（或近似）换算，只有力矩的换算是线性的。
  - K1 对应的并联下标是 **14、15、20、21**（按 K1 布局推断）。DEP 的 K1 部署**没有**使用这个技巧，而是直接给踝 kp = 30~65。⚠待实机验证两种做法的踝部跟踪误差。
- 在仿真和训练里，串联踝的等效 armature 取单个 E4310 的 2 倍，即 0.0565（`TRN/assets/robots/actuator.py:283-293`，`AST/K1_22dof.xml:136,140`）。如果要做更精确的 sim2real，可以改用 `K1_22dof_parallel.xml` 训练或验证。

---

## 5. 质量分布与质心

### 5.1 连杆质量（`AST/K1_22dof.urdf`，`<link>` 名所在行）

| 连杆 | 质量 kg | 质心（本体系，m） | 行 |
| --- | --- | --- | --- |
| trunk | 6.5 | (-0.0043, -0.0007, 0.0657) | `:20` |
| aahead_yaw_link / aahead_pitch_link | 0.3 / 0.7 | (-0.0007, -0.0004, 0.0317) / (0.0110, -0.0009, 0.0807) | `:81` / `:140` |
| 肩 pitch / 肩 roll / 上臂 (elbow_pitch_link) / 前臂 (elbow_yaw_link) | 0.5 / 0.09 / 0.8 / 0.19 | 见 URDF | `:199,249,307,366`（左）；`:426,476,534,593`（右） |
| hip_pitch / hip_roll / hip_yaw（大腿主体） / knee（小腿） | 0.69 / 0.13 / **1.65** / **1.5** | hip_yaw (-0.0085, -0.0040, -0.0879)；knee (-0.0008, 0.0031, -0.1092) | `:653,703,761,819`（左）；`:995,1045,1103,1161`（右） |
| ankle_pitch（十字轴） / ankle_roll（脚） | 0.039 / 0.494 | 脚 (0.0117, 0.0002, -0.0144) | `:885,935` / `:1227,1277` |

| 分组 | 质量 | 占比 |
| --- | --- | --- |
| 躯干 | 6.5 kg | 33.1% |
| 头 | 1.0 kg | 5.1% |
| 双臂 | 2 × 1.58 = 3.16 kg | 16.1% |
| 双腿 | 2 × 4.503 = 9.006 kg | 45.8% |
| 合计 | **19.666 kg** | 100% |

- 单腿各段：大腿段（hip 三连杆）2.47 kg，小腿 1.5 kg，脚 + 十字轴 0.533 kg。
- 脚很轻（约 0.5 kg），腿的质量集中在大腿附近。这对摆腿惯量有利，也意味着单纯用倒立摆模型（LIPM）估计质心时误差不大。

### 5.2 质心位置 [计算]（trunk 系坐标；离地高度 = trunk 原点离地高度 + 质心 z）

| 姿态 | trunk 原点离地 | 质心（trunk 系） | 质心离地 |
| --- | --- | --- | --- |
| 全零（T 字臂，直腿） | 0.5517 m | (-0.0003, -0.0003, -0.0704) | 0.481 m |
| DEP `K1_CFG.default`（臂下垂，直腿） | 0.5517 m | (-0.0003, -0.0003, -0.0844) | 0.467 m |
| DEP `prepare_state`（微屈膝） | 0.5504 m | (-0.0034, -0.0003, -0.0843) | 0.466 m |
| DEP k1_walk default（屈膝，臂前摆） | 0.5471 m | (0.0033, -0.0003, -0.0828) | 0.464 m |

- 质心约在 trunk 原点下方 7–8 cm，接近髋 pitch 轴的高度（trunk 原点下方 7.7 cm）。LIPM 可取 z_c ≈ 0.46 m，对应自然频率 ω = √(g/z_c) ≈ 4.6 rad/s。
- RCD 的 brain 配置里 `robot_height: 0.8`（T1 为 1.12），用于视觉和里程计，这个数不是质心高度（`RCD/src/brain/config/config.yaml:13`）。

### 5.3 计算方法（可复现）

解析 `AST/K1_22dof.urdf` 的 joint origin、axis 和 link inertial，从 trunk 做正运动学，按质量加权求出质心。脚底取 `ankle_roll_link` 原点下方 0.038 m（依据 MJCF 脚盒）。临时脚本在 scratchpad 中，没有放进仓库；核心代码约 40 行 numpy，思路即上面的描述。

---

## 6. 坐标系约定

### 6.1 base / trunk
- `trunk` 是浮动基座，采用 REP-103 约定：**x 前、y 左、z 上**。依据：左腿在 +y（0.096），头和相机在 +x 侧，脚盒向 +x 偏移。
- trunk 原点在髋 pitch 轴上方 0.077 m 处，大约是骨盆与腰部的交界。
- 仿真中的 IMU 放在 trunk 原点，姿态与 trunk 一致：MJCF 为 `<site name="imu" pos="0 0 0">`（`AST/K1_22dof.xml:46`），传感器为 `framequat`、`gyro`（`:213-214`）。
- 实机 IMU 的安装位姿在 URDF 里没有给出。可以用 RPC `GetSensors`（API 2044）读取 `ImuInfo.mount_position`（`SDK/include/booster/idl/b1/ImuInfo.h`，字段 `m_mount_position`）。⚠待实机验证 IMU 是否与 trunk 系对齐。DEP 和 GYM 都把它当作 trunk 系直接使用。

### 6.2 IMU（`LowState.imu_state`）

| 字段 | 含义 | 依据 |
| --- | --- | --- |
| `rpy[3]` | 欧拉角 (roll, pitch, yaw)，单位 rad。旋转矩阵 **R = Rz(yaw)·Ry(pitch)·Rx(roll)**，即 ZYX 内旋，描述 body→world | `R2IF/msg/ImuState.msg:1-2`；`GYM/utils/rotate.py:17-20`；DEP 用 `quat_from_euler_xyz(roll, pitch, yaw)`（`DEP/booster_deploy/utils/isaaclab/math.py:273-299`） |
| `gyro[3]` | 角速度，**机体系**，rad/s | DEP 直接当作 `root_ang_vel_b` 使用（`booster_robot_controller.py:219,230`） |
| `acc[3]` | 加速度 x/y/z，单位 m/s² | `ImuState.msg:5-6`。Python SDK 文档中直立时的示例值约为 `[-0.45, 0.10, 9.80]`（`DOC/...imu-state.md:119-121`），说明是比力（直立时 z ≈ +g）⚠待实机验证 LowState 与 Python 接口是否同源 |

- 投影重力（策略里最常用的量）：`g_b = Rᵀ·[0, 0, -1]`。直立时 `g_b ≈ (0, 0, -1)`。DEP 用 `g_b.z > -0.5` 判定摔倒，对应倾角超过 60°（`DEP/tasks/locomotion/locomotion.py:119-131`）。
- yaw 会漂移，且原点不确定。K1 的 DEP 策略**不使用 yaw**：只用投影重力，因此 yaw 被消掉了。只有 T2 策略用 yaw 算航向误差（`locomotion.py:238-252`）。
- IDL 字段：`SDK/include/booster/idl/b1/ImuState.h:207-209`（三个 `std::array<float,3>`）。

### 6.3 头部
- 运动链：trunk → 头 yaw（Z，位于 trunk 原点上方 0.2149 m、前方 0.0056 m）→ 头 pitch（Y，再往上 0.033 m）。正方向见 §4.3：yaw 正 = 左转，pitch 正 = 低头。
- 机器人会发布头部位姿话题 `/head_pose`（`geometry_msgs/Pose`）。RCD 的 brain 和 vision 都订阅它（`RCD/src/brain/src/brain.cpp:193`、`RCD/src/vision/src/vision_node.cpp:299`）。它的参考系（base 还是 odom）在 RCD 里当作 head→base 使用（`vision_node.cpp:325-326`）。⚠待实机验证。
- RCD 读头部角度用的是 `motor_state_serial[0]`（yaw）和 `[1]`（pitch）（`RCD/src/brain/src/brain.cpp:1339-1340`）。

### 6.4 相机

| 帧 | 父帧 | 平移 (m) | 旋转 | 含义 |
| --- | --- | --- | --- | --- |
| `head_booster_stereo_rgb_link` | `aahead_pitch_link` | (0.060138, 0.0351, 0.092774) | rpy (-π/2, 0, -π/2) | 标准**光学系**（z 前、x 右、y 下），无俯仰；偏左 35 mm，可能是双目的左目 |
| `head_realsense_rgb_link` | `aahead_pitch_link` | (0.053617, -0.0115, 0.10231) | rpy (-1.835388, 0, -π/2) | 光学系，**下俯 15.16°**。这是旧款 RealSense 头的安装位 |

- 来源：`AST/K1_22dof.urdf:1336-1347`；MJCF 中以四元数形式给出（`K1_22dof.xml:64-65`）。
- 官方文档还提到有一个 `K1_22dof-ZED.urdf` 变体（`DOC/developer-guide__open-source__booster-assets.md:30-32`），本地仓库里没有，只有 `meshes/Head_2_ZED.STL`。
- 当前量产相机（3P/HSL）：D-Robotics 广角双目，544×488，FOV 105°×94°。
- RCD 用 D-Robotics 的话题 `/StereoNetNode/rectified_image`、`/StereoNetNode/stereonet_depth`，配置的内参为 fx = fy = 206.4455，cx = 224.958，cy = 242.717（`RCD/src/vision/config/vision.yaml:6-8,21-28`）。按宽 544 算，水平 FOV = 2·atan(272/206.45) ≈ 105.6°，与 3P 一致；但 cx 并不在 272 附近，可能是校正裁切造成的。⚠待实机验证，应以 `camera_info` 话题为准。
- RCD 还给出了相机到头的外参（cam：x 右 y 下 z 前 → head：x 前 y 左 z 上）：平移约 (-0.012, 0.044, -0.028) m，含约 4.3° 的俯仰（`vision.yaml:29-48`）。这是 RCD 针对某台机器标定的结果；系统级标定文件 `/opt/booster/vision.yaml` 的优先级更高（见 `k1-operations.md §4.2`）。视觉细节以视觉相关参考为准。

### 6.5 脚 / 里程计
- 脚系：`left/right_ankle_roll_link` 原点在踝十字轴中心，脚底在其下方 0.038 m。
- 里程计：`rt/odometer_state`（`Odometer{x, y, theta}`，float）是平面里程计（`SDK/include/booster/idl/b1/Odometer.h` 私有字段；`b1_api_const.hpp:36`）。RCD 在 K1 上乘了系数 `odom_factor: 0.8`（`RCD/src/brain/config/config.yaml:14`）。

---

## 7. 不一致与待验证汇总

| # | 问题 | 各方说法 | 建议 |
| --- | --- | --- | --- |
| 1 | 膝峰值力矩 | URDF 与 TRN 电机模型为 112 N·m；官网写 60 N·m | 实测，或按 60 N·m 保守设计 |
| 2 | 髋 roll 力矩 | URDF 43；TRN E4315 为 76 | 以实测为准，仿真里先按 43 截断 |
| 3 | 肘限位 | URDF 为 -128.5°~46.8°；规格书为 -129°~39° | 发送端按规格书 39° 限幅 |
| 4 | 踝限位口径 | URDF 与官网给串联角；规格书给电机角；并联 MJCF 的驱动范围又是另一套 | 实机分别读 `motor_state_serial` 和 `motor_state_parallel` 标定 |
| 5 | 关节命名 | 本地 URDF 用小写名；TRN、DOC 和机器人上报用 `Left_Hip_Pitch` 等；motions.py 缺少 `aa` 前缀 | 只按 idx 对接 |
| 6 | IMU 安装位姿与 acc 定义 | 没有文档 | 调用 `GetSensors`，把机器人静置在水平面上读取 acc 和 rpy |
| 7 | 相机内参、主点 | 3P 写 544×488；RCD 配置的 cx 不居中 | 以 `camera_info` 为准 |
| 8 | 192.168.10.101 | 只在 RCD 的 fastdds.xml 白名单里出现 | 在机器人上用 `ip a` 确认 |
| 9 | 质量 | 规格书约 19.5 kg；URDF 19.666 kg | 实测称重 |
| 10 | 并联踝 A/B 与 Up/Down 的对应关系和符号 | 只能从 MJCF 命名推断 | 在 DAMP 模式下手动掰动脚板，看两个电机角的变化方向 |
