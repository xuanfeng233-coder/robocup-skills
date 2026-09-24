# 固件 1.7 / Demo 1.7 兼容性审计（本队现行栈）

> 适用场景：主办方指定的 **1.7 栈**：K1 固件 ≥ 1.7（发放包 `1.7.2.0-dev-yunlong-…`）+ `sdk_release.zip` + `K1_5v5_demo_1.7.zip` + HSL GameController 7.0.0-rc.3。其它参考文件按最新 SDK 1.6.3（`87a9a26`，固件 1.8.0）和公开 robocup_demo main 写成，本文列出在 1.7 栈下哪些结论不成立。v1.6 栈（Demo v1.6 / 固件 1.6 / SDK `324946e` / GC 1.0.1）已于 2026-09-24 废弃，旧审计文件已删除。
> 审计日期 2026-09-24。本地快照：`SDK17` = `refs/booster_robotics_sdk@fw1.7`（`d5d8f7a`，2026-07-08）；`SDK18` = `refs/booster_robotics_sdk`（`87a9a26`，2026-09-15）；`SDK16` = `refs/booster_robotics_sdk@fw1.6`（`324946e`）；`D17` = `refs/K1_5v5_demo_1.7`；`GC7` = `refs/robocup_league/GameController@v7.0.0-rc.3`。
> 外部证据 `[PyPI]`：`booster_robotics_sdk_python` 1.3.9 sdist 与 1.5.6 wheel（2026-09-24 下载核对，未放进 `refs/`）。
> 标注：【已核实】= 读代码或逐字节比对确认；【推断】= 由日期、命名或结构推出；【待实机验证】= 本地资料无法确认。

## 0. 结论速览

1. **`sdk_release.zip` = 公开 SDK 提交 `d5d8f7a`**（"update for 1.7.0 firmware"）【已核实：`diff -rq` 无差异】；它也和 PyPI 1.3.9 sdist 里的 `sdk_release/` 逐字节相同。构建方式已经和 1.8 一样：Fast DDS 2.13.1 以 `booster_eprosima` 命名空间静态打进 `.a`，只需链接 `.a`、Threads、dl、rt；`install.sh` 支持 Ubuntu 22/24（§1.2）。
2. **SDK 1.7 相对 1.6 新增的足球相关接口**：`GetUpVersion`（kV2 = BMM 稳定起身）、`GaitType::kWholeBodyHumanlikeGaitV2`、`RotateHeadWithTime`、`BodyControl::kVisualKickV1`、`rt/odom|imu/data|joint_states`、`GetSensors/GetHands/GetRobotModel`、`HandEyeCalibClient`、`CameraClient`、`SetLEDLightColors`。这些接口官方文档默认要求**固件 ≥ 1.7.1**，1.7.0.x 上很可能不可用【推断】（§1.1）。
3. **1.7 上仍然没有（1.8 才有）**：`ResetOdometryTo`、异步 Operation RPC、返回码 503、`GetTrainedTrajStatus`/`rt/trained_traj_status`、LieDown 的 K1 警告；以及 1.8.0 的三个固件修复：Custom 自动保持站立、Visual Kick V1 里程计冻结、**K1 足球模式头部高速追球 CAN 掉线**（§1.1、§2）。
4. **Python 固定 `booster_robotics_sdk_python==1.5.6`**（与 `d5d8f7a` 同日发布，API 层级一致，有 `kJointCntK1` 和各订阅类；`b1-cli` 入口拼错不能用）。**不要用 1.3.9**：它的 C++ 部分是 SDK17，但绑定是用旧头文件编的（§1.3）。
5. **Demo 1.7 属于 `feat/k1_3v3_demo` → 内部仓 → `support_T2` 这条谱系**，不是 main/gc2026/autocal 线；29% 的 brain 代码不在任何公开提交里。它自带 v12/v20 双协议、v20 回包、定位球/加时/点球处理，但**定位 bug 仍在**，并新增了两个风险：队内通信 10 Hz 会耗尽 GC 额度（比分清零）、`setVelocity` 最小速度 0.3（§3）。
6. **Demo 1.7 include 了一个哪里都找不到的内部头文件** `booster_internal/robot/b1/b1_loco_internal_api.hpp`（`D17:src/brain/include/robot_client.h:10`、`src/robot_client.cpp:3`）：它**不在任何公开 SDK 里**（`sdk_release` 也没有），**1.7.2 升级包也不安装它**（包内只有运控库里的枚举定义，值 `kEnableRobocupWalkMode = 100008`）。它只被从未调用的 `RobotClient::walkMode()` 使用（`robot_client.cpp:105-113`；include 在 `robot_client.h:10`、`robot_client.cpp:3`）。编译报找不到这个头文件时：删掉这两行 include 和 `walkMode()`，或把枚举换成常量 `100008`（`issues.md` V6）（§2.3）。
7. 其它参考文件的勘误共 **39 条**（§4，文中标【fw1.7 #N】）。

---

## 1. SDK（`d5d8f7a`）

### 1.1 接口、枚举、话题逐项核对（「有/无」均读头文件确认【已核实】；能否调用还取决于固件小版本）

| 标识符 | SDK16 | SDK17 | SDK18 | SDK17 位置（相对 `include/booster/robot/`） | 在固件 1.7 上的结论 |
|---|---|---|---|---|---|
| `RobotMode::kSoccer=4` | 有 | 有 | 有 | `common/robot_shared.hpp:13` | 可用；Demo 1.7 由 LT+A 切入 |
| `BodyControl::kVisualKickV1=14` | 无 | 有 | 有 | `robot_shared.hpp:31`（`kInsideFoot=10` 注释为「实际是 visual kick V2」，:27） | kV2 踢球时 BodyControl 报 10 |
| `VisualKick(bool, VisualKickVersion=kV1)`，kV1=0/kV2=1 | 有 | 有 | 有 | `b1/b1_loco_client.hpp:655`；`b1/b1_loco_api.hpp:1089-1117` | 可用。`FromJson` 无条件读 `version`（:1103-1104），**请求必须带 version**。SDK17 注释 kV2 =「stronger kicking force」（:1091） |
| `GetUp(GetUpVersion=kV1)` | 只有 `GetUp()`（body `""`） | 有 | 有 | `b1_loco_client.hpp:286-290` | 无参也会发 `{"version":0}`；kV2 需固件 ≥ 1.7.1 |
| `GetUpWithMode(mode, GetUpVersion=kV1)` | 只有 mode | 有 | 有 | `b1_loco_client.hpp:297-301`；`b1_loco_api.hpp:352-378` | 可调 `GetUpWithMode(kSoccer, kV2)`，起身后直接回到足球模式【待实机验证】 |
| `enum GetUpVersion{kV1=0, kV2=1 BMM}` | 无 | 有 | 有 | `b1_loco_api.hpp:321-324` | 对应 1.7.1「K1 稳定起身」【推断】；Demo 1.7 默认 kV2 |
| `EnterWBCGait/ExitWBCGait` | 有 | 有 | 有 | `b1_loco_client.hpp:637,646` | 可用 |
| `SwitchGait` + `GaitType`（含 `kWholeBodyHumanlikeGaitV2=3`） | 0–2 | 0–3 | 0–3 | `b1_loco_client.hpp:721`；`b1_loco_api.hpp:69-74` | 3 对应 1.7.1「K1 敏捷步态」【推断】 |
| `LieDown()` 的 K1 零位警告 | 只标 unstable | **只标 unstable** | 有 | `b1_loco_client.hpp:272-279` | K1 上仍然禁止调用 |
| `Shoot()` | 有 | 有 | 有 | `b1_loco_client.hpp:308` | K1 上能否用【待实机验证】 |
| `Move` / `MoveCommand` | 有 | 有 | 有 | `:204` / `:210` | 可用 |
| `RotateHeadWithTime`（2043） | 无 | 有 | 有 | `b1_loco_api.hpp:63,102-132`；`b1_loco_client.hpp:240` | 需 ≥ 1.7.1。1.8.0 前 kSoccer 追球有 CAN 掉线问题，用较长的转头时间可能减轻【推断】 |
| `ResetOdometry`（2031）/ `ResetOdometryTo` | 有 / 无 | 有 / **无** | 有 / 有 | `b1_loco_client.hpp:577` | 只能清零 |
| `GetSensors/GetHands/GetRobotModel`（2044–2046） | 无 | 有 | 有 | `b1_loco_api.hpp:64-66`；`b1_loco_client.hpp:138,159,181` | 需 ≥ 1.7.1 |
| `GetTrainedTrajStatus`（2047）、`HandOnChestGreeting`（2050）；LocoApiId 上限 | 无；2042 | 无；**2046** | 有；2050 | `b1_loco_api.hpp:22-67` | — |
| `WaitForOperationService`、`AsyncSendApiRequest`、`RpcCallMode` | 无 | **无** | 有 | `rpc/` 下没有 `rpc_operation_*.hpp`；`RequestHeader` 只有 `api_id`、`expect_response`（`rpc/request_header.hpp:10-53`） | 没有异步动作回调 |
| 返回码 503 `kRpcStatusCodeLowBattery` | 无 | **无** | 有 | `rpc/error.hpp:8-16`（到 502） | 固件会不会返回 503【待实机验证】 |
| `MoveController` / `ArmController` | 有 | 有 | 有 | `b1/move_controller.hpp:26`；`b1/arm_controller.hpp:296`（`kJointCnt`=23） | ArmController 在 K1 上仍按 23 个关节 |
| `kJointCntK1=22`、`JointIndexK1` | 有 | 有 | 有 | `b1/b1_api_const.hpp:143`、`:64` | 可用 |
| 话题 `rt/joint_ctrl`…`rt/kick_ball`（12 个常量） | 有 | 有 | 有 | `b1_api_const.hpp:10-21` | 可用 |
| `rt/odom`、`rt/imu/data`、`rt/joint_states` | 无 | 有 | 有 | `b1_api_const.hpp:22-24` | 需 ≥ 1.7.1 |
| `rt/trained_traj_status` | 无 | **无** | 有 | — | — |
| `rt/button_event` | 仅 IDL | 仅 IDL | 仅 IDL | `idl/b1/ButtonEvent.h` | 话题名要手写 |
| IDL `LowCmd/MotorCmd/LowState/MotorState/ImuState/Kick/FallDownState/RobotStates/RemoteControllerState/Odometer` | 有 | 有 | 有 | `include/booster/idl/b1/*.h` | SDK17 与 SDK18 成员相同；与 SDK16 只差 MD5 成员和命名空间，线上格式兼容 |
| `HandEyeCalibClient` / `CameraClient::GetCameras` / `SetLEDLightColors` | 无 | 有 | 有 | `vision/handeye_calib_client.hpp:14`；`camera/camera_client.hpp:15,34`；`device/light/light_control_client.hpp:54` | 需 ≥ 1.7.1 |

`9759632`（T2 1.7.3）只给 T2 加了 2047/2050 和注释；K1 以 `d5d8f7a` 为准【已核实】。

### 1.2 构建与依赖

| 项 | SDK16 | SDK17（= SDK18） |
|---|---|---|
| Fast DDS | 标准 eProsima 2.13.1，命名空间 `eprosima`，`libfastrtps.so`/`libfastcdr.so` 动态库 + `libfoonathan_memory-0.7.3.a` | 头文件在 `include/booster_fastdds/`，命名空间 `booster_eprosima`，**静态**打进 `lib/<arch>/libbooster_robotics_sdk.a`；没有 `third_party/` |
| profile 环境变量（`.a` 的 strings） | 只有 `FASTRTPS_DEFAULT_PROFILES_FILE` | 另有 `BOOSTER_FASTRTPS_DEFAULT_PROFILES_FILE`、`BOOSTER_FASTDDS_BUILTIN_TRANSPORTS`、`BOOSTER_FASTDDS_ENVIRONMENT_FILE`；`Init(0,"")` 读的是 `FASTRTPS_DEFAULT_PROFILES_FILE`（依据 PyPI 1.3.9 源码 `dds_factory_model.cpp:41-52`）【推断】 |
| QoS | — | `SetWriter/SetReader` 用构造时拷贝的默认 QoS（`common/dds/dds_factory_model.hpp:76,94,112-113`），**XML profile 里的 QoS 很可能不生效**；SDK18 改成 `get_default_*_qos()` 并注释了原因【推断】 |
| install.sh | 只认 22（其它走 `lib/<arch>/<ver>`）；apt 装 ssl/asio/tinyxml2；拷贝 third_party | 只接受 22.*/24.*（:13-23）；apt 装 build-essential、cmake（:29-32）；拷贝 `include/*`、`lib/<arch>/*`（:46-47）。输出 "Booster Robotics SDK installed successfully!" |
| CMake 链接 | `booster_robotics_sdk.a fastrtps fastcdr libfoonathan_memory-0.7.3.a` | `"${BOOSTER_SDK_LIBRARY}" Threads::Threads ${CMAKE_DL_LIBS} rt`（:41），C++17 |
| Python 绑定源码 | 仓库里有 | 没有（README 说明通过 pip 单独发布） |
| 其它 | — | 删除了几个头文件里的全局 `using namespace booster::robot;`，依赖它的旧代码会编译失败；`DdsDedicatedCallbackExecutor` 有初始化竞态（只在 `kDedicated` 模式出现，默认 `kShared`），SDK18 已修 |

- D17 的 `src/vision/src/CMakeLists.txt:9` 仍链接 `booster_robotics_sdk.a fastrtps fastcdr`：配 SDK17 时后两项多余，会链接到 `/usr/local/lib` 里可能残留的 1.6 版 `.so`。SDK17 的 install.sh 不会清理它们，用 `ldd install/vision/lib/vision/vision_node` 核对【推断】。

### 1.3 Python（PyPI `booster_robotics_sdk_python`）

- 版本与日期（UTC）：1.3.5 04-20；1.3.6 05-08；1.3.7 06-17；**1.3.9 06-22（只有 sdist）**；**1.5.6 07-08（只有 wheel，cp310–cp314，manylinux_2_34，x86_64/aarch64）**；1.6.1 08-24；1.6.3 09-16。
- **1.5.6 = SDK17 层级**（字符串指纹：有 `kGetSensors`、`GetUpVersion`、`kWholeBodyHumanlikeGaitV2`、`booster_eprosima`；没有 Operation RPC、`TrainedTrajStatus`、`ResetOdometryTo`、`LowBattery`）【已核实：字符串层面】。导出 `kJointCntK1`、`B1FallDownStateSubscriber`、`B1RobotStatesSubscriber`、`B1RemoteControllerStateSubscriber`、`B1VisualKickReferencePublisher`、`GetUpVersion`，另有 `B1RosOdometry/RosImu/RosJointState`、`B1ButtonEvent`、`B1RobocupBehaviorStatus`、`B1ProneBodyControlStatus` 订阅类。
- **`b1-cli` 入口拼错**（`entry_points.txt:3` 指向 `sdk_pybind_b1_exmaple`，实际文件是 `..._example.py`），不能启动。改用 `python3 -m python_example.sdk_pybind_b1_example <ip>`。
- 1.3.9 sdist 的 C++ 部分与 SDK17 逐字节相同，但它的 Python 绑定用旧头文件编译：`GetUp()` 无参、没有 `GetUpVersion`/`kJointCntK1`/订阅类。**不要用在固件 1.7 上。**
- 建议：`pip install booster_robotics_sdk_python==1.5.6`（Ubuntu 22.04 的 glibc 2.35 满足 manylinux_2_34）。

---

## 2. 固件 1.7.x 与 1.8 的差异、发放的升级包

### 2.1 发放的升级包 `1.7.2.0-dev-yunlong-1-7-2026-06-01-hM193-00464-2026-08-18.22.04.aarch64.single.run`

包没有执行过，只流式列出了内容（4510 项），并单独解出了几个脚本【已核实】。

| 项 | 结论 |
|---|---|
| 类型 | Makeself 2.4.5 自解压包（标签 "Booster Installer"），载荷是 zstd 压缩的 pax tar；解压后执行 `./install.sh`（要求 root） |
| 大小 | 压缩 3.26 GiB，**解压约 5.7 GiB，默认解到 `/tmp`，空间不够会直接退出** |
| 完整性 | 包头只有 MD5，没有签名；本地载荷 MD5 与包头一致。上传到机器人后可用 `sh <file>.run --check` 只做校验、不安装 |
| 解出的 version.txt | `Version: 1.7.2.0-dev-yunlong-1-7-2026-06-01-hM193-00464-2026-08-18`；`Branch: ci-build-yunlong-1-7-2026-06-01.hM193-2026-08-17.xm128.2026-08`；`Commit ID: 263509d0…` |
| 文件名含义 | `1.7.2.0` 版本；**`dev` 开发渠道**（官方正式包是 `release`）；`yunlong-1-7-2026-06-01` 是 2026-06-01 切出的 1.7 CI 分支；`00464` CI 构建号；`2026-08-18` 构建日期；`single` 单板机型。没有官方包名里的 `global`/`unsealed`，CI 路径是 `china-single`，推断是国内版 |
| 与公开 1.7.2 的关系 | 官方 1.7.2 GA 是 2026-08-04（`booster_docs/changelog__v1-7-2-firmware-release.md:10`），这个 dev 包晚两周构建，可能带了回合修复，包里没有 changelog，无法核实【推断】。**全队必须装同一个包** |

**install.sh 的行为（按顺序）**：
1. **必须联网**：`apt update` 失败直接退出；还要 apt 安装一批依赖，并在 `~/python-v-env` 里 `pip install toml`（pip 源写死为阿里云，写进 `~/.pip/pip.conf`）。**不能离线安装**。
2. **停运控**：停掉 booster-daemon、joystick、感知、电池、RTC、LUI、音频等服务，删除 `/opt/booster` 下的旧目录。从这一步起关节不出力，**必须上支架或平放**。
3. 感知：安装手眼标定（BoosterAutoHandeyeCalib）、人脸检测、**BoosterAgent（内置 Soccer Agent 1.0.2）**；`booster_robotics_sdk_python-1.5.6` wheel **只装进手眼标定的 venv**；整体替换 `/opt/booster/{bin,config,lib,ros2,env,share}`。
4. 运控，**会覆盖本地数据**：
   - 按机型版本覆盖 `/opt/booster/configs/*`，旧文件备份到 `/opt/booster/configs/.config/<时间戳>/`；
   - **覆盖 `/opt/booster/Gait/configs`（包括 F1 键配置 `task_instruction.yaml`），不备份**；
   - **清空 `/var/lib/bluetooth/*`**（备份到 `/var/lib/bluetooth_backups`），手柄等蓝牙配对会丢失。
5. 安装 `/usr/local/bin/booster-cli`；`booster-daemon.service` 改为软链接，指向 `/opt/booster/config/systemd/`；启动并 enable booster-daemon、btmon、joystick_ros2。
6. 系统层面：配置 NetworkManager/uap0；**stop + disable dnsmasq 和 hostapd**；设置 isolcpus（8 核时为 5-7）；Ubuntu 22.04 上把网卡改名为 `usb_eth0`；**更新内核**：机型为 "Booster K1 Orin NX" 时装 5.15.148-rt-tegra（对应 L4T R36.4，即 JetPack 6.1/6.2【推断】），更新前会备份旧内核，并生成回滚脚本 `/opt/booster/restore_kernel_<时间戳>.sh`。
7. **可能自动重启**：内核、网卡、CPU 或 NXP 驱动任何一项有变化，就 `sleep 5` 后 `reboot`。从旧固件升级基本都会重启。
8. **没有版本检查**，也不阻止降级。
9. `/opt/booster/version.txt` 是**追加写入**：每次安装先写分隔线 `------------------`，再写 version.txt 和 `Install time`。**核对版本时要看最后一段**：`tail -n 5 /opt/booster/version.txt`。
10. **不创建也不删除 `/opt/booster/vision.yaml`**，但仍建议升级前备份它，以及 `~/Workspace`、自定义配置。

### 2.2 包内与比赛相关的组件

- **不含 C++ SDK**：没有 `booster_robotics_sdk` 的头文件或库，也不写 `/usr/local/include`。C++ SDK 要单独装 `sdk_release`（`event-sop.md` §5）。
- **内置 Soccer Agent 1.0.2**（`agents/com.boosterobotics.soccer-1.0.2_{jetpack_6.0,jetpack_6.2,qnn_1.0}.agent`，`gait:"robocup"`，`agent_api_level 10700`）：自带 brain/vision/game_controller 节点和 BT。它的 launch **会读 `/opt/booster/vision.yaml`**（传 `vision_config_path='/opt/booster'`），相机类型取自 `/opt/booster/perception_info.yaml`。这与 Demo 1.7 的 `start.sh` 不同，这也是讲义说「`/opt/booster/vision.yaml` 优先」的来源【推断】。Demo 1.7 的 `start.sh` 会禁用 `booster-agent-manager`，两者不会同时跑。
- **ROS 2 RPC 桥存在**：`/opt/booster/ros2/booster_rpc_bridge`，由 `start_rpc_service.sh` 启动，`topic_prefix: 'LocoApiTopic'`、`service_name: 'booster_rpc_service'`，消息类型 `booster_msgs/RpcReqMsg`/`RpcRespMsg`。Demo 1.7 发往 `LocoApiTopicReq` 的请求在 1.7.2 上有接收端（`issues.md` V14 大部分确认）。
- `/opt/booster/BoosterRos2/fastdds_profile_udp_only.xml` 存在（Demo 1.7 `start.sh:23` 依赖它）。ROS 2 为 Humble。
- 运控二进制的字符串里有 `rt/LocoApiTopic`、`rt/kick_ball`、`rt/robocup_behavior_status`、`RobocupMode`、`VisualKickV1BodyControl`、`K1_odom_model_visionkick`；**找不到** `rt/trained_traj_status`、`ResetOdometryTo`（只扫了几个主要库，属指示性证据）。

### 2.3 内部接口 ID（从 `lib/motion/libmodule_source.so` 的 DWARF 读出）

枚举 `booster_internal::robot::b1::LocoInternalApiId`：kMoveToTargetInternal=100000、KHighKick=100001、kHandAction=100002、kSquatAction=100003、kStanceAction=100004、kChangeControlMode=100005、kSetHandActionParams=100006、kStandUp=100007、**kEnableRobocupWalkMode=100008**、kGoalieSquatDown=100009、kEnableVisualKickMode=100010、**kRLKickBall=100011**、**kRLFancyKickBall=100012**、kPushUp=100101、kGoalieDown=100103、kGoalieUp=100104、kReplayTrajectoryWithData=100105、kAxisMove=100106、kChangeModeWithDefaultGait=100204。其中 100011/100012 与 Demo 1.7 自己定义的常量一致（`D17:src/brain/src/robot_client.cpp:15-16`），可以相互印证。**这些是未公开接口，行为和参数没有文档，只按 Demo 已有的用法调用。**

### 2.4 Changelog 对照：1.7.2 上有什么、缺什么

快照里没有 v1.7.0、v1.7.3 的页面；`booster_docs/developer-guide__cpp__rpc.md:11` 规定没有单独标注版本的接口按 ≥ v1.7.1.0 处理，1.7.2 满足。`CL171`/`CL172`/`CL180` = `booster_docs/changelog__v1-7-1-firmware-app-release.md`/`changelog__v1-7-2-firmware-release.md`/`changelog__v1-8-0-firmware-app-release.md`。

| 变更 | 版本 | 在 1.7.2 上 |
|---|---|---|
| K1 敏捷人形步态 + 稳定起身及其 API（`CL171:24`） | 1.7.1 | ✅（对应 `GaitType 3`、`GetUpVersion::kV2`） |
| 里程计、IMU、电机发布标准 ROS 2 消息（`CL171:28`） | 1.7.1 | ✅（`rt/odom`、`rt/imu/data`、`rt/joint_states`） |
| 设备元数据 API（`CL171:30`）；控制链路降延迟（`:32`） | 1.7.1 | ✅ |
| App 做 K1 手眼标定（`CL171:16`） | 1.7.1 | ✅ |
| 修复 IMU 异常导致摔倒、灯带青色无法启动、教育版 Wi-Fi 断连（`CL171:36-40`） | 1.7.1 | ✅ |
| 优化 K1 Get Up 稳定性（`CL172:14`） | 1.7.2 | ✅（1.7.2 唯一的变更） |
| **进入 Custom Mode 后默认保持站立**（`CL180:35`） | 1.8.0.9 | ❌ `ChangeMode(kCustom)` 前必须预发保持帧并持续发送，或者先把机器人吊起来 |
| `ResetOdometryTo`（`CL180:41`） | 1.8.0.9 | ❌ 只能 `ResetOdometry()` 归零，在自己的代码里叠加偏移 |
| 动作状态回调、`GetTrainedTrajStatus`、`rt/trained_traj_status`（`CL180:44`） | 1.8.0.9 | ❌ 只能轮询，或看 `rt/robocup_behavior_status` |
| **修复 Visual Kick V1 模式里程计不更新**（`CL180:48`） | 1.8.0 | ❌ 缺陷仍在（除非 dev 包回合过，未核实）。Demo 默认 kV2，保持 |
| **修复 K1 足球模式头部高速追球时 CAN 掉线**（`CL180:50`） | 1.8.0 | ❌ 缺陷仍在：限制头部角速度和指令频率，赛前做长时间追球压力测试（`issues.md` V8） |
| 修复调用 `MoveHandEndEffectorV2` 后头部控制失效（`CL180:54`） | 1.8.0 | ❌ 不要用这个接口 |
| C++ SDK 1.6.3 的全部新接口（`developer-guide__cpp__changelog.md:10-16`） | 需要 ≥ 1.8.0.9 | ❌ |

**升级到 1.8 的取舍**：讲义允许 1.8，可以修掉 CAN 掉线、kV1 里程计冻结，并带来 Custom 自动站立；但 Demo 1.7 是按 1.7 验证的。App OTA 和 `booster-cli upgrade` 会装最新正式版（目前 1.8.0.9）。**不要混用**：要么全队 1.7.2 dev 包，要么全队 1.8。

---

## 3. Demo 1.7（`D17`）与公开代码的关系

### 3.1 谱系【已核实，比对脚本和中间结果在会话 scratchpad，结论如下】

- **不属于 main / v1604 / gc2026 / autocal 这条线**，属于 `origin/sandbox/feat/k1_3v3_demo`（2025 年 K1 3v3 官方 demo，tip `d2e326e`，src 与 `96ed289` 相同）→ Booster 内部仓 → `origin/sandbox/support_T2`（`2d56d36`，2026-09-04）这一条线。D17 更可能是内部仓 2026-08 前后的快照。
- 在全部 75 个公开提交里，与 D17 `src/` 相同文件最多的是 3v3（137 个相同、48 个不同），`support_T2` 次之（100 个相同），main 线只有 63 个相同。按 brain 代码行归属（12965 行）：52% 在 3v3 里已有，18% 只在 T2 里有，0.5% 只在 v1604/autocal 里有，**29% 在任何公开提交里都没有**。
- 逐文件看：`brain.cpp`、`brain_tree.cpp`、`robot_client.cpp`、`config.yaml`、`vision_node.cpp` 最接近 3v3；`locator.cpp`、`brain_tree.h`、`vision/launch.py` 最接近 T2；`game_controller_node.cpp` 是重写的（与任何提交都差约 300 行）。
- 9 个文件是 CRLF 换行（`brain.cpp/.h`、`types.h`、`locator.h/.cpp`、brain `main.cpp`、brain `launch.py`、两个 GC 头文件）。`src/brain/src/brain.cpp` 和 `src/brain/config/config.yaml` 的修改时间是 2026-09-11，比其余文件（08-06 至 08-20）晚。
- 结论：**`robocup-demo.md`（按 main 写）和 `robocup-demo-branches.md` 的行号、函数位置对 D17 大多不成立**，改代码时直接读 `refs/K1_5v5_demo_1.7`。main 线的整体架构（三节点、BT、`LocoApiTopicReq`）仍然适用。

### 3.2 D17 的关键改动（相对 3v3 / main）

| 模块 | 改动 | 位置（D17） |
|---|---|---|
| GC 接收 | 按包长区分：688 B → HL v12（要求 version 12），158 B → HSL v20（要求 version 20）；先校验 `RGme` 头，再过白名单；v20 经 `toLegacySecondaryState` 映射成旧编号，`secondary_state_info[0]=kickingTeam`、`[1]=stopped?0:1`；`SENT_OFF`(12) 视为红牌 | `src/game_controller/src/game_controller_node.cpp:94-145,243-303`；`include/game_controller_protocol_v20.h` |
| GC 消息 | `GameControlData.msg` 新增 `stopped`/`game_phase`/`set_play`，时间字段改为 int16；`TeamInfo` 新增 `goalkeeper`、`goalkeeper_colour`、`message_budget` | `src/robocup_ros2_interface/src/game_controller_interface/msg/` |
| GC 白名单 | **默认开启**，只放行 `172.169.80.24` | `src/game_controller/launch/launch.py:21-26` |
| brain 状态机 | `state` 越界检查；v20 的 `game_phase` 1/2 标成 PENALTYSHOOT/OVERTIME、按正常比赛处理；v20 定位球：`stopped`→STOP，我方→PLAY（沿用进攻树），对方→GET_READY，`set_play` 回到 0 视为 Ball Free；v12 子状态有越界保护 | `src/brain/src/brain.cpp:2010-2223`、`:1260-1331` |
| GC 回包 | 收到第一个 GC 包、确定版本后才开始发；v20 回 `RGrt` v4（32 B，`fallen` 0/1、位姿 mm、球），v12 回 v2 ALIVE；1 Hz | `src/brain/src/brain_communication.cpp:65-114`；`include/brain_communication.h:19,51` |
| 队内通信 | 改为广播 `255.255.255.255:10000+team_id`，**每 100 ms 一条**，**不读 `message_budget`** | `brain_communication.cpp:117-215`；`brain_communication.h:65` |
| 守门员 | 动态守门员 `selectGoaliePlayerId`；通信不完整时沿用 GC 的守门员号（GC 默认 1 号） | `brain.cpp`；`config.yaml:100-107` |
| 起身 | `kGetUp`，body `{"version":0|1}`（kV1/kV2），由 `recovery.get_up_version` 配置（默认 kV2） | `robot_client.cpp:64-89`；`brain_config.cpp:264-274` |
| 视觉踢球 | API 2038，body `{"start":b,"version":0|1}`，由 `RLVisionKick.visual_kick_version` 配置（默认 kV2）；`robocupWalk` 改为只发 `VisualKick(false)`；`changeRobocupMode` = `ChangeMode(kSoccer)` + `VisualKick(false)` | `robot_client.cpp:126-167` |
| 内部 API | include `booster_internal/robot/b1/b1_loco_internal_api.hpp`（**不在任何公开 SDK 里**），用 `kEnableRobocupWalkMode`（=100008，只在从未调用的 `walkMode()` 里用）；`kickBall`/`fancyKickBall` 用内部 API 100011/100012 | `robot_client.cpp:3,14-16,91-124` |
| 最小速度 | ⚠ `setVelocity` 的最小速度从 0.05/0.08/0.05 改成 **0.3/0.3/0.3**：小于 0.3 的非零速度指令会被抬到 0.3，靠近目标点时可能来回抖动 | `robot_client.cpp:195-200` |
| 头部 | pitch 下限写死 0.2（3v3 是 0.45），不能用 yaml 配置 | `include/brain_config.h:86`；`robot_client.cpp:55` |
| 行为树 | 新增 `RLVisionKick`、`MoveToFarSetPlaySearchArea`、`KickoffStand`、`Analyze2`、`GoalieIdleHome`、`Intercept2`、`RoleSwitchIfNeeded`、`AutoCalibrateVision` 等节点；删除 `GoalieDecide`；SelfLocate* 从 `locator.cpp` 搬到 `brain_tree.cpp`；新增点球守门子树 | `src/brain/src/brain_tree.cpp`；`behavior_trees/subtrees/subtree_goal_keeper_penalty_kick.xml` |
| 配置 | 3v3 的键全部保留，另增 95 个（`auto_visual_kick.*`、`goalie_simple_*`、`cooperation.goalie_*`、`far_set_play_search.*`、`set_play_stand.*`、`ball_predictor.*`、`debug.low_frequency_status.*` 等）；场地 `robo_league` = 22.003×14.126 | `src/brain/config/config.yaml`；`include/types.h:37` |
| 视觉 | `vision_config_path` 默认为空，即用包内 config（`start.sh` 不再像 3v3 那样传 `/opt/booster`）；优先用 `camera_info_topic` 里的内参，3 s 等不到再用 yaml；`save_data:=false` 时 logger 判空；新增 `vision_d.yaml`（d-robotics）；球尺寸可选 | `src/vision/launch/launch.py:8-20`；`src/vision/config/vision.yaml:1-4`；`src/vision/src/vision_node.cpp:281-284` |
| 脚本 | `build.sh` 去掉 `--symlink-install`；`start.sh` 会 `pkill -9 python3`、禁用 `booster-agent-manager`、mask apt；sound 节点已注释 | `scripts/build.sh:9`；`scripts/start.sh:9-44` |
| 接口包 | `booster_ros2_interface` 是精简版（没有 ButtonEvent/FallDownState/Hand*/AgentService，也没有模板 `CreateMsg`）；RPC 走 `booster_msgs/RpcReqMsg` 发到 `LocoApiTopicReq` | `src/booster_ros2_interface/`；`src/booster_msgs/` |

### 3.3 旧 bug 在 D17 中的状态

| # | 问题（出处 `robocup-demo.md` §6.2） | D17 状态 | 位置 |
|---|---|---|---|
| B1 | `SelfLocate2X` 的 `dy` 应为 `-(p0.y+p1.y)/2` | **仍存在**（代码搬到了 brain_tree） | `src/brain/src/brain_tree.cpp:3361` |
| B2 | `SelfLocatePT` 两个条件都在比较 x | **仍存在** | `brain_tree.cpp:3673-3674` |
| B3 | `SelfLocatePT` 模板点用 `fd.length`，应为 `fd.length/2` | **仍存在** | `brain_tree.cpp:3702` |
| B4 | `SelfLocateLT/PT` 内层循环在另一个数组上从 `j=i+1` 开始 | **仍存在** | `brain_tree.cpp:3551`、`:3669` |
| — | 以上是否会执行 | 会：`subtree_locate.xml:9-11` 在 READY/SET/定位球阶段都会调用（`game.xml:67,74,103,108,114`） | — |
| B5 | `gameStateMap` / `gameSubStateMap` 越界 | 已修 | `brain.cpp:2030-2033`、`:2118-2121` |
| B6 | 加时、点球大战落到 FREE_KICK | **v20 已修**（`brain.cpp:2091-2094`）；v12 下 `secondary_state` 1/2 仍落到 default `UNKNOWN_SET_PLAY`（:2084-2087）。本赛事用 v20，影响不大 | — |
| B7 | `save_data:=false` 时 `data_logger_` 空指针 | 已修 | `src/vision/src/vision_node.cpp:281-284` |
| B8 | 头部 pitch 下限 0.45 截断找球角度 | 已修（写死 0.2） | `brain_config.h:86` |
| B9 | `image_camera_info_topic` 指向图像话题 | 不再适用：brain 已没有这个键 | `vision.yaml:3` |
| B10 | 对方开球 SET 阶段本地切到 PLAY（×100、+100 m，`issues.md` D8） | **不存在**：`gc_game_state` 只由 GC 写入（`brain.cpp:2035`） | — |
| B11 | 替补判断用 HL 常量 `SUBSTITUTE`=14，v20 是 13 | 新问题，影响小（`issues.md` D7） | `brain_communication.cpp:320` |
| B12 | 队内通信 10 Hz 不看额度 | **新问题，会导致比分清零**（`issues.md` T10） | `brain_communication.h:65` |

---

## 4. 其它参考文件的勘误清单

「原结论」是摘要；文中对应位置已插入【fw1.7 #N】。行号以 2026-09-24 的文件为准，会随编辑漂移，搜 `【fw1.7 #N】` 最准。

| # | 文件 | 小节 | 原结论 | 在 1.7 栈下的修正 |
|---|---|---|---|---|
| 1 | sdk-api.md | 页头 | SDK 快照为 `87a9a26`（1.6.3） | 1.7 栈用 `d5d8f7a`（= `sdk_release.zip`）；Python 用 1.5.6 |
| 2 | sdk-api.md | §0 #5、§3.11 | 有返回码 503，头文件里有 | `d5d8f7a` 到 502 为止 |
| 3 | sdk-api.md | §0 #7、§3.6 | 「头文件明确说明」K1 上 LieDown 执行零位轨迹 | 这条警告只在 SDK18 里；SDK17 只写 unstable。禁止调用的结论不变 |
| 4 | sdk-api.md | §0 #10、§8 #11 | 当前仓库对应固件 1.8.0，PyPI 1.6.3 | 本队 1.7 栈 = SDK17 + Python 1.5.6 |
| 5 | sdk-api.md | §1.3 | header 里有 `call_mode/req_id/operation_command` | 只有 `api_id`、`expect_response` |
| 6 | sdk-api.md | §1.3、§1.5 表、§3.1 | `RpcCallMode`、`kOperation`、`rt/LocoApiOperationEvent`、Async 系列接口 | SDK17 都没有 |
| 7 | sdk-api.md | §2.2 | PyPI 最新 1.6.3 | 固定 `==1.5.6`；它的 `b1-cli` 同样坏；不要用 1.3.9 |
| 8 | sdk-api.md | §3.2 | kCustom 在 ≥ v1.8.0.9 时保持站立 | 1.7 上不会，必须先预发保持帧 |
| 9 | sdk-api.md | §3.3 | 可用 `ResetOdometryTo` | 没有，只能 `ResetOdometry()` |
| 10 | sdk-api.md | §3.5 | kV2「开启 WBC 走 WBC 路径，否则回退」 | SDK18 的注释；SDK17 写的是「stronger kicking force」，实际行为由固件决定 |
| 11 | sdk-api.md | §3.8、§5 | 有 `GetTrainedTrajStatus`、`rt/trained_traj_status`、`B1TrainedTrajStatusSubscriber` | SDK17 和 Python 1.5.6 都没有 |
| 12 | sdk-api.md | §3.10 | LocoApiId 到 2050 | 到 2046 为止 |
| 13 | sdk-api.md | §3.1 最低固件、§4 表 | GaitType 3、RotateHeadWithTime、GetUpVersion kV2、设备元数据、手眼标定、SetLEDLightColors 可用 | 头文件都有，但要求固件 ≥ 1.7.1；1.7.0.x 上先实测返回码 |
| 14 | low-level-control.md | §0 固件行、§6.5 | 固件 ≥ v1.8.0.9 进入 Custom 会保持站姿 | 1.7 上不会，预发保持帧必不可少 |
| 15 | low-level-control.md | §1.2 QoS 基线 | SDK 用 `get_default_datawriter_qos()`，从 XML 取 QoS | SDK17 用构造时拷贝的默认 QoS，XML profile 很可能不生效【推断】；引用行号是 SDK18 的 |
| 16 | low-level-control.md | §1.2 环境变量 | 哪个变量生效待实机验证 | `Init(0,"")` 读 `FASTRTPS_DEFAULT_PROFILES_FILE`【推断】 |
| 17 | low-level-control.md | §1.3 | 有 `rt/trained_traj_status`；常量引用 `b1_api_const.hpp:26-113` | SDK17 没有该话题；常量在 `:10-24` |
| 18 | low-level-control.md | §1.4 | GetUp body「—」，GetUpWithMode 为 `{"mode":…}` | SDK17 发 `{"version":v}` / `{"mode":m,"version":v}` |
| 19 | low-level-control.md | §1.4 | 可用 GetSensors / GetRobotModel | 需固件 ≥ 1.7.1 |
| 20 | low-level-control.md | §1.4 | API id 来源 `b1_loco_api.hpp:90-137` | SDK17 为 `:22-67`，最大 2046 |
| 21 | low-level-control.md | §1.4 错误码、§4.6 | RPC 会返回 503 | SDK17 未定义 503，固件是否返回待验证 |
| 22 | low-level-control.md | 各处行号 | `b1_api_const.hpp:27/30/212-214`、`arm_controller.hpp:383`、`b1_loco_client.hpp:268`、`channel_factory.hpp:37-44`、`rpc_client.hpp:30,46` | SDK17 对应 `:10/:11/:141-143`、`:296`、`:174`、`:29-32`、`:23,:35`（数值相同）；`b1_loco_api.hpp:68` 的 robot-state-manager 说明在 SDK17 里没有（未逐行插标注） |
| 23 | low-level-control.md | §4.1、§4.5 | DEP 默认退到 Walking；v1.7.1 修复 IMU 异常 | DEP 要求 ≥ 1.7.2，1.7.2.0 满足；1.7.0 上 IMU 问题仍在。先确认小版本 |
| 24 | robocup-demo.md | §0.2 GC 行、§4、§6.2 #2、§8 | GC 1.0.1（HL v12）与 main 兼容，不需要换分支 | 本赛事是 GC 7.0.0-rc.3（v20），main 收不到；用 Demo 1.7（双协议） |
| 25 | robocup-demo.md | §6.2 | 已知 bug 清单（按 main 行号） | Demo 1.7 中的状态见 §3.3：定位 bug 仍在（搬到 `brain_tree.cpp`），GC 越界、save_data、pitch 下限已修 |
| 26 | robocup-demo.md | §2.4 | main 不读 `/opt/booster/vision.yaml` | Demo 1.7 同样不读；标定程序直接改写 `src/vision/config/vision.yaml` |
| 27 | robocup-demo.md | §0.2 队内通信行、§3.8 | UDP 单播 | Demo 1.7 改为广播，但 10 Hz 会耗尽 GC 额度（`issues.md` T10） |
| 28 | robocup-demo.md | §3.9、§5.2、§5.3 | main 的参数表、`git lfs pull`、`--symlink-install`、`start.sh` 行为 | Demo 1.7 多 95 个键、默认值不同；engine 随 zip 附带；不带 symlink；`start.sh` 有额外副作用；只能在机器人上编译 |
| 29 | rl-sim-deploy.md | §0 #2、§4.6 | booster_deploy 要求 ≥ v1.7.2，「建议用最新固件」 | 1.7.2.0 满足；`exit_mode="walking"` 先吊架实测，默认 damping |
| 30 | rl-sim-deploy.md | §6 | 固件 v1.7 默认不带 boosteros | 本队固件 1.7：先 `pip install boosteros`；Demo 的 `start.sh` 会禁用 `booster-agent-manager`，Agent 与 Demo 不要同时跑 |
| 31 | k1-operations.md | §6.2 | 「离线包」：scp 后 `sudo ./<pkg>.run` | `.run` 包**必须联网**（apt/pip，失败即退出）；增加主办方流程和 `--check` 校验 |
| 32 | k1-operations.md | §6.2 | 在线命令 / App 升级 | 会装最新正式版（1.8.0.9）；全队必须同一版本，不要与 1.7.2 dev 包混用 |
| 33 | k1-operations.md | §6.2 升级前准备 | 备份配置和 vision.yaml | 1.7.2 包还会覆盖 `configs/*`、**覆盖 Gait 配置（含 F1 键）且不备份**、清空蓝牙配对、禁用 hostapd/dnsmasq、更新内核并可能自动重启 |
| 34 | k1-operations.md | §6.1、§8.1 #4 | `cat /opt/booster/version.txt` 看版本 | 文件追加写入，看最后一段；dev 包写的是 `1.7.2.0-dev-…` |
| 35 | k1-operations.md | §4.2 JetPack | JetPack 版本未知 | 1.7.2 包装内核 5.15.148-rt-tegra（L4T R36.4 → JetPack 6.1/6.2，推断） |
| 36 | k1-operations.md | §6.3 | 1.6.3 新接口 ≥ 1.8.0.9；booster_deploy 两种说法 | 1.7.2 上 1.6.3 新接口不可用；booster_deploy 两种说法都满足；新增 Demo 1.7 的兼容行 |
| 37 | k1-operations.md | §6.4 1.7.2 行 | 优化 K1 Get Up | 本队目标版本；dev 包比 GA 晚两周构建；1.8.0 的修复都不在 |
| 38 | k1-operations.md | §7 CAN 掉线行 | 1.8.0 已修复 | 1.7.2 上仍存在，限速 + 压力测试，或全队升 1.8 |
| 39 | k1-operations.md | §4.2 `/opt/booster/vision.yaml` 行 | 优先于 Demo 配置 | Demo 1.7 不读；固件内置 Soccer Agent 1.0.2 会读 |

---

## 5. 基于 1.7 栈的开发建议

### 5.1 Demo（比赛程序）
1. 在每台机器人上解压 `K1_5v5_demo_1.7.zip` 后先 `git init` 做初始提交；开发机上以 `refs/K1_5v5_demo_1.7` 为对照。在机器人上编译（依赖机器人上的 ROS 2 包与 TensorRT）；如果报找不到 `booster_internal` 头文件，按 §0 #6 删掉 include 和 `walkMode()`。
2. 上场前必改（`event-sop.md` §6.2）：`team_id`、`player_id`、`player_role`、`number_of_players: 3`、`field_type`、`game_control_ip`、GC 白名单、相机对应的 `vision.yaml` 与 `cam_*`。
3. 必须先修（`issues.md`）：T10 队内通信降频（否则比分清零）→ T4 定位 bug → D10 最小速度 0.3 的影响。
4. 可以从公开分支手工移植的：`gc2026` 的哨声检测（依赖 Duerwen 二进制库和 `hw:1,0` 声卡，只有 C12 答复「不勾 No Delay」时才值得做）；`autocal` 的 App 标定结果读取（固件 ≥ 1.7.1 有 App 手眼标定，但 Demo 1.7 自带 `calibration_node`，意义不大）。**不要整分支合并**：Demo 1.7 与 main 线没有共同历史。
5. 不要依赖 `/opt/booster/vision.yaml`；如果想让它生效，就在 `start.sh` 里给 vision 和 brain 都加上 `vision_config_path:=/opt/booster`，并确认该文件包含完整键（模型路径、阈值等）。

### 5.2 SDK
- 机器人上的 SDK 应与 `d5d8f7a` 一致（`issues.md` V4）；只有缺失或编译报版本错误时才运行 `sdk_release/install.sh`。
- 开发机上查头文件用 `refs/booster_robotics_sdk@fw1.7`；`sdk-api.md`、`low-level-control.md` 按 1.8 写的地方先查 §4 勘误。
- **不要在 1.7 的机器人上装 1.6.3（`87a9a26`）的 SDK**：会用 1.8 才有的接口覆盖 `/usr/local/include/booster`。

### 5.3 底层与 RL（1.7 上）
- 进入 Custom：严格按 `low-level-control.md` §4.2 做，**必须先预发保持帧**（自动保持站立 1.8.0 才有）；退出一律切到 PREP 或 DAMP。
- `booster_deploy` 的 README 要求固件 ≥ v1.7.2，1.7.2.0 满足。真机运行前仍要吊架测试 `exit_mode`，并确认 `booster_rpc_service` 存在（`issues.md` V14）。
- 固件 1.7 有 `boosteros`（需 `pip install boosteros`）和 Agent 框架（`min_api_level 10700`）。但 Demo 1.7 的 `start.sh` 会禁用 `booster-agent-manager`，两套不要同时跑。

## 6. 待确认事项

版本与物料相关的待确认项统一记在 `issues.md` 的 V 组（V2 裁判机二进制、V3 固件小版本、V4 机器人上的 SDK、V6 `booster_internal` 头文件、V8 CAN 掉线、V9 kV1 里程计、V10 Custom 保持帧、V12 `booster-agent-manager`、V13 kV2 起身、V14 `LocoApiTopicReq` 桥接、V15 升级后的恢复工作），这里不重复。
