# K1 底层原理与底层控制（DDS / LowCmd / Custom 模式 / RL 部署 / 绕过 SDK）

> ⚠ **本队使用固件 ≥ 1.7 + SDK `d5d8f7a`（`refs/booster_robotics_sdk@fw1.7`，= 主办方 `sdk_release.zip`）+ 主办方 Demo 1.7。** 本文按最新 SDK 1.6.3（`87a9a26`）/ 固件 1.8 撰写；在 1.7 上不同的地方用【fw1.7 #N】标出，完整说明见 `fw1.7-demo-v1.7.md` §4。

> 读者：要绕过 `B1LocoClient.Move()` 这类高层接口，直接发关节指令、自研步态，或部署 RL 策略的开发者。
> 路径约定：除 URL 外都相对于 `refs/`，`:Lnn` 表示行号。来源缩写与 `k1-hardware.md` 相同：`SDK` = booster_robotics_sdk，`DEP` = booster_deploy，`GYM` = booster_gym/deploy（T1 专用，但流程可以借鉴），`TRN` = booster_train/source/booster_train/booster_train，`DOC` = booster_docs，`R2IF` = booster_robotics_sdk_ros2/booster_ros2_interface，`RCD` = robocup_demo，`AST` = booster_assets/robots/K1。
> `⚠待实机验证` 表示文档或源码没有给出明确结论，或者只是推断。关节索引、限位、增益、坐标系见 `k1-hardware.md`；网络与运维见 `k1-operations.md`。

## 0. 一页速查

| 要点 | 结论 | 来源 |
| --- | --- | --- |
| 中间件 | Booster 自带的 Fast DDS 2.x（命名空间改成了 `booster_eprosima`，库名 `booster_fastdds`），线上走标准 RTPS，与 ROS 2 Humble 互通 | `SDK/include/booster/idl/b1/LowCmd.h:29-48`；`DOC/developer-guide__cpp__sdk-overview.md:11` |
| Domain | 0 | `DOC/developer-guide__cpp__architecture.md:19`；`DOC/developer-guide__cpp__quick-start.md:17` |
| 指令话题 | `rt/joint_ctrl`，类型 `booster_interface::msg::dds_::LowCmd_`；ROS 2 中对应 `/joint_ctrl` | `SDK/include/booster/robot/b1/b1_api_const.hpp:27`；库字符串；`DEP/booster_deploy/controllers/booster_robot_controller.py:257-265` |
| 状态话题 | `rt/low_state`，类型 `LowState_`；ROS 2 中对应 `/low_state` | `b1_api_const.hpp:30` |
| 数组长度 | 22（`kJointCntK1`）。官方示例和 ArmController 用的都是 T1 的 23，K1 上**不要照抄** | `b1_api_const.hpp:212-214`；`SDK/include/booster/robot/b1/arm_controller.hpp:383` |
| 推荐 cmd_type | `SERIAL`（idx 14/15 对应踝 pitch/roll，与 URDF 一致），读 `motor_state_serial` | `DEP/.../booster_robot_controller.py:224,270` |
| 生效条件 | 只在 **CUSTOM** 模式下生效；只能从 PREP 或 DAMP 进入 | `DOC/developer-guide__cpp__low-level-topics.md:12`；`DOC/product-manual__k1__basic-operations__modes.md:58` |
| 进入前 | 先用当前角度加较高 kp/kd **预发一帧**，再调 `ChangeMode(kCustom)`；机器人会保留这一帧 | `DEP/.../booster_robot_controller.py:380-392,439-446` |
| 固件 ≥ v1.8.0.9 | 进入 CUSTOM 后先保持站姿，直到收到第一帧有效的 `rt/joint_ctrl`【fw1.7 #14】1.7 上没有这个行为，预发保持帧必不可少 | `DOC/developer-guide__cpp__changelog.md:32`；`DOC/developer-guide__cpp__rpc__motion.md:169` |
| 控制律 | τ = kp·(q_des − q) + kd·(dq_des − dq) + τ_ff，**在机器人侧执行**（不在用户进程里） | §3 |
| weight | Custom 模式下**无效**，官方代码一律置 0 | `GYM/utils/command.py:15`；`DEP/.../booster_robot_controller.py:280` |
| 频率 | 策略 50 Hz；官方 K1 部署只按 50 Hz 发指令，保持位姿或插值时按 500 Hz 发 | `DEP/.../controller_cfg.py:102`；`booster_robot_controller.py:485-492` |
| 看门狗 | 没有文档说明。源码注释表明机器人会**保留最后一帧**；进程崩溃后很可能按最后一帧继续跟踪 | §4.6 ⚠ |

---

## 1. 系统软件架构

### 1.1 分层结构（带「推断」字样的部分没有官方图示）

```
┌──────────────────────────── 用户程序（可以跑在机载 Jetson 上，也可以跑在同一局域网的 PC 上）────────────────────────────┐
│ C++ SDK: ChannelPublisher/Subscriber<MSG>、B1LocoClient(RPC)     Python: booster_robotics_sdk_python / boosteros         │
│ ROS 2 Humble: rclpy/rclcpp + booster_interface（/opt/booster/BoosterRos2Interface）                                    │
└──────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
               │ DDS domain 0，RTPS/UDPv4（机载 profile：/opt/booster/BoosterRos2/fastdds_profile_udp_only.xml）
┌──────────────▼──────────────── Booster 服务层（容器化，用 `bdb container boot-all/kill-all` 管理）──────────────────────────┐
│ robot-state-manager（RPC "loco"，话题 rt/LocoApiTopicReq/Resp）：模式状态机 DAMP/PREP/WALK/CUSTOM/SOCCER/PROTECT          │
│ motion stack（/opt/booster/Gait，内部有 URDF+RBDL 模型）：PREP 的 "PVT" 保持控制器、步态、起身、踢球等 BodyControl          │
│ 「low-level controller」：订阅 rt/joint_ctrl，在 CUSTOM 下保留并执行最后一帧；做串/并联换算；发布 rt/low_state（推断）      │
│ ROS 2 bridge：rt/odom、rt/imu/data、rt/joint_states、rt/tf、/head_pose、booster_rpc_service（ROS 2 service）               │
└──────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
               │ CAN 总线（3P/HSL）
┌──────────────▼───────────┐
│ 关节一体化驱动器（双编码器、力矩反馈，私有驱动板）：执行 PD（推断） │
└──────────────────────────┘
```

依据：
- 服务层用容器管理：`DOC/product-manual__k1__basic-operations__service-control.md:30-42`。
- `robot-state-manager` 以及 "legacy LocoApiService on the same topic"：`SDK/include/booster/robot/b1/b1_loco_api.hpp:68`。
- motion stack 用 RBDL：`SDK/include/booster/robot/b1/b1_loco_client.hpp:268`。
- "PVT" 与 "low-level controller"：DEP 注释 `booster_robot_controller.py:381,390-391,439-451`。
- Gait 目录：`DOC/product-manual__k1__basic-operations__body-operations.md:25`。
- ROS 2 bridge：`DOC/developer-guide__cpp__low-level-topics.md:214-245`、`b1_api_const.hpp:94-113`。
- CAN 与驱动板：`3P/HSL`。

### 1.2 DDS 关键事实

| 项 | 内容 | 来源 |
| --- | --- | --- |
| 初始化 | `ChannelFactory::Instance()->Init(domain_id=0, network_interface)`。第二个参数填 IP：在机器人上跑用 `127.0.0.1`，有线连接用 `192.168.10.102` 这一类；空串表示默认网络配置 | `SDK/include/booster/robot/channel/channel_factory.hpp:37-44`；`DOC/developer-guide__cpp__architecture.md:19` |
| 注册的类型名 | ROS 2 风格：`booster_interface::msg::dds_::LowCmd_`、`LowState_`、`MotorCmd_`、`MotorState_`、`ImuState_`、`FallDownState_`、`Odometer_`、`RobotStatesMsg_`；RPC 用 `booster_msgs::msg::dds_::RpcReqMsg_` / `RpcRespMsg_` | 在 `SDK/lib/aarch64/libbooster_robotics_sdk.a` 上用 `grep -a` 查到 |
| 话题名 | `rt/xxx`，这是 ROS 2 对话题 `/xxx` 的 DDS 名字修饰（mangling）规则，所以 ROS 2 节点订阅 `/low_state` 就是 `rt/low_state` | 同上；DEP 用 `"/low_state"` 和 `"joint_ctrl"`（`booster_robot_controller.py:167,259`） |
| 序列化 | `DEFAULT_DATA_REPRESENTATION`，即 Fast DDS 2.x 默认的 XCDR1，与 ROS 2 Humble 一致 | `LowCmd.h:203-206` |
| QoS 基线 | SDK 创建读写端时，从已加载的 XML 默认 profile 取 QoS（`get_default_datawriter_qos()`）；`reliable=true` 时再改成 RELIABLE。**`reliable=false` 并不是强制 BEST_EFFORT，只是保留默认值**。Fast DDS 2.x 原生默认 writer 为 RELIABLE、reader 为 BEST_EFFORT。官方文档写的是 "default is false, which selects best-effort"【fw1.7 #15】`d5d8f7a` 用构造时拷贝的默认 QoS（`common/dds/dds_factory_model.hpp:76,94,112-113`），XML profile 里的 QoS 很可能不作用到 SDK 的读写端（1.8 头文件注释说这正是改动原因）【推断】；本行引用的行号是 1.8 的 | `SDK/include/booster/common/dds/dds_factory_model.hpp:68-103`；`DOC/developer-guide__cpp__architecture.md:65` ⚠待实机验证实际 QoS |
| 自带 Fast DDS 读取的环境变量 | `BOOSTER_FASTRTPS_DEFAULT_PROFILES_FILE`、`BOOSTER_FASTDDS_BUILTIN_TRANSPORTS`、`BOOSTER_FASTDDS_ENVIRONMENT_FILE`、默认文件名 `DEFAULT_BOOSTER_FASTRTPS_PROFILES.xml`（库里也有 `FASTRTPS_DEFAULT_PROFILES_FILE` 字符串）。改名的目的应该是避免与系统里 ROS 2 的 Fast DDS 冲突【fw1.7 #16】`d5d8f7a` 的库里两组变量都有；`Init(0,"")` 读的是 `FASTRTPS_DEFAULT_PROFILES_FILE`（依据 PyPI 1.3.9 源码 `dds_factory_model.cpp:41-52`，与 `.a` 字符串一致）【推断】 | 库字符串 ⚠待实机验证哪个变量生效 |
| 机载 ROS 2 profile | `FASTRTPS_DEFAULT_PROFILES_FILE=/opt/booster/BoosterRos2/fastdds_profile_udp_only.xml`，只用 UDP，不用共享内存 | `RCD/scripts/start.sh:11` |
| 示例白名单 | `interfaceWhiteList`：127.0.0.1、192.168.10.101、192.168.10.102；`useBuiltinTransports=false` | `RCD/configs/fastdds.xml:4-23` |
| 没有 key、没有时间戳 | LowCmd 和 LowState 都**没有 header 或时间戳**，只能用本地接收时刻计时 | `LowState.h:229-231`；`R2IF/msg/LowState.msg:1-3` |

### 1.3 话题全表（与底层控制相关的）

| DDS 话题 | ROS 2 名 | 消息类型 | 方向 | C++ 常量 | 最低固件 | 备注 |
| --- | --- | --- | --- | --- | --- | --- |
| `rt/joint_ctrl` | `/joint_ctrl` | `LowCmd` | 用户 → 机器人 | `kTopicJointCtrl` | v1.0.0.0 | 只在 CUSTOM 下生效；在 UpperBodyCustomControl 下只有上身生效（§4.7） |
| `rt/low_state` | `/low_state` | `LowState` | 机器人 → 用户 | `kTopicLowState` | v1.0.0.0 | IMU + 22 个电机，串联和并联两套数组 |
| `rt/fall_down` | `/fall_down` | `FallDownState` | 机器人 → 用户 | `kTopicFallDown` | v1.2.0.2 | `IS_READY`/`IS_FALLING`/`HAS_FALLEN`/`IS_GETTING_UP` + `is_recovery_available` |
| `rt/robot_states` | `/robot_states` | `RobotStatesMsg` | 机器人 → 用户 | `kTopicRobotStates` | v1.3.1.1 | `current_mode`/`current_body_control`/`current_actions`；**订阅它比轮询 RPC 更适合监视模式** |
| `rt/odometer_state` | `/odometer_state` | `Odometer{x, y, theta}` | 机器人 → 用户 | `kTopicOdometerState` | v1.3.1.1 | 内置步态的平面里程计 |
| `rt/remote_controller_state` | `/remote_controller_state` | `RemoteControllerState` | 机器人 → 用户 | 直接写话题字符串 | v1.2.0.2 | 手柄的轴和按键，DEP 用它做按键触发 |
| `rt/button_event` | — | `ButtonEventMsg` | 机器人 → 用户 | 直接写话题字符串 | v1.7.1.0 | 背部按键事件 |
| `rt/battery_state` | — | `BatteryState{voltage, current, soc, average_voltage}` | 机器人 → 用户 | 常量里没有 | — | 来自示例 `SDK/example/low_level/battery_state_subscriber.cpp:8` |
| `rt/imu/data` | `/imu/data` | `sensor_msgs/Imu` | 机器人 → 用户 | `kTopicRosImu` | v1.7.1.0 | 需要开启 ROS bridge |
| `rt/joint_states` | `/joint_states` | `sensor_msgs/JointState` | 机器人 → 用户 | `kTopicRosJointStates` | v1.7.1.0 | 同上 |
| `rt/odom` / `rt/tf` | `/odom` / `/tf` | `nav_msgs/Odometry` / `TFMessage` | 机器人 → 用户 | `kTopicRosOdometer` / `kTopicTF` | v1.7.1.0 / v1.1.0.6 | `tf` 只能从 ROS 2 订阅 |
| — | `/head_pose` | `geometry_msgs/Pose` | 机器人 → 用户 | — | — | RCD 用它得到头部位姿（`RCD/src/brain/src/brain.cpp:193`） |
| `rt/LocoApiTopicReq` / `rt/LocoApiTopicResp` | `LocoApiTopicReq` | `booster_msgs/RpcReqMsg` / `RpcRespMsg` | 双向 | `kLocoApiChannelName = "rt/LocoApiTopic"` + `Req`/`Resp` 后缀 | — | 模式切换等 RPC（§1.4）；RCD 直接发布 `LocoApiTopicReq`（`RCD/src/brain/src/robot_client.cpp:13-28`） |
| — | service `booster_rpc_service` | `booster_interface/srv/RpcService` | 双向 | — | — | ROS 2 版 RPC，DEP 用它切模式（`booster_robot_controller.py:284-334`） |
| `rt/kick_ball`、`rt/robocup_behavior_status`、`rt/prone_body_control_status`、`rt/trained_traj_status`、`rt/robot_replay_traj_id`、`rt/booster_hand_data`【fw1.7 #17】1.7 没有 `rt/trained_traj_status`；`d5d8f7a` 的话题常量在 `b1_api_const.hpp:10-24` | — | 见 `DOC/developer-guide__cpp__low-level-topics.md:135-212` | — | 见 `b1_api_const.hpp:43-92` | — | 与底层控制关系不大 |

来源：`b1_api_const.hpp:26-113`；`DOC/developer-guide__cpp__low-level-topics.md:135-245`。IDL 里还有 `RobotStatusDdsMsg`（关节温度、`is_limited`、状态码）和 `RobotProcessStateMsg`，但 SDK 没有给出对应的话题常量。⚠待实机用 `ros2 topic list` 查。

### 1.4 模式切换 RPC 的线上格式（绕过 SDK 时需要）

- 请求：发布到 `rt/LocoApiTopicReq`，类型 `booster_msgs::msg::RpcReqMsg{string uuid; string header; string body}`。`header` 是 JSON，形如 `{"api_id": 2000}`；`body` 是 JSON，形如 `{"mode": 3}`。来源：`SDK/include/booster/idl/rpc/RpcReqMsg.h` 私有字段；`RCD/src/brain/src/robot_client.cpp:16-28`；`b1_loco_api.hpp:80`；`ChangeModeParameter::ToJson` 在 `b1_loco_api.hpp:254-279`。
- 响应：`rt/LocoApiTopicResp`，类型 `RpcRespMsg{uuid, header, body}`，用 uuid 与请求对应。状态码放在 header 里（推断，⚠待实机验证）。
- ROS 2 service 版本：`booster_rpc_service`，`RpcService.srv` 的请求为 `BoosterApiReqMsg{int64 api_id; string body}`，响应为 `BoosterApiRespMsg{int64 status; string body}`（`R2IF/srv/RpcService.srv:1-3`、`R2IF/msg/BoosterApiReqMsg.msg`、`BoosterApiRespMsg.msg`）。

| API | id | body | 返回 | 备注 |
| --- | --- | --- | --- | --- |
| ChangeMode | 2000 | `{"mode": 0 DAMP / 1 PREP / 2 WALK / 3 CUSTOM / 4 SOCCER}` | status | `RobotMode` 定义在 `SDK/include/booster/robot/common/robot_shared.hpp:7-14` |
| GetMode | 2017 | — | `{"mode": ...}` | |
| GetStatus | 2018 | — | `{"current_mode", "current_body_control", "current_actions"}` | DEP 切换模式后用它确认（`booster_robot_controller.py:364-374`） |
| UpperBodyCustomControl | 2030 | `{"start": bool}`（推断） | status | WALK 模式下接管上身（§4.7） |
| ZeroTorqueDrag | 2026 | `{"active": bool}`（推断） | status | 零力矩拖动 |
| GetUp / GetUpWithMode | 2008 / 2025 | — / `{"mode": ...}`【fw1.7 #18】`d5d8f7a` 发 `{"version":v}` / `{"mode":m,"version":v}`（kV1=0、kV2=1；kV2 需固件 ≥ 1.7.1） | status | 摔倒后起身 |
| GetSensors / GetRobotModel【fw1.7 #19】需固件 ≥ 1.7.1 | 2044 / 2046 | — | IMU 目录 / URDF 模型 | 可读 IMU 安装位置 |

API id 来源：`b1_loco_api.hpp:90-137`。【fw1.7 #20】`d5d8f7a` 为 `b1_loco_api.hpp:22-67`，最大 2046。

RPC 错误码（`SDK/include/booster/robot/rpc/error.hpp:12-21`）：

| 码 | 含义 |
| --- | --- |
| 0 | 成功 |
| 100 | 超时 |
| 400 | 请求参数错误 |
| 409 | 与当前服务状态冲突 |
| 429 | 请求过于频繁 |
| 500 | 服务内部错误 |
| 501 | 服务拒绝（该能力在当前配置下被禁用） |
| **502** | **状态机转换失败**（例如从 WALK 直接切 CUSTOM） |
| **503** | **电量低**【fw1.7 #21】`d5d8f7a` 未定义 503 |

SDK 默认超时：`WaitForService` 5000 ms，单次请求 1000 ms（`SDK/include/booster/robot/rpc/rpc_client.hpp:30,46`）。

### 1.5 QoS（已知值与推断值）

| 端点 | QoS | 依据 |
| --- | --- | --- |
| DEP 订阅 `/low_state` | BEST_EFFORT、KEEP_LAST、depth 1 | `booster_robot_controller.py:166-175` |
| DEP 发布 `joint_ctrl` | **RELIABLE**、KEEP_LAST、depth 1 | `booster_robot_controller.py:257-265` |
| DEP 订阅 `/remote_controller_state` | BEST_EFFORT、depth 1 | `DEP/booster_deploy/utils/remote_control_service.py:224-228` |
| 官方 ROS 2 示例、RCD 订阅 `/low_state` | rclcpp 默认 QoS（RELIABLE、depth 10） | `booster_robotics_sdk_ros2/booster_ros2_example/low_level/src/low_level_subscriber.cpp:13-15`；`RCD/src/brain/src/brain.cpp:192` |
| 推断：机器人的 `rt/low_state` writer | **RELIABLE**。理由：RELIABLE 的 reader 只能匹配 RELIABLE 的 writer，而上面两个默认 QoS 的订阅者都能收到数据 | ⚠待实机 `ros2 topic info -v /low_state` |
| 推断：机器人的 `rt/joint_ctrl` reader | **BEST_EFFORT**。理由：SDK 声称用 best-effort 发布，也能生效 | ⚠同上 |
| 建议 | 订阅用 BEST_EFFORT + depth 1（可以匹配任意 writer，也不会有重传积压）；发布用 RELIABLE + depth 1（和 DEP 一样，对任意 reader 都能匹配）；durability 用 VOLATILE | — |

### 1.6 频率与时序

| 量 | 值 | 来源 / 性质 |
| --- | --- | --- |
| `rt/low_state` 发布频率 | **约 500 Hz**（推断） | GYM 把每条 low_state 回调都当作 2 ms 时钟节拍（`GYM/deploy.py:80-81` + `GYM/utils/timer.py:15-19`，`dt=0.002` 见 `GYM/configs/T1.yaml:2`）⚠待实机 `ros2 topic hz /low_state` |
| 电机通信频率 | `MotorState.reserve[1]`，取值 0–800 | `R2IF/msg/MotorState.msg:10` |
| 官方 K1 RL 策略 | 50 Hz（`policy_dt = 0.02`） | `DEP/booster_deploy/controllers/controller_cfg.py:102` |
| DEP 发 LowCmd | 每个策略步发 1 次，即 50 Hz | `booster_robot_controller.py:757-764,786-796` |
| DEP 进入 Custom 时插值 | 500 步 × 2 ms，即 500 Hz、共 1 s | `booster_robot_controller.py:485-492` |
| GYM（T1）发 LowCmd | 500 Hz（`dt = 0.002`），策略 50 Hz（`decimation = 10`），中间用一阶低通平滑目标 | `GYM/configs/T1.yaml:2,52`；`GYM/deploy.py:167-196` |
| SDK 示例 | 50 Hz（`control_dt = 0.02`），每步最大关节变化量 0.5 rad/s × dt | `SDK/example/low_level/b1_low_sdk_example.cpp:59-65` |
| ArmController | 约 100 Hz（每步 sleep 10 ms），固定 kp 60 / kd 3 | `SDK/include/booster/robot/b1/arm_controller.hpp:244`；`DOC/developer-guide__cpp__controllers.md:169` |
| TRN 训练 | 物理 200 Hz（`sim.dt = 0.005`），`decimation = 4`，即策略 50 Hz；执行器延迟随机 2–8 个物理步，即 **10–40 ms** | `TRN/tasks/manager_based/beyond_mimic/robots/k1/mj_dance_002/tracking_env_cfg.py:313-316`；`TRN/assets/robots/booster.py:47-50` |
| DEP MuJoCo sim2sim | 物理 500 Hz（`policy_dt / decimation = 0.02 / 10`），PD 在 Python 里算 | `controller_cfg.py:19,111-112`；`DEP/booster_deploy/controllers/mujoco_controller.py:227-245` |

---

## 2. IDL 消息逐字段

C++ 定义由 fastddsgen 生成，位于 `SDK/include/booster/idl/b1/*.h`；ROS 2 定义位于 `R2IF/msg/*.msg`。两者字段顺序相同，个别类型不同（见 §2.7）。

### 2.1 `LowCmd`（`LowCmd.h:94,191-192`；`R2IF/msg/LowCmd.msg:1-8`）

| 字段 | C++ 类型 | ROS 2 类型 | 含义 |
| --- | --- | --- | --- |
| `cmd_type` | `enum CmdType : uint32_t { PARALLEL = 0, SERIAL = 1 }`，默认 **PARALLEL** | `int8`，常量 `CMD_TYPE_PARALLEL = 0`、`CMD_TYPE_SERIAL = 1` | 下标按电机空间（PARALLEL）还是串联关节空间（SERIAL）解释，见 `k1-hardware.md §4.5` |
| `motor_cmd` | `std::vector<MotorCmd>` | `MotorCmd[]` | K1 固定 22 个，下标就是 `JointIndexK1`。**不要只发部分关节**；不需要控制的关节可以发 kp = kd = 0 |

### 2.2 `MotorCmd`（`MotorCmd.h:261-267`；`R2IF/msg/MotorCmd.msg:1-7`）

| 字段 | C++ | ROS 2 | 单位 | 含义与注意 |
| --- | --- | --- | --- | --- |
| `mode` | `uint8_t` | `int8` | — | **没有文档**。官方文档示例和 DEP 用 0；ArmController 用 `0x0A`（`arm_controller.hpp:216`）。⚠待实机验证。Custom 下按 DEP 的做法置 0 |
| `q` | float | float32 | rad | 目标位置。SERIAL 下是串联关节角，PARALLEL 下是电机角 |
| `dq` | float | float32 | rad/s | 目标速度。官方所有示例都置 0，于是 kd 项变成纯阻尼 −kd·dq |
| `tau` | float | float32 | N·m | 前馈力矩 τ_ff。GYM 用它对并联踝做「力矩模式」控制（`GYM/deploy.py:182-190`） |
| `kp` | float | float32 | N·m/rad | 位置刚度 |
| `kd` | float | float32 | N·m·s/rad | 阻尼。并联关节的 kd 直接下发到电机侧，见 `k1-hardware.md §3.5` |
| `weight` | float | float32 | 0–1 | 见 §3.3。**Custom 下无效，置 0** |

Python SDK 文档说明：没有填写的 velocity、effort、kp、kd、weight 一律按 0.0 下发，**0 不等于「沿用默认增益」**（`DOC/developer-guide__booster-os-python-sdk__common-data-types__joint-related-data__joint-command.md:14`）。所以一定要显式给 kp 和 kd。

### 2.3 `LowState`（`LowState.h:229-231`；`R2IF/msg/LowState.msg:1-3`）

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `imu_state` | `ImuState` | 见 §2.5 |
| `motor_state_parallel` | `MotorState[]` | 电机空间，idx 14/15、20/21 是踝的上下曲柄电机 |
| `motor_state_serial` | `MotorState[]` | 串联关节空间，idx 14/15、20/21 是踝 pitch/roll。DEP 和 RCD 都读这一组（`booster_robot_controller.py:224-227`；`RCD/src/brain/src/brain.cpp:1339-1340`） |

两组数组中，非踝关节的值应该相同（推断）⚠。数组长度在 K1 上应为 22，写代码时用 `min(size, 22)` 做防御。

### 2.4 `MotorState`（`MotorState.h:285-292`；`R2IF/msg/MotorState.msg:1-11`，注释的英文版见 `RCD/src/interface/booster_ros2_interface/msg/MotorState.msg`）

| 字段 | C++ | ROS 2 | 含义 |
| --- | --- | --- | --- |
| `mode` | uint8 | int8 | 电机模式，没有文档 ⚠ |
| `q` | float | float32 | 位置，rad |
| `dq` | float | float32 | 速度，rad/s。是否经过滤波取决于配置：v1.6.0 起可以配置开关「关节反馈滤波」（`DOC/changelog__v1-6-0-firmware-app-release.md:83`） |
| `ddq` | float | float32 | 加速度，rad/s² |
| `tau_est` | float | float32 | 估计力矩，N·m。DEP 把它当作 `feedback_torque` 使用（`booster_robot_controller.py:227`） |
| `temperature` | uint8 | int8 | 电机温度，范围 −100~150 |
| `lost` | uint32 | uint32 | 丢包计数 |
| `reserve[2]` | uint32[2] | uint32[2] | `[0]` 为电机错误标志位（0–255）；`[1]` 为当前电机通信频率（0–800） |

建议在控制循环里监控 `temperature`、`lost` 的增量以及 `reserve[0] != 0`，作为自己的保护条件。

### 2.5 `ImuState`（`ImuState.h:207-209`；`R2IF/msg/ImuState.msg:1-6`）

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `rpy[3]` | float[3] | 欧拉角 (roll, pitch, yaw)，rad，R = Rz·Ry·Rx |
| `gyro[3]` | float[3] | 机体系角速度，rad/s |
| `acc[3]` | float[3] | 加速度，m/s²（直立时 z ≈ +9.8，推断 ⚠） |

`ImuState` 里**没有四元数**，要自己用 rpy 转换：

```python
# 与 DEP 完全一致（DEP/booster_deploy/utils/isaaclab/math.py:273-299），返回 (w, x, y, z)
cy, sy = cos(yaw/2), sin(yaw/2); cr, sr = cos(roll/2), sin(roll/2); cp, sp = cos(pitch/2), sin(pitch/2)
q = [cy*cr*cp + sy*sr*sp, cy*sr*cp - sy*cr*sp, cy*cr*sp + sy*sr*cp, sy*cr*cp - cy*sr*sp]
# 投影重力（GYM/utils/rotate.py:17-20）：g_b = (Rz@Ry@Rx).T @ [0, 0, -1]
```

### 2.6 其他常用状态消息

| 消息 | 字段 | 来源 |
| --- | --- | --- |
| `FallDownState` | `fall_down_state`（IS_READY=0、IS_FALLING=1、HAS_FALLEN=2、IS_GETTING_UP=3）；`is_recovery_available`（bool） | `FallDownState.h:92-97`；`R2IF/msg/FallDownState.msg:1-7` |
| `RobotStatesMsg` | `current_mode`、`current_body_control`（int32）；`current_actions`（int32[]） | `R2IF/msg/RobotStatesMsg.msg`；枚举见 `robot_shared.hpp:7-53`（`BodyControl::kCustom = 6`、`kPrepare = 2`、`kDamping = 1`、`kSoccerGait = 5`） |
| `Odometer` | x、y、theta（float） | `Odometer.h` |
| `RemoteControllerState` | event、lx/ly/rx/ry、a/b/x/y、lb/rb/lt/rt、ls/rs、back/start、hat_* | `RemoteControllerState.h`；事件码定义在 `b1_api_const.hpp:247-254` |
| `BatteryState` | voltage、current、soc、average_voltage | `BatteryState.h` |

### 2.7 C++ IDL 与 ROS 2 msg 的类型差异（自己写 IDL 时必须注意）

| 字段 | C++ SDK（fastddsgen） | ROS 2 `.msg` | 线上字节（XCDR1，小端） |
| --- | --- | --- | --- |
| `LowCmd.cmd_type` | `enum : uint32`，4 字节 | `int8`，1 字节，后面补 3 字节对齐，然后是 sequence 长度 | 如果补齐的字节是 0，两种写法的字节流**完全相同**：`01 00 00 00 <len>` |
| `MotorCmd.mode` / `MotorState.mode` / `temperature` | `uint8` | `int8` | 都是 1 字节，只有符号解释不同 |
| 其余字段 | 两边一致 | | |

实证：SDK（C++ 或 Python）发的 LowCmd 与 DEP 用 ROS 2 发的 LowCmd **都能控制机器人**，说明机器人两种都接受。自己实现时，照抄其中一种定义即可，不要自创字段。

---

## 3. 控制律：在哪里执行，weight 和 mode 是什么

### 3.1 控制律形式

```
τ_joint = kp · (q_des − q) + kd · (dq_des − dq) + τ_ff        （每个关节独立；SERIAL 模式下并联踝由固件换算到两个电机）
```

各处用的都是这个形式：
- TRN 训练用 Isaac Lab 的 `DelayedPDActuator`，力矩再经 T-N 曲线截断（`TRN/assets/robots/actuator.py:85-133`）。
- DEP 的 MuJoCo sim2sim 用 `ctrl = clip(kp·(q* − q) − kd·dq, ±effort_limit)`（`DEP/booster_deploy/controllers/mujoco_controller.py:237-243`），没有 dq_des 和 τ_ff 两项。
- 实机上只要让 LowCmd 的 `dq = 0`、`tau = 0`，就与上面的仿真公式等价。

### 3.2 PD 在哪里执行

**结论**：PD 在机器人侧执行，频率明显高于用户发指令的频率，指令在两帧之间做零阶保持。具体是在关节驱动板里跑，还是在主控的底层控制进程里跑，官方没有说明（⚠）。现有证据倾向于「kp/kd/q/τ 下发到驱动器，由驱动器闭环」。

| 证据 | 推论 |
| --- | --- |
| DEP 的 K1 行走策略只按 50 Hz 发 LowCmd（`booster_robot_controller.py:757-764`），并且能稳定行走 | PD 一定在下游以更高频率执行，否则 50 Hz 的 PD 撑不住双足 |
| DEP 注释："The low-level controller keeps this command when Custom is entered, until the locomotion policy publishes its first action"；"Send exactly one command while PVT still owns the robot; the low-level controller retains it across the Custom transition"（`booster_robot_controller.py:390-391,441-442`） | 机器人侧有一个「low-level controller」，它会**保存最后一帧**并持续执行 |
| DEP README："For parallel-actuated joints, `robot.joint_damping` is sent directly to the motors"（`DEP/README.md:93-94`） | kd（以及很可能 kp）下发到电机驱动器 |
| `MotorState.reserve[1]` 的含义是「当前电机通信频率（0–800）」 | 主控与电机之间的通信频率在几百 Hz 量级 |
| 3P/HSL："Integrated motor controller boards (proprietary)"，总线是 CAN | 关节内置驱动板 |
| GYM 对并联踝令 `kp = 0`，自己算 `tau = kp·(q* − q)`，注释是 "to avoid non-linearity"（`GYM/deploy.py:182-190`） | 固件对 SERIAL 模式下的 kp 做了非线性（或近似）的映射，力矩映射则是线性的（Jacobian 转置） |

对控制设计的影响：
1. 刚度和阻尼由驱动器实现，用户侧可以低频发指令（50 Hz 足够）。**但必须持续发**，下一帧到来前机器人一直执行上一帧，见 §4.6。
2. 想做纯力矩控制，可以令 `kp = kd = 0`，用 `tau` 给力矩（GYM 在踝上就是这么做的）。这时力矩闭环频率等于你的发送频率，而且没有驱动器侧的阻尼，**建议保留少量 kd**。力矩上限和截断行为没有文档 ⚠。
3. `kp = kd = 0` 且 `tau = 0` 时，关节完全放松（零力矩）。ArmController 就是用这种方式「不接管」腿部，让内部控制器继续平衡（`DOC/developer-guide__cpp__controllers.md:175`；`arm_controller.hpp:234-236`）。

### 3.3 `weight` 的语义

| 证据 | 内容 |
| --- | --- |
| GYM 官方代码注释 | `# weight is not effective in custom mode`（`GYM/utils/command.py:15`） |
| DEP 官方 K1 部署 | Custom 模式下所有关节都是 `weight = 0.0`，照样能控制（`booster_robot_controller.py:280`） |
| ArmController（UpperBodyCustomControl 下） | 不设置 weight，即 0，手臂仍然受控（`arm_controller.hpp:214-240`） |
| SDK 示例 `b1_low_sdk_example.cpp` | 定义了 `weight`、`weight_rate` 并做斜坡变化（`:51-62,193-203`），**但从来没有写进 msg**，是一段死代码，推测是旧版「逐步交接控制权」的遗留 |
| `low_level_publisher.cpp` | 只有头部 pitch 给 `weight = 1.0`，其余为 0（`:35-42`），没有说明模式 |
| Python 文档 | "Control weight, typical range 0.0 ~ 1.0"（`joint-command.md:50-52`） |

**结论**：weight 很可能是「用户指令与内部控制器输出的混合系数」，只在某些非 Custom 模式下起作用；**在 Custom 下无效**。Custom 下置 0 即可，与官方一致。如果在 UpperBodyCustomControl 下看到行为异常，可以试试 weight = 1。⚠待实机验证。

### 3.4 固件会做什么，不会做什么（已知与未知）

| 行为 | 状态 |
| --- | --- |
| 串联 ↔ 并联换算 | 会做（SERIAL 模式） |
| 关节限位截断 | ArmController 场景下「server 会施加关节位置限位」（`arm_controller.hpp:60`）；Custom 下是否截断 ⚠。超限会进入 PROTECT（`modes.md:68`） |
| 力矩饱和 | 电机的物理极限（`k1-hardware.md §2`）；是否有软件力矩限幅 ⚠ |
| 指令超时回落 | 没有文档；源码注释表明会保留最后一帧 ⚠（§4.6） |
| 过热、低电 | 有声音告警（规格书）；RPC 返回 503；v1.6.0 的更新日志写了「低电时机器人将停止运动」，以及「可配置低电模式（For RoboCup）」（`DOC/changelog__v1-6-0-firmware-app-release.md:53,86`）。Custom 下是否会强制停止 ⚠【fw1.7 #21】`d5d8f7a` 未定义 503，固件是否返回待实机验证 |

---

## 4. 进入与退出 Custom 模式的完整安全流程

### 4.1 模式状态机（与底层相关的部分）

| 从 → 到 | 是否允许 | 来源 |
| --- | --- | --- |
| 上电 → DAMP | 自动 | `k1-operations.md §3.1`（官方状态图） |
| DAMP → PREP | 可以（L2 + Start，或背部 STAND 键，或 `ChangeMode(1)`） | `modes.md:28`；`DOC/product-manual__k1__basic-operations__joystick-control.md` |
| DAMP / PREP → CUSTOM | **可以**；遥控器上没有对应按键，只能用 RPC | `modes.md:58` |
| WALK → CUSTOM | **不行**（手册写 Custom 只能从 PREP 或 DAMP 进入），会返回 502 | `modes.md:58`；错误码见 `error.hpp:20` |
| CUSTOM → DAMP / PREP | 可以 | `modes.md:60` |
| CUSTOM → WALK | 手册写**不可以**；但 DEP 的默认退出方式正是从 Custom 切到 Walking，并用 GetStatus 确认成功（`DEP/booster_deploy/controllers/controller_cfg.py:36`；`booster_robot_controller.py:667-680`），DEP 要求固件 ≥ v1.7.2（`DEP/README.md:10`）【fw1.7 #23】固件 1.7.2.0 满足；1.7.0/1.7.1 不满足，先确认小版本。CUSTOM→WALK 仍要在吊架上实测 | **两处说法冲突** ⚠。新固件可能已经允许 |
| 任意 → PROTECT | 超限、摔倒等异常时自动进入，关节状态与 DAMP 相同 | `modes.md:66-72` |

### 4.2 推荐的进入流程（综合 DEP 和 GYM，逐步给出出处）

| 步 | 动作 | 为什么 | 出处 |
| --- | --- | --- | --- |
| 0 | 吊架或保护绳全程保护；场地平整 | Custom 下腿也由你控制，极易摔倒 | `modes.md:64`；`DOC/product-manual__k1__getting-started__safety-warnings.md:32` |
| 1 | 让机器人进入 **PREP** 并站稳（PREP 下起步最安全） | Custom 只能从 PREP 或 DAMP 进；PREP 由 "PVT" 控制器保持站姿 | `GYM/README.md`；`SDK/example/low_level/b1_low_sdk_example.cpp:12-14` |
| 2 | 初始化 DDS，订阅 `rt/low_state`，**等到收到第一帧** | 没有状态就无法得到当前姿态 | `booster_robot_controller.py:404-413` |
| 3 | 姿态检查：投影重力 z < −0.5（倾角 < 60°）；更保守的做法是要求 \|roll\| 和 \|pitch\| < 0.3 | 机器人已经倒下时不能进入 | `booster_robot_controller.py:418-433` |
| 4 | 等 `rt/joint_ctrl` 的订阅者匹配成功（`GetMatchedSubscriptionsCount() > 0`，ROS 2 用 `get_subscription_count()`） | 在 DDS 发现完成之前发出的帧会丢失 | `booster_robot_controller.py:435-437,465-467`；`SDK/include/booster/robot/channel/channel_publisher.hpp:50-55` |
| 5 | **预发一帧保持指令**：`q = 当前实测角`，kp/kd 用 prepare 那一套（如 `K1_CFG.prepare_state`），`dq = tau = 0`，SERIAL。然后 sleep 0.1 s | 进入 Custom 的瞬间，机器人会执行它保存的最后一帧。如果保存的是全 0 帧（kp = 0），机器人会瘫倒；如果保存的是远离当前位姿的目标，会猛地一跳 | `booster_robot_controller.py:380-392,439-446,471-479`；GYM 做法相同（`GYM/deploy.py:116-123`） |
| 6 | `ChangeMode(kCustom)`（API 2000，`{"mode": 3}`），再用 GetStatus（2018）确认 `current_mode == 3`。DEP 失败时每 0.5 s 重试一次，最多 20 次 | RPC 可能因为发现未完成或状态不对而失败 | `booster_robot_controller.py:336-378` |
| 7 | 从当前角度**平滑插值**到目标姿态：DEP 用 500 步 × 2 ms = 1 s；SDK 示例限制每步最大变化 0.5 rad/s × dt | 避免阶跃 | `booster_robot_controller.py:485-492`；`b1_low_sdk_example.cpp:60-63,139-145` |
| 8 | 进入主循环，**持续**发送（≥ 50 Hz，保持或插值时建议 500 Hz） | 机器人执行最后一帧；发得太慢时轨迹是阶梯状的 | §1.6 |
| 9 | 在循环里做监控（§4.5），任一条件触发就走退出流程 | | |
| 10 | 退出：`ChangeMode(kPrepare)` 让机器人站回 PREP 姿态，或 `ChangeMode(kDamping)`（吊着时可以用）；DEP 默认切到 Walking | GYM 的 README 要求"Switch back to PREP Mode before terminating the program"；GYM 代码退出时切 Damping（`GYM/deploy.py:235`）；DEP 可以配置 `exit_mode`（`DEP/README.md:105-124`） | |

DEP 的两种准备方式（`DEP/README.md:128-150`；K1 默认 `prepare_mode = "walking"`，见 `DEP/booster_deploy/robots/k1.py:6`）：
- `"walking"`：按 X 后，预发一帧保持指令 → 切 Custom → 直接运行 K1 自带的 RL 步态（速度指令屏蔽为 0）来保持站立；再按 A 切换到任务策略。
- `"standing"`：预发 → 切 Custom → 用 1 s 插值到 `prepare_state.joint_pos` → 按 A 启动任务策略。

### 4.3 退出

- 正常退出：先停止发送，再立即 `ChangeMode(kPrepare 或 kDamping)`。**不要只停止发送而不切模式**，参见 §4.6。
- DEP 的清理顺序：设置 `exit_event` → 等推理进程退出 → 关闭通信 → `rclpy.shutdown`；然后在 `run()` 结尾切换到 `exit_mode`。如果是安全中止（`_safety_abort`），则强制切到 damping（`booster_robot_controller.py:558-609,667-680`）。
- 注意：DEP 的策略级摔倒检测（`projected_gravity.z > -0.5`，见 `DEP/tasks/locomotion/locomotion.py:123-131`）触发后，走的是**配置的 exit_mode**，默认是 walking；只有在按 X 那一刻检测到姿态异常时，才会强制切 damping（`booster_robot_controller.py:425-433,667`）。比赛或调试时建议设置 `--exit-mode damping`。

### 4.4 急停方式（全部是「软急停」）

| 方式 | 效果 | 来源 |
| --- | --- | --- |
| 手柄 L2 + Back | 进入 DAMP | `DOC/product-manual__k1__basic-operations__joystick-control.md:50-51` |
| 背部 F1 键 | 默认进入 DAMP，可以在 `/opt/booster/Gait/configs/K1/task_instruction.yaml` 里改 | `body-operations.md:25` |
| App | 可以触发 | `DOC/product-manual__k1__getting-started__overview.md:60` |
| 程序调用 `ChangeMode(kDamping)` | 进入 DAMP | — |
| 长按电源键 3 s | 断电，机器人直接瘫倒 | `k1-operations.md §2.3` |

- 手册没有提到硬件急停按钮。⚠
- 手柄的按键组合在 Custom 下是否仍然有效，没有文档。⚠ **必须在第一次上机前实测**。

### 4.5 摔倒与异常保护（建议在自己的循环里全部实现）

| 条件 | 阈值建议 | 参考 |
| --- | --- | --- |
| 倾角 | 投影重力 z > −0.5（DEP）；\|roll\| 或 \|pitch\| > 1.0 rad（GYM） | `locomotion.py:123-131`；`GYM/deploy.py:77-79` |
| 状态超时 | 超过 50–100 ms 没有收到 `rt/low_state` 就退出 | 自定（DEP 没有做） |
| 跟踪误差 | BeyondMimic 用：实际投影重力与参考投影重力的点积 < 0.5 则停止 | `DEP/tasks/beyond_mimic/beyond_mimic.py:161-175` |
| 关节 | 目标角 clamp 到限位 ×0.9；关注 `temperature`、`reserve[0]` 和 `lost` 的增量 | `k1-hardware.md §3.2`；§2.4 |
| 摔倒话题 | `rt/fall_down` 变成 IS_FALLING 或 HAS_FALLEN | §2.6 |
| 模式被外部切换 | 订阅 `rt/robot_states`，一旦 `current_mode != 3`，立即停止发送 | §2.6 |

机器人自身的保护：出现超限或摔倒时进入 PROTECT，关节状态同 DAMP（`modes.md:66-72`）；进入不可控状态时自动切到 DAMP（`overview.md:60`）。v1.7.1 修复了「IMU 偶发异常数据导致摔倒」的问题（`DOC/changelog__v1-7-1-firmware-app-release.md:36`），所以要尽量用新固件。【fw1.7 #23】1.7.2 已包含该修复，1.7.0 上仍有。

### 4.6 看门狗和超时（重要）

- 官方文档**没有说明** `rt/joint_ctrl` 断流后会怎样。
- DEP 的注释写明低层控制器会**保留**最后一帧（`booster_robot_controller.py:390-391,441-442`）。由此推断：**用户进程崩溃或网络中断后，机器人会一直按最后一帧的 q、kp、kd、tau 继续跟踪，不会自动进入阻尼**。⚠待实机验证：吊着机器人，在 Custom 下 kill 掉进程并观察。
- 应对办法：
  1. 在机器人本机运行控制程序，不走 Wi-Fi。
  2. 另起一个独立的「看门狗进程」订阅你的心跳话题，超时后调用 `ChangeMode(kDamping)`。
  3. 手边随时备好手柄（L2 + Back）。
  4. 最后一帧不要带大的 τ_ff。

### 4.7 替代方案：WALK + UpperBodyCustomControl（适合足球里只自己控制头和手臂的场景）

- 在 WALK 模式下调用 `UpperBodyCustomControl(true)`（API 2030）后，头和双臂（idx 0–9）交给 `rt/joint_ctrl`，腿仍由内置步态控制。Python 文档说明："When enabled, control authority for the head and both arms is transferred to the caller … the legs continue to be controlled by the system"（`DOC/developer-guide__booster-os-python-sdk__booster-robot-client-reference__motion-control-apis__upper-body-control.md:18`）。
- ArmController 就是这种用法：腿部发 kp = kd = 0 的帧，手臂发 kp = 60、kd = 3，约 100 Hz（`arm_controller.hpp:209-244`）。它用的是 23 关节数组（`kJointCnt`），在 K1 上是否正常 ⚠。**自己写时用 22**。
- 只转头的话，更简单的做法是调 RPC `RotateHead`（2004）或 `RotateHeadWithTime`（2043）；RCD 就是这么做的（`RCD/src/brain/src/robot_client.cpp:31-39`）。
- Python `set_joints` 只接受两种名字集合：全部关节，或者前 10 个上身关节（`DOC/...set-joints.md:40`）。

---

## 5. RL 策略部署流水线（以 DEP 的 K1 实现为准）



### 5.1 进程与数据流（`DEP/booster_deploy/controllers/booster_robot_controller.py`）

```
主进程 BoosterRobotPortal
 ├─ 线程 low_state_executor：rclpy 订阅 /low_state（BEST_EFFORT, depth 1）
 │     回调：rpy、gyro、motor_state_serial[i].q / dq / tau_est → SyncedArray("state")（共享内存）
 │            手柄的 vx / vy / vyaw → SyncedArray("command")                            :156-253
 ├─ publisher：LowCmd 发到 joint_ctrl（RELIABLE, depth 1），cmd_type = SERIAL，
 │             weight = 0；RPC 客户端 booster_rpc_service                               :255-288
 └─ run()：等 X → start_custom_mode_conditionally() → 等 A → 拉起推理子进程 → 每 0.1 s 检查子进程是否存活  :621-680
子进程 inference_process_func → BoosterRobotController.run()
   每隔 policy_dt（0.02 s）：update_state()（读共享内存，rpy → quat）
                          → policy.inference() → ctrl_step()：写入 22 个 q / kp / kd 并 publish      :727-799
```

- `update_state` 把 `root_pos_w` 和 `root_lin_vel_w` 都置为 0（`:231-236`），也就是说**实机没有线速度估计**。所以 K1 的策略都不使用线速度；训练时要用 "WoStateEstimation" 这类观测配置（`TRN/tasks/manager_based/beyond_mimic/robots/k1/mj_dance_002/env_cfg.py:38-42`）。
- LowState 没有时间戳；推理子进程按自己的时钟读取「最新」状态，观测的陈旧度在 0 到 1 个 low_state 周期之间，再加上推理耗时。

### 5.2 K1 行走策略 `k1_walk` 的观测

来源：`DEP/tasks/locomotion/locomotion.py:113-154,202-210`；配置在 `DEP/tasks/locomotion/robots/k1/__init__.py:12-83`。

| 段 | 维度 | 计算 | 缩放 |
| --- | --- | --- | --- |
| base_ang_vel | 3 | `imu_state.gyro`（机体系） | 1 |
| projected_gravity | 3 | `quat_apply_inverse(quat_from_euler_xyz(rpy), [0, 0, -1])` | 1 |
| command | 3 | vx、vy、vyaw。手柄归一化值乘以上限：vx 前 1.6 / 后 0.3，vy 0.3，vyaw 1.8（`__init__.py:44-49`） | 1 |
| dof_pos − default | 20 | 按 `policy_joint_names` 顺序，**不含头部** | 1 |
| dof_vel | 20 | 同上 | **×0.1**（`obs_dof_vel_scale`） |
| last_action | 20 | 上一步的原始网络输出 | 1 |
| **单帧合计** | **69** | 裁剪到 ±100 | |
| 历史 | ×10 帧 → 690 | 第一帧用 `repeat` 填满整个历史（`history_init = "repeat"`） | |

`policy_joint_names` 是 Isaac Lab 按广度优先排列的顺序。对应的实机 idx 为 `[2, 6, 10, 16, 3, 7, 11, 17, 4, 8, 12, 18, 5, 9, 13, 19, 14, 20, 15, 21]`（由 `__init__.py:51-72` 与 `DEP/booster_deploy/robots/k1.py:7-17` 推出）。

### 5.3 动作映射（`locomotion.py:87-111`）

```text
action = model(obs_history.flatten()).clamp(-100, 100)        # 20 维，Isaac 顺序
action_real = scatter(action → 22 维实机顺序)；头部 2 维 = 0
action_real[right_elbow_pitch(idx 8)] -= 0.2                   # arm_action_fix：实际目标偏移 -0.2 × 0.25 = -0.05 rad
target = default_joint_pos + action_real * 0.25                # action_scale = 0.25
filtered.lerp_(target, 0.8)                                    # action_filter = 0.8，一阶低通，τ ≈ 12 ms
→ LowCmd.q = filtered；kp / kd 取 k1_walk 配置（100/2、踝 65/1、臂 20/2、头 4/1），SERIAL，50 Hz
```

`default_joint_pos` 为 `[0,0, 0.2,-1.25,0,-0.5, 0.2,1.25,0,0.5, -0.15,0,0,0.3,-0.15,0, -0.15,0,0,0.3,-0.15,0]`（`__init__.py:15-21`）。

### 5.4 BeyondMimic（K1 舞蹈、格斗动作跟踪）

来源：`DEP/tasks/beyond_mimic/beyond_mimic.py:89-181`；训练侧观测定义在 `TRN/tasks/manager_based/beyond_mimic/robots/k1/mj_dance_002/tracking_env_cfg.py:118-129`。

- 观测共 119 维：参考关节位置（22）、参考关节速度（22）、参考锚点姿态相对当前姿态的旋转矩阵前两列（6）、ang_vel（3）、joint_pos − default（22）、joint_vel（22）、last_action（22）。关节按 sim 顺序（`sim_joint_names`）排列。
- 锚点姿态的对齐：启动时记录初始 yaw 的逆，所以它用到的是**相对启动时刻的 IMU yaw**（`beyond_mimic.py:67-69,94-106`）。
- 动作：`target = action[sim2real] · scale + default`，其中 `scale = 0.25 · effort_limit / stiffness`（`beyond_mimic.py:40-43,177-181`）。
- **不一致 ⚠**：DEP 里 K1 mj2 的配置是 kp 80、effort 30，由此得到髋 pitch 的 scale = 0.094。而本地 TRN 源码推出的训练值是 kp 30.2、scale 0.563（`TRN/assets/robots/booster.py:105-116` 与 `actuator.py:159-163`）。说明 DEP 自带的 checkpoint 来自另一版训练配置。**部署自己训练的模型时，kp、kd、action_scale 和 default_pos 必须与训练时逐项一致。**

### 5.5 GYM（T1）的另一种做法：500 Hz 发送 + 目标平滑 + 并联踝力矩化

来源：`GYM/deploy.py:76-196`，`GYM/utils/policy.py:34-73`。可以借鉴到 K1。

- 观测共 47 维：投影重力、角速度、平滑后的指令（受步态频率门控）、步态相位 cos/sin、腿部 12 个关节的 dof_pos − default、dof_vel × 0.1、上一步动作；action_scale = 1.0，clip ±1。
- 发送线程每 2 ms 执行 `filtered = 0.8·filtered + 0.2·target`（τ ≈ 9 ms），然后发出。
- 并联踝（T1 的 idx 15、16、21、22；K1 应为 **14、15、20、21**）：`q = 实测角`、`kp = 0`、`tau = clip(kp_cfg·(target − q), ±torque_limit)`，kd 保持不变。

### 5.6 sim2real 检查清单

| 项 | 要求 |
| --- | --- |
| 关节顺序 | 实机按 idx 排列（URDF 顺序）；Isaac 策略用广度优先顺序；MuJoCo 用 MJCF 顺序，K1 的 MJCF 与 URDF 顺序相同（`mujoco_controller.py:162` 取 `qpos[7:]`） |
| 增益 | 实机 kp/kd 与训练一致。并联踝的 kd 在电机侧生效（`DEP/README.md:91-101`） |
| 延迟 | 训练时加入 10–40 ms 的执行器延迟随机化（TRN 的做法）；实机观测没有时间戳 |
| IMU | 只用 gyro 和投影重力；yaw 会漂移，不要用绝对 yaw |
| 线速度 | 实机没有，观测里去掉 |
| 频率 | 策略 50 Hz；可以像 GYM 那样用 500 Hz 发送线程平滑目标 |
| 限位 | 训练时软限位系数 0.9（`booster.py:44`），实机发送前 clamp |
| 安全 | 摔倒检测后切 DAMP（设置 `--exit-mode damping`） |

---

## 6. 绕过 SDK：可行性、需要什么、风险

### 6.1 方案对比

| 方案 | 可行性 | 需要 | 证据 / 备注 |
| --- | --- | --- | --- |
| A. ROS 2 Humble + `booster_interface` | **已被官方验证**，DEP 和 RCD 都在用 | 机器人上 `source /opt/booster/BoosterRos2Interface/install/setup.bash`；在其他机器上，用 `booster_robotics_sdk_ros2/booster_ros2_interface` 自行编译 | `DEP/README.md`；`RCD/scripts/start.sh:9-11` |
| B. 原生 Fast DDS（eProsima 2.x，自己用 fastddsgen 生成） | 高：同一套 RTPS 协议，同一种 XCDR1 编码 | 类型名必须**精确等于** `booster_interface::msg::dds_::LowCmd_`，也就是 IDL 要放在 `module dds_` 里，结构体名带下划线；话题 `rt/joint_ctrl`、`rt/low_state`；domain 0 | 类型名来自库字符串；SDK 自己就是这么做的 |
| C. CycloneDDS（C/C++/Python），或 ROS 2 换用 `rmw_cyclonedds` | 中高：RTPS 标准互通；类型名同上 | 同 B | ⚠待实机验证。Cyclone 与 Fast DDS 在发现和 type information 上偶尔有兼容问题 |
| D. 自己解析 UDP 抓包 | 不推荐 | — | 没有必要 |

### 6.2 最小 IDL（ROS 2 风格，与 `R2IF/msg/*.msg` 逐字段对应）

```idl
// 保存为 booster_lowlevel.idl。fastddsgen 需要支持 IDL4 的 int8；旧版工具可以把 int8 换成 octet（线上字节相同，只是符号解释不同）
module booster_interface { module msg { module dds_ {
  struct MotorCmd_   { int8 mode; float q; float dq; float tau; float kp; float kd; float weight; };
  struct LowCmd_     { int8 cmd_type; sequence<booster_interface::msg::dds_::MotorCmd_> motor_cmd; }; // 0=PARALLEL, 1=SERIAL
  struct ImuState_   { float rpy[3]; float gyro[3]; float acc[3]; };
  struct MotorState_ { int8 mode; float q; float dq; float ddq; float tau_est; int8 temperature; uint32 lost; uint32 reserve[2]; };
  struct LowState_   { booster_interface::msg::dds_::ImuState_ imu_state;
                       sequence<booster_interface::msg::dds_::MotorState_> motor_state_parallel;
                       sequence<booster_interface::msg::dds_::MotorState_> motor_state_serial; };
}; }; };
// RPC（切模式用）：
module booster_msgs { module msg { module dds_ {
  struct RpcReqMsg_  { string uuid; string header; string body; };   // 话题 rt/LocoApiTopicReq；header = {"api_id":2000}，body = {"mode":3}
  struct RpcRespMsg_ { string uuid; string header; string body; };   // 话题 rt/LocoApiTopicResp
}; }; };
```

- 字段顺序依据：`R2IF/msg/*.msg` 与 `SDK/include/booster/idl/b1/*.h` 的私有成员。
- C++ SDK 把 `cmd_type` 定义为 uint32 枚举，线上兼容，见 §2.7。
- 所有 sequence 都不设上限，没有 `@key`。

### 6.3 QoS 与传输配置

- 读端：BEST_EFFORT、KEEP_LAST 1、VOLATILE。写端：RELIABLE（或 BEST_EFFORT）、KEEP_LAST 1、VOLATILE。
- 传输：只用 UDPv4，与机载 profile 一致；机器人的服务跑在容器里，**共享内存传输不可靠**。Fast DDS 的 XML 写法可以参照 `RCD/configs/fastdds.xml:4-23`（`useBuiltinTransports = false` 加一个 UDPv4 transport，并设置 `interfaceWhiteList`）。
- 在机器人本机运行时，白名单只放 `127.0.0.1`，可以降低局域网串扰。但要先确认机器人服务侧也在 loopback 上发布数据。⚠待实机验证。

### 6.4 用 ROS 2 做诊断（在机器人上）

```bash
source /opt/ros/humble/setup.bash
source /opt/booster/BoosterRos2Interface/install/setup.bash
export FASTRTPS_DEFAULT_PROFILES_FILE=/opt/booster/BoosterRos2/fastdds_profile_udp_only.xml   # 与 RCD 一致
ros2 topic list                                   # 确认 /low_state、/joint_ctrl、/robot_states ... 以及未公开的话题
ros2 topic info -v /low_state                     # 查看机器人端的 QoS（验证 §1.5 的推断）
ros2 topic hz /low_state --qos-reliability best_effort   # 实测 LowState 频率（验证 §1.6）
ros2 topic echo /robot_states                     # 监视模式（current_mode：0 DAMP / 1 PREP / 2 WALK / 3 CUSTOM）
```

`--qos-reliability` 这个参数在 Humble 的 `ros2 topic hz` 上是否可用 ⚠；如果不可用，直接去掉即可。

### 6.5 风险

| 风险 | 说明 | 缓解 |
| --- | --- | --- |
| **比赛局域网串扰** | 所有 K1 默认都在 domain 0，`rt/joint_ctrl` 没有鉴权。同一网段里任何 DDS 参与者都能向**所有处于 Custom 模式的机器人**发指令，也能读到它们的 low_state | 控制程序在机器人本机运行；白名单只放 127.0.0.1；ROS 节点设置 `ROS_LOCALHOST_ONLY=1` 或专用的 `ROS_DOMAIN_ID`（Python SDK 支持 `domain_id`，见 `DOC/...initialization.md:74`）。机器人服务本身能否改 domain ⚠ |
| 多个写者 | 两个进程同时发 `rt/joint_ctrl` 时，机器人会交替执行两边的帧，导致抖动或危险动作 | 保证只有一个写者；ROS 2 可以用 `get_publisher_count` 检查 |
| 数组长度或布局错误 | 23 与 22 混用，或只发部分关节 | 固定 22 个；发送前 assert |
| cmd_type 用错 | C++ IDL 默认是 PARALLEL。如果用 URDF 串联角去控并联电机，**踝会乱动** | 显式设置 `SERIAL` |
| 断流保持 | 见 §4.6 | 看门狗 |
| 跨 Wi-Fi 控制 | 延迟和丢包；RELIABLE 重传会导致积压 | 本机运行；读端用 BEST_EFFORT |
| 固件差异 | Custom 入口行为（≥ v1.8.0.9 会先保持站立）、话题、RPC 都随版本变化【fw1.7 #14】 | 查看 `/opt/booster/version.txt`（`k1-operations.md`） |
| 类型定义漂移 | RCD 自带的 `booster_interface` 与官方 `R2IF` 的 msg 集合不同：RCD 多了 `RawBytesStamped`，官方多了 `RobotStatesMsg` 等 | 以机器人上 `/opt/booster/BoosterRos2Interface` 为准 |

---

## 7. 最小底层控制示例：保持当前姿态 → 2 s 插值到 K1 prepare 姿态 → 保持

### 7.1 C++（SDK）

改写自 `SDK/example/low_level/b1_low_sdk_example.cpp`（结构与斜坡插值），按 K1 的 22 关节布局重写；进入流程取自 `DEP/booster_deploy/controllers/booster_robot_controller.py:394-498`；目标姿态和增益取自 `DEP/booster_deploy/robots/k1.py:66-78`。⚠未在实机编译运行，第一次运行务必用吊架。

```cpp
// k1_hold_pose.cpp —— 用法：./k1_hold_pose 127.0.0.1   （在机器人上运行；事先让机器人处于 PREP 并站稳，挂好吊架）
#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <csignal>
#include <iostream>
#include <mutex>
#include <thread>

#include <booster/idl/b1/LowCmd.h>
#include <booster/idl/b1/LowState.h>
#include <booster/idl/b1/MotorCmd.h>
#include <booster/robot/b1/b1_api_const.hpp>
#include <booster/robot/b1/b1_loco_client.hpp>
#include <booster/robot/channel/channel_publisher.hpp>
#include <booster/robot/channel/channel_subscriber.hpp>

using namespace std::chrono;
using namespace booster::robot;
namespace bim = booster_interface::msg;
constexpr size_t N = b1::kJointCntK1;  // 22，不是 kJointCnt(23)

// K1_CFG.prepare_state（booster_deploy/booster_deploy/robots/k1.py:66-78）
const std::array<float, N> kTarget = {0, 0,  0, -1.3f, 0, 0,  0, 1.3f, 0, 0,
                                      0, 0, 0, 0.105f, -0.10f, 0,  0, 0, 0, 0.105f, -0.10f, 0};
const std::array<float, N> kKp = {40, 40,  40, 50, 20, 20,  40, 50, 20, 20,
                                  350, 350, 180, 350, 250, 250,  350, 350, 180, 350, 250, 250};
const std::array<float, N> kKd = {1.5f, 1.5f,  0.5f, 1.5f, 0.2f, 0.2f,  0.5f, 1.5f, 0.2f, 0.2f,
                                  7.5f, 7.5f, 3, 5.5f, 5, 5,  7.5f, 7.5f, 3, 5.5f, 5, 5};
// URDF 限位（booster_assets/robots/K1/K1_22dof.urdf），SERIAL 空间
const std::array<float, N> kQMin = {-1.012f, -0.314f, -2.932f, -1.642f, -1.885f, -2.242f, -2.932f, -1.642f, -1.885f, -0.816f,
                                    -2.958f, -0.375f, -1.012f, 0.f, -0.87f, -0.345f, -2.958f, -1.536f, -1.012f, 0.f, -0.87f, -0.345f};
const std::array<float, N> kQMax = {1.012f, 0.794f, 1.196f, 1.629f, 1.885f, 0.816f, 1.196f, 1.629f, 1.885f, 2.242f,
                                    2.226f, 1.536f, 1.012f, 2.321f, 0.345f, 0.345f, 2.226f, 0.375f, 1.012f, 2.321f, 0.345f, 0.345f};

std::mutex g_mtx;
std::array<float, N> g_q{};
std::array<float, 3> g_rpy{};
std::atomic<bool> g_have{false}, g_stop{false};
std::atomic<int64_t> g_last_ns{0};
int64_t NowNs() { return duration_cast<nanoseconds>(steady_clock::now().time_since_epoch()).count(); }

void OnLowState(const void *p) {
  const auto *s = static_cast<const bim::LowState *>(p);
  if (s->motor_state_serial().size() < N) return;              // 防御：长度不对就丢弃
  std::lock_guard<std::mutex> lk(g_mtx);
  for (size_t i = 0; i < N; ++i) g_q[i] = s->motor_state_serial()[i].q();
  g_rpy = s->imu_state().rpy();
  g_last_ns = NowNs();
  g_have = true;
}

int main(int argc, char **argv) {
  if (argc < 2) { std::cerr << "usage: " << argv[0] << " <ip，本机为 127.0.0.1>\n"; return 1; }
  std::signal(SIGINT, [](int) { g_stop = true; });
  ChannelFactory::Instance()->Init(0, argv[1]);                // domain 0

  ChannelSubscriber<bim::LowState> sub(b1::kTopicLowState, OnLowState);
  sub.InitChannel();
  ChannelPublisher<bim::LowCmd> pub(b1::kTopicJointCtrl);
  pub.InitChannel();
  b1::B1LocoClient loco;
  loco.Init();

  // 1) 等待首帧 low_state（最多 5 s）
  for (int i = 0; i < 50 && !g_have; ++i) std::this_thread::sleep_for(100ms);
  if (!g_have) { std::cerr << "no rt/low_state\n"; return 1; }
  std::array<float, N> q0; std::array<float, 3> rpy0;
  { std::lock_guard<std::mutex> lk(g_mtx); q0 = g_q; rpy0 = g_rpy; }
  // 2) 姿态检查（比 DEP 的 60° 更保守）
  if (std::fabs(rpy0[0]) > 0.3f || std::fabs(rpy0[1]) > 0.3f) { std::cerr << "not upright\n"; return 1; }
  // 3) 等待 joint_ctrl 的读端匹配
  for (int i = 0; i < 20 && pub.GetMatchedSubscriptionsCount() == 0; ++i) std::this_thread::sleep_for(500ms);
  if (pub.GetMatchedSubscriptionsCount() == 0) { std::cerr << "no joint_ctrl reader\n"; return 1; }

  // 4) 构造 LowCmd：SERIAL、22 个关节、weight = 0（Custom 下无效）、mode = 0
  bim::LowCmd cmd;
  cmd.cmd_type(bim::CmdType::SERIAL);
  cmd.motor_cmd().resize(N);
  auto fill = [&](const std::array<float, N> &q) {
    for (size_t i = 0; i < N; ++i) {
      auto &m = cmd.motor_cmd()[i];
      m.mode(0); m.q(std::clamp(q[i], kQMin[i], kQMax[i])); m.dq(0.f); m.tau(0.f);
      m.kp(kKp[i]); m.kd(kKd[i]); m.weight(0.f);
    }
  };
  fill(q0);
  pub.Write(&cmd);                                             // 5) 预发「保持当前位姿」帧，机器人会保存它
  std::this_thread::sleep_for(100ms);

  // 6) 切换到 Custom 并确认
  if (loco.ChangeMode(RobotMode::kCustom) != 0) { std::cerr << "ChangeMode(kCustom) failed\n"; return 1; }
  b1::GetStatusResponse st;
  if (loco.GetStatus(st) != 0 || st.current_mode_ != RobotMode::kCustom) { std::cerr << "not in Custom\n"; }

  // 7) 500 Hz：前 2 s 线性插值到目标，之后保持；带状态超时和倾角保护
  const auto dt = microseconds(2000);
  const int ramp = 1000;                                       // 1000 × 2 ms = 2 s
  auto next = steady_clock::now();
  std::array<float, N> q{};
  for (int k = 0; !g_stop; ++k) {
    const float a = std::min(1.f, static_cast<float>(k) / ramp);
    for (size_t i = 0; i < N; ++i) q[i] = q0[i] + a * (kTarget[i] - q0[i]);
    fill(q);
    pub.Write(&cmd);
    std::array<float, 3> rpy; { std::lock_guard<std::mutex> lk(g_mtx); rpy = g_rpy; }
    if (NowNs() - g_last_ns > 100'000'000) { std::cerr << "low_state stale\n"; break; }
    if (std::fabs(rpy[0]) > 0.5f || std::fabs(rpy[1]) > 0.5f) { std::cerr << "tilt\n"; break; }
    next += dt;
    std::this_thread::sleep_until(next);
  }
  // 8) 退出：回到 PREP（机器人自己站好）；在吊架上想让它瘫倒可以改成 kDamping
  loco.ChangeMode(RobotMode::kPrepare);
  pub.CloseChannel();
  sub.CloseChannel();
  return 0;
}
```

编译方法：把上面的文件放进 SDK 的 `example/low_level/`，然后在 `SDK/CMakeLists.txt` 里追加一行 `add_executable(k1_hold_pose example/low_level/k1_hold_pose.cpp)`。SDK 的 CMakeLists 通过 `link_libraries` 统一链接 `lib/<arch>/libbooster_robotics_sdk.a`、Threads、dl 和 rt，并且使用 C++17（`SDK/CMakeLists.txt:19,35-41`）。机器人上的 arch 是 aarch64。

### 7.2 Python（ROS 2，不依赖 SDK，改写自 DEP）

改写自 `DEP/booster_deploy/controllers/booster_robot_controller.py:156-498`。⚠未实机运行。

```python
# 运行前：source /opt/ros/humble/setup.bash && source /opt/booster/BoosterRos2Interface/install/setup.bash
import json, threading, time, numpy as np, rclpy
from rclpy.executors import SingleThreadedExecutor
from rclpy.qos import QoSProfile, ReliabilityPolicy, HistoryPolicy
from booster_interface.msg import LowState, LowCmd, MotorCmd, BoosterApiReqMsg
from booster_interface.srv import RpcService

N = 22
TARGET = np.array([0,0, 0,-1.3,0,0, 0,1.3,0,0, 0,0,0,0.105,-0.10,0, 0,0,0,0.105,-0.10,0], np.float32)  # k1.py:75-78
KP = [40,40, 40,50,20,20, 40,50,20,20, 350,350,180,350,250,250, 350,350,180,350,250,250]           # k1.py:67-70
KD = [1.5,1.5, 0.5,1.5,0.2,0.2, 0.5,1.5,0.2,0.2, 7.5,7.5,3,5.5,5,5, 7.5,7.5,3,5.5,5,5]               # k1.py:71-74
QMIN = np.array([-1.012,-0.314,-2.932,-1.642,-1.885,-2.242,-2.932,-1.642,-1.885,-0.816,
                 -2.958,-0.375,-1.012,0,-0.87,-0.345,-2.958,-1.536,-1.012,0,-0.87,-0.345], np.float32)
QMAX = np.array([1.012,0.794,1.196,1.629,1.885,0.816,1.196,1.629,1.885,2.242,
                 2.226,1.536,1.012,2.321,0.345,0.345,2.226,0.375,1.012,2.321,0.345,0.345], np.float32)

rclpy.init()
node = rclpy.create_node("k1_hold_pose")
st = {"q": None, "rpy": None, "t": 0.0}
def on_state(m):
    if len(m.motor_state_serial) < N:
        return
    st["q"] = np.array([s.q for s in m.motor_state_serial[:N]], np.float32)
    st["rpy"] = np.array(m.imu_state.rpy, np.float32)
    st["t"] = time.monotonic()
node.create_subscription(LowState, "/low_state", on_state,
    QoSProfile(depth=1, reliability=ReliabilityPolicy.BEST_EFFORT, history=HistoryPolicy.KEEP_LAST))
pub = node.create_publisher(LowCmd, "joint_ctrl",
    QoSProfile(depth=1, reliability=ReliabilityPolicy.RELIABLE, history=HistoryPolicy.KEEP_LAST))
rpc = node.create_client(RpcService, "booster_rpc_service")
ex = SingleThreadedExecutor(); ex.add_node(node)
threading.Thread(target=ex.spin, daemon=True).start()

def call(api_id, body=None, timeout=3.0):
    req = RpcService.Request(); req.msg = BoosterApiReqMsg()
    req.msg.api_id = api_id; req.msg.body = json.dumps(body) if body is not None else ""
    fut = rpc.call_async(req); t0 = time.monotonic()
    while not fut.done() and time.monotonic() - t0 < timeout:
        time.sleep(0.01)
    return (fut.result().msg.status, fut.result().msg.body) if fut.done() else (None, None)

cmd = LowCmd(); cmd.cmd_type = LowCmd.CMD_TYPE_SERIAL
cmd.motor_cmd = [MotorCmd() for _ in range(N)]
def fill(q):
    for i, m in enumerate(cmd.motor_cmd):
        m.q = float(np.clip(q[i], QMIN[i], QMAX[i])); m.dq = 0.0; m.tau = 0.0
        m.kp = float(KP[i]); m.kd = float(KD[i]); m.weight = 0.0

try:
    t0 = time.monotonic()
    while st["q"] is None and time.monotonic() - t0 < 5.0: time.sleep(0.05)       # 1) 等首帧
    assert st["q"] is not None, "no /low_state"
    assert abs(st["rpy"][0]) < 0.3 and abs(st["rpy"][1]) < 0.3, "not upright"      # 2) 姿态检查
    assert rpc.wait_for_service(timeout_sec=15.0), "no booster_rpc_service"
    while pub.get_subscription_count() == 0: time.sleep(0.5)                       # 3) 等读端匹配
    q0 = st["q"].copy(); fill(q0); pub.publish(cmd); time.sleep(0.1)               # 4-5) 预发保持帧
    status, _ = call(2000, {"mode": 3})                                             # 6) ChangeMode(kCustom)
    status, body = call(2018)
    assert status == 0 and json.loads(body)["current_mode"] == 3, "not in Custom"
    start = time.perf_counter(); k = 0
    while True:                                                                     # 7) 500 Hz 插值并保持
        a = min(1.0, k / 1000.0)
        fill(q0 + a * (TARGET - q0)); pub.publish(cmd)
        if time.monotonic() - st["t"] > 0.1 or np.any(np.abs(st["rpy"][:2]) > 0.5):
            break
        k += 1
        while time.perf_counter() < start + k * 0.002: time.sleep(0.0002)
except KeyboardInterrupt:
    pass
finally:
    call(2000, {"mode": 1})                                                         # 8) 回到 PREP（RobotMode::kPrepare = 1）
    rclpy.shutdown()
```

---

## 8. 存疑点汇总（⚠待实机验证）

| # | 问题 | 现状 | 验证方法 |
| --- | --- | --- | --- |
| 1 | `rt/low_state` 的实际频率 | 从 GYM 的时钟设计推断约 500 Hz | `ros2 topic hz /low_state` |
| 2 | 机器人端 QoS | 推断 low_state 的 writer 为 RELIABLE、joint_ctrl 的 reader 为 BEST_EFFORT | `ros2 topic info -v` |
| 3 | 断流后的行为 | 推断会保持最后一帧 | 吊架上 kill 进程并观察 |
| 4 | PD 在驱动板还是主控执行，频率多少 | 只能推断在机器人侧 | 看 `reserve[1]`；做阶跃响应测试 |
| 5 | `MotorCmd.mode` 的取值含义（0 与 0x0A） | 没有文档 | 询问官方，或做对比实验 |
| 6 | `weight` 在 UpperBodyCustomControl 下的作用 | Custom 下已确认无效 | 对比实验 |
| 7 | CUSTOM → WALK 是否允许 | 手册说不允许，DEP 的默认做法却是这样 | 在当前固件上直接试 |
| 8 | SERIAL 模式下踝 kp 如何映射 | 已知 kd 在电机侧生效；GYM 用力矩化绕开 kp 映射 | 比较两种方式下踝的跟踪误差 |
| 9 | Custom 下固件是否截断关节限位和力矩 | 超限会进入 PROTECT | 发送端自己 clamp |
| 10 | 手柄急停在 Custom 下是否有效 | 没有文档 | 首次上机前实测 |
| 11 | ArmController 在 K1 上用 23 关节数组 | 可能不匹配 | 读源码或实测，自己写时用 22 |
| 12 | `reliable=false` 时 SDK writer 的实际 QoS | 代码只是保留 XML 默认值 | 用 `ros2 topic info -v` 查看 SDK 发布端 |
| 13 | DEP 自带 BeyondMimic checkpoint 的 scale 与本地 TRN 源码不一致 | checkpoint 来自另一版训练配置 | 部署自己的模型时逐项对齐 |
