# Booster K1 SDK 高层 API 参考

> ⚠ **本队使用固件 ≥ 1.7 + SDK `d5d8f7a`（`refs/booster_robotics_sdk@fw1.7`，= 主办方 `sdk_release.zip`）+ 主办方 Demo 1.7。** 本文按最新 SDK 1.6.3（`87a9a26`）/ 固件 1.8 撰写；在 1.7 上不同的地方用【fw1.7 #N】标出，完整说明见 `fw1.7-demo-v1.7.md` §4。

> 适用对象：在 Booster K1 上做 RoboCup 人形足球的开发者。
> 依据：本地 `refs/`（只读）。本地 SDK 快照：`refs/booster_robotics_sdk` 提交 `87a9a26 feat: update for 1.8.0 firmware`，对应 C++ SDK 包 v1.6.3（`refs/booster_docs/developer-guide__cpp__changelog.md`，2026-09-15）。【fw1.7 #1】本队 1.7 栈的 C++ SDK 是 `d5d8f7a`（`refs/booster_robotics_sdk@fw1.7`，= 主办方 `sdk_release.zip` = PyPI 1.3.9 sdist 里的 `sdk_release/`）；Python 用 1.5.6。
> 标注约定：`【源】` 后面是证据文件路径（相对 `RoboCup/`）；**待实机验证** 表示本地资料里找不到定论；`[wheel]` 表示证据来自 PyPI 包 `booster_robotics_sdk_python-1.6.3` 解包后的文件（不在 refs 里，2026-09-24 下载核对，文件为 `python_example/*.py`、`booster_robotics_sdk_python/*.py`）。

---

## 0. 速查（10 条）

1. 所有高层能力都是**跑在 FastDDS 上的 RPC**。先调用 `ChannelFactory::Instance()->Init(0, "<本机网卡IP>")`，再调用 `B1LocoClient::Init()`；顺序反了不能工作。【源】`refs/booster_robotics_sdk/include/booster/robot/b1/b1_loco_client.hpp`（"This class does not initialize ChannelFactory"）
2. 正常上电顺序：`kDamping → kPrepare → kWalking`。DAMP 不能直接切到 WALK。【源】`refs/booster_docs/product-manual__k1__basic-operations__modes.md`
3. 连续速度控制用 `MoveCommand(vx,vy,vyaw)`（不等回复），不要用阻塞的 `Move()`（默认等待 1 s）。官方 `MoveController` 的发送周期约为 20 ms。【源】`include/booster/robot/b1/move_controller.hpp`、`include/booster/robot/rpc/rpc_client.hpp`
4. 速度单位：m/s 和 rad/s。vx 向前为正，vy 向左为正，vyaw 逆时针为正。服务端会按当前模式和机型的限值做裁剪，SDK 里**没有写死范围**。K1 规格：最大步行 1.1 m/s、最大转向 1.5 rad/s。
5. 返回码：`0` 成功，`100` 超时，`400` 参数错误，`409` 冲突，`429` 请求过频，`500` 服务内部错误，`501` 被拒绝（能力未开启），`502` 状态机切换失败，`503` 电量低。【源】`include/booster/robot/rpc/error.hpp`【fw1.7 #2】`d5d8f7a` 的 `error.hpp` 到 502 为止，没有 503；固件是否返回 503 待实机验证。
6. 足球相关：`RobotMode::kSoccer`（仅 K1/T1）、`VisualKick(start, kV1|kV2)` + 话题 `rt/kick_ball`（`brain::msg::Kick`）、`GetUpWithMode(kSoccer, kV2)`（kV2 仅 K1）、`SwitchGait`、`EnterWBCGait`、话题 `rt/robocup_behavior_status`。
7. **K1 上不要调用 `LieDown()`**。头文件明确说明：K1 上它可能返回成功，但实际执行的是零位轨迹，不是躺下动作。【fw1.7 #3】这条警告只在 1.6.3 头文件里；`d5d8f7a` 只写了「unstable」（`b1_loco_client.hpp:272-279`）。禁止调用的结论不变。
8. Python 有两套：旧的 `booster_robotics_sdk_python`（C++ 的 pybind 封装，API 与 C++ 同名，出错抛 `RuntimeError`）；新的 `boosteros`（Booster OS Python SDK，基于 ROS 2，字符串模式名，要求固件 ≥ v1.7，只能跑在机器人本体或 Booster Studio 虚拟机器人上）。
9. ROS 2 名 `/xxx` 与 SDK 的 DDS 名 `rt/xxx` 是同一个话题。`robocup_demo` 不链接 SDK 库，而是直接往 ROS 2 话题 `LocoApiTopicReq` 发 `booster_msgs/RpcReqMsg`，并往 `/kick_ball` 发 Kick 消息。
10. 固件与 SDK 必须配套。旧 5v5 Demo 文档要求"固件 1.6 配 SDK 1.3.6"；当前仓库对应固件 1.8.0。在机器人上可用 `booster-cli version` 查看版本。【fw1.7 #4】本队现为固件 ≥ 1.7 + SDK `d5d8f7a` + Python 1.5.6。

---

## 1. SDK 整体架构

### 1.1 分层

```
应用层   你的程序 (C++ / Python pybind / boosteros / ROS 2 节点)
         │ B1LocoClient 等 RPC 客户端         │ ChannelPublisher/Subscriber
接口层   RpcClient (JSON over DDS)              DDS Topic (IDL 强类型)
         │                                      │
通信层   FastDDS（SDK 自带、改名空间 booster_eprosima）  ← 与 ROS 2 DDS 线协议兼容
服务层   机器人本体上的 Booster Service（运动/视觉/音频/灯/AI…），ROS 2 桥 /opt/booster/BoosterRos2*
```
【源】`refs/booster_docs/developer-guide__cpp__sdk-overview.md`（"uses Fast DDS … compatible with ROS 2 … When message types, topic names, and QoS settings match"）、`developer-guide__cpp__architecture.md`

- FastDDS 以源码头文件形式打包在 `include/booster_fastdds/`，命名空间为 `booster_eprosima::fastdds`，并静态链接进 `lib/<arch>/libbooster_robotics_sdk.a`。因此不需要单独安装 FastDDS，也不会和系统里的 ROS 2 FastDDS 冲突。【源】`include/booster/common/dds/dds_factory_model.hpp`
- IDL 类型名遵循 ROS 2 约定。库中注册的类型名形如 `booster_interface::msg::dds_::LowState_`，所以和 ROS 2 包 `booster_interface` 的消息在线上可以互通。【源】对 `lib/x86_64/libbooster_robotics_sdk.a` 执行 `strings` 的结果

### 1.2 `ChannelFactory::Init` 的含义

【源】`include/booster/robot/channel/channel_factory.hpp`

| 重载 | 说明 |
|---|---|
| `Init(int32_t domain_id, const std::string& network_interface = "")` | 最常用。`domain_id` 为 DDS 域号，默认 0，必须与机器人上的服务一致。第二个参数在头文件中叫 `network_interface`，文档称为 "network IP"，示例值为 `127.0.0.1` 或 `192.168.10.102`；传空串表示使用默认网络配置 |
| `Init(const nlohmann::json& config)` | 用 JSON 配置初始化 DDS |
| `InitDefault(int32_t domain_id)` | 使用 SDK 默认设置 |
| `InitWithConfigPath(int32_t domain_id, const std::string& xml)` | 加载 FastDDS XML 配置 |

- 这是**进程级单例**，一个进程只初始化一次。`MoveController` 和 `ArmController` 的构造函数内部会自己调用 `Init(0, ip)`。【源】`include/booster/robot/b1/move_controller.hpp`、`refs/booster_docs/developer-guide__cpp__controllers.md`
- 第二个参数应理解为**本机**用于 DDS 通信的网卡或地址（相当于 FastDDS 的 interface whitelist），而不是"机器人的 IP"。依据有三：头文件中参数名为 `network_interface`；`MoveController` 注释写的是 "Network interface name or address"；`refs/robocup_demo/configs/fastdds.xml` 的 `interfaceWhiteList` 列出的也是本机地址（127.0.0.1、192.168.10.101/102）。在 K1 本体上运行时传 `127.0.0.1`；在开发机上运行时，推测应传开发机在机器人网段的 IP（有线直连时开发机为 `192.168.10.10`，机器人为 `192.168.10.102`，【源】`product-manual__k1__basic-operations__connect-robot.md`）。**跨机运行待实机验证。**
- 未 Init 就创建通道时，只会打印 `ChannelFactory is not initialized…` 并返回 `nullptr`，不会抛异常。

### 1.3 RPC 是怎么基于 DDS 实现的

【源】`include/booster/robot/rpc/rpc_client.hpp`、`request_header.hpp`、`include/booster/idl/rpc/RpcReqMsg.h`、`refs/robocup_demo/src/brain/src/robot_client.cpp`

- 每个业务客户端绑定一个"通道基名"，例如 `rt/LocoApiTopic`。`RpcClient::Init(name)` 会创建请求写者 `<name>Req` 和响应读者 `<name>Resp`（库中有 `Req`/`Resp` 字符串；robocup_demo 直接发布到 ROS 2 话题 `"LocoApiTopic" + suffix + "Req"`，两者吻合）。
- 请求消息 `booster_msgs::msg::RpcReqMsg { string uuid; string header; string body; }`，响应 `RpcRespMsg` 的结构相同。【源】`refs/robocup_demo/src/interface/booster_msgs/msg/RpcReqMsg.msg`
  - `header` 是 JSON 字符串，字段有 `api_id`（即 `LocoApiId` 数值）、`call_mode`、`req_id`、`operation_command`。robocup_demo 只填了 `{"api_id": N}`。【fw1.7 #5】`d5d8f7a` 的 `RequestHeader` 只有 `api_id` 和 `expect_response`（`rpc/request_header.hpp:10-53`），fire-and-forget 靠 `expect_response=false` 实现。
  - `body` 是参数类 `XxxParameter::ToJson().dump()` 的结果，例如 Move 为 `{"vx":..,"vy":..,"vyaw":..}`。
  - 通过 `uuid` 把请求和响应对应起来（`RpcClient::GenUuid()`）。
- 三种调用模式 `RpcCallMode`：`kRequestResponse=0`（同步，`SendApiRequest` 默认超时 1000 ms）、`kFireAndForget=2`（`MoveCommand` 使用此模式；等待端点匹配最多 1000 ms）、`kOperation=1`（异步长任务，事件从 `rt/LocoApiOperationEvent` 返回，接口为 `AsyncSendApiRequest` / `AsyncCancelOperation` / `WaitForOperationService`；1.8.0 固件的 changelog 把它称为 "action-state callback interface"）。【fw1.7 #6】`d5d8f7a` 没有 `RpcCallMode`、`kOperation`、`rt/LocoApiOperationEvent` 和 Async 系列接口（1.8 才有）。
- `WaitForService(timeout_ms = 5000, require_response_path = true)` 在请求和响应端点都被发现后返回 `true`。
- 多机器人命名：`Init(robot_name)` 会把通道改成 `rt/LocoApiTopic/<robot_name>`。

RPC 通道一览（从库的字符串和头文件注释中提取）：

| 客户端 | 命名空间 | 通道 | 头文件 |
|---|---|---|---|
| `B1LocoClient` | `booster::robot::b1` | `rt/LocoApiTopic`（+`rt/LocoApiOperationEvent`）【fw1.7 #6】1.7 只有 `rt/LocoApiTopic` | `robot/b1/b1_loco_client.hpp` |
| `AiClient` / `LuiClient` | `booster::robot` | `rt/AiApiTopic` / `rt/LuiApiTopic` | `robot/ai/client.hpp` |
| `VisionClient` / `HandEyeCalibClient` | `booster::robot::vision` | `rt/VisionApiTopic` / `rt/HandEyeCalibApiTopic` | `robot/vision/*.hpp` |
| `CameraClient` | `booster::robot::camera` | `rt/CameraApiTopic` | `robot/camera/camera_client.hpp` |
| `X5CameraClient` | `booster::robot::x5_camera` | `rt/X5CameraControl` | `robot/x5_camera/*.hpp` |
| `LightControlClient` | `booster::robot::light` | `rt/LightControlApiTopic` | `robot/device/light/*.hpp` |
| `AudioManager` | `booster::robot::audio` | `rt/booster/audio/<method>`（一个方法一个服务） | `robot/audio/audio_manager.h` |

### 1.4 C++ 与 Python 绑定的关系

- C++ SDK 以**预编译静态库**加头文件的形式发布，没有 `.cpp` 源码。【源】`refs/booster_robotics_sdk/lib/{x86_64,aarch64}/libbooster_robotics_sdk.a`
- Python 绑定不在这个仓库里，通过 pip 单独发布：`pip install booster_robotics_sdk_python`。【源】`refs/booster_robotics_sdk/README.md`。它是 pybind11 模块（`booster_robotics_sdk_python/_core.*.so`），类名和方法名与 C++ 保持 PascalCase 一致，另外附带纯 Python 写的 `MoveController` 和 `ArmController`。[wheel] `booster_robotics_sdk_python/__init__.py`
- 与 C++ 的主要差异（[wheel] `python_example/sdk_pybind_b1_example.py`）：
  - 用 `client.InitWithName(name)` 代替 C++ 的 `Init(name)` 重载。
  - 查询类方法直接返回对象，例如 `GetMode().mode`、`GetStatus().current_mode`、`GetRobotInfo().version`、`GetFrameTransform(src,dst).position.x`。
  - 底层返回码非 0 时**抛 `RuntimeError`**（示例注释："Catch runtime_error thrown by pybind when the underlying API returns a non-zero code"），同一说法见 `refs/booster_docs/developer-guide__cpp__rpc__ai-lui.md`。
  - 参数类提供 `to_json_str()`，`SendApiRequest(int(LocoApiId.kX), json)` 可以直接发送原始 JSON。
  -
- `booster_gym` 部署代码中的用法：`ChannelFactory.Instance().Init(0, args.net)`、`B1LocoClient()`、`B1LowStateSubscriber(cb)`、`B1LowCmdPublisher()`、`RobotMode.kCustom`。【源】`refs/booster_gym/deploy/deploy.py`

### 1.5 ROS 2 SDK 与原生 SDK 的关系

- `refs/booster_robotics_sdk_ros2` **只是接口包加示例**：ROS 2 包名为 `booster_interface`（目录 `booster_ros2_interface/`），里面是 msg/srv 定义和 `message_utils.hpp`（该头文件 `#include <booster/robot/b1/b1_loco_api.hpp>`，所以**编译时需要先装好 C++ SDK 头文件**）。ROS 2 桥本身（RPC 服务端、话题转发）在机器人固件里（`/opt/booster/BoosterRos2*`），不在这个仓库。【源】`booster_ros2_interface/include/booster_interface/booster_interface/message_utils.hpp`、`refs/robocup_demo/scripts/start.sh`、`refs/booster_docs/developer-guide__open-source__booster-deploy.md`
- 话题名的对应关系：SDK 的 `rt/low_state` 就是 ROS 2 的 `/low_state`，`rt/odometer_state` 就是 `/odometer_state`，依此类推（ROS 2 在 DDS 层给话题加 `rt/` 前缀）。证据是 robocup_demo 在 ROS 2 中订阅 `/odometer_state`、`/low_state`、`/remote_controller_state`，发布 `/kick_ball`；SDK 常量对应 `rt/odometer_state`、`rt/low_state`、`rt/kick_ball`。【源】`refs/robocup_demo/src/brain/src/brain.cpp`、`main.cpp`，`include/booster/robot/b1/b1_api_const.hpp`
- ROS 2 中调用高层 RPC 有两条路：
  1. ROS 2 服务 `booster_rpc_service`，类型 `booster_interface/srv/RpcService`（请求 `BoosterApiReqMsg{int64 api_id; string body}`，响应 `BoosterApiRespMsg{int64 status; string body}`）。有返回码。【源】`booster_ros2_example/rpc_client/src/client.{cpp,py}`、`refs/booster_deploy/booster_deploy/controllers/booster_robot_controller.py`
  2. 直接发布 `booster_msgs/msg/RpcReqMsg` 到话题 `LocoApiTopic[/<robot_name>]Req`。这是 fire-and-forget，没有返回码，robocup_demo 用的就是这种方式。【源】`refs/robocup_demo/src/brain/src/robot_client.cpp`
- 另有 `booster_rtc_service`（RpcService 类型，用于 AI 对话 RTC），见 `booster_ros2_example/rtc_client/src/client.cpp`。

### 1.6 新旧 Python/SDK 对比与选型

| 维度 | booster_robotics_sdk（C++ / `booster_robotics_sdk_python`） | Booster OS Python SDK（`boosteros`） | ROS 2（`booster_interface`） |
|---|---|---|---|
| 形态 | C++ 静态库加 pybind 封装 | 纯 Python 高层客户端 `BoosterRobot` | msg/srv 接口加机器人侧 ROS 2 桥 |
| 底层 | 自带 FastDDS，直连 `rt/*` | ROS 2 节点（每个实例建一个 ROS node，可选 `domain_id`、`dds_profile`） | ROS 2 DDS |
| 运行位置 | 本体或开发机（Ubuntu 22.04/24.04，x86_64/aarch64） | **仅限机器人本体或 Booster Studio 虚拟机器人**；`network_interface` 为保留参数，固定为 `""` | 机器人本体（需 source 机器人上的 setup） |
| 版本要求 | 对应的最低固件逐接口列出（见 §3.1） | Python ≥ 3.10，固件 ≥ v1.7 | 跟随固件 |
| 模式/步态 | `RobotMode` 枚举、`GaitType`、全部 LocoApiId | 字符串：`"damping"/"prepare"/"walk"/"custom"`；步态为 `"default"/"soccer"` | 与 RPC 相同的 api_id 加 JSON |
| 阻塞语义 | 返回码；`ChangeMode` 只返回 RPC 状态 | `set_mode` 会**等待切换完成**，失败抛 `RuntimeError`；动作以 `TaskHandle` 异步执行 | 服务同步；话题方式无返回 |
| 足球 | `VisualKick` + `rt/kick_ball`、`kSoccer`、`Shoot` | `SoccerKickManager.start/update_ball/update_command/stop` | robocup_demo 的实现方式 |
| 适用场景 | 高频控制、C++ 决策栈、低层与高层混用 | 快速原型、Python 比赛框架（`refs/booster_champion_example` 使用它） | 已有 ROS 2 栈，例如 robocup_demo |

【源】`refs/booster_docs/developer-guide__booster-os-python-sdk__sdk-overview.md`、`…__booster-robot-client-reference__initialization.md`、`…__motion-control-apis__set-mode.md`、`…__set-gait.md`、`…__automatic-soccer-kick-manager__*.md`、`refs/booster_champion_example/src/soccer_framework/robot.py`

---

## 2. 安装与编译

### 2.1 C++ SDK

【源】`refs/booster_robotics_sdk/install.sh`、`README.md`、`CMakeLists.txt`、`refs/booster_docs/developer-guide__cpp__quick-start.md`、`developer-guide__cpp__cpp-api.md`

- 环境：Ubuntu 22.04 或 24.04（`install.sh` 用 `lsb_release -rs` 检查，其他版本直接退出），gcc 11.4.0 预编译，C++17，CPU 为 x86_64 或 aarch64。**macOS 和 Windows 都不支持。**
- `sudo ./install.sh` 做的事：
  1. 检查 Ubuntu 版本（22 或 24）。
  2. `apt update && apt install -y build-essential cmake`。
  3. 按 `uname -m` 选择 `lib/$arch`（若存在 `lib/$arch/$ubuntu` 子目录则优先使用）。
  4. `cp -r include/* /usr/local/include`，`cp -r lib/$arch/* /usr/local/lib`。
  5. `ldconfig`。
- 编译仓库自带示例（仓库内的 CMake 直接链接 `lib/${arch}/libbooster_robotics_sdk.a`，不依赖 install）：
  ```bash
  cmake -S . -B build && cmake --build build -j
  ./build/b1_loco_example_client 127.0.0.1
  ```
- 编译自己的工程（先 install）：
  ```cmake
  cmake_minimum_required(VERSION 3.15)
  project(my_booster_app CXX)
  set(CMAKE_CXX_STANDARD 17)
  find_package(Threads REQUIRED)
  add_executable(my_booster_app main.cpp)
  target_link_libraries(my_booster_app PRIVATE booster_robotics_sdk Threads::Threads ${CMAKE_DL_LIBS} rt)
  ```
- 在 K1 上编译还是在开发机上编译：K1 的计算单元是 ARM 平台（教育版 Jetson Orin NX 8GB，专业版 AGX Orin 32GB，【源】`product-manual__k1__getting-started__specifications.md`），应使用 aarch64 库在本机编译；开发机为 x86_64。仓库没有提供交叉编译工具链配置。在开发机上编译的程序只适合通过网络连机器人调试（参见 §1.2 的网卡参数）。
- 版本核对：在机器人上执行 `booster-cli version`（输出形如 `Firmware: 1.6.x / SDK: 1.3.6`，【源】`developer-guide__open-source__robocup-demo.md`），或 `cat /opt/booster/version.txt`（【源】`product-manual__k1__firmware-version__check-version.md`），或在程序里用 `GetRobotInfo().version_`（【源】`developer-guide__cpp__rpc.md`）。

### 2.2 Python

| 包 | 安装 | 说明 |
|---|---|---|
| `booster_robotics_sdk_python` | `pip install booster_robotics_sdk_python --user` | PyPI 最新 1.6.3（2026-09-16），提供 CPython 3.10–3.14、manylinux_2_34 x86_64/aarch64 wheel（glibc ≥ 2.34，即 Ubuntu 22.04+）。wheel 自带 `python_example/` 和命令行入口 `b1-cli`/`b1-low-level`/`b1-ros-rt-topics`/`b1-ai-cli`。**注意**：`entry_points.txt` 里 `b1-cli` 指向 `sdk_pybind_b1_exmaple`（拼写错误），而实际文件名是 `sdk_pybind_b1_example.py`，所以 `b1-cli` 很可能无法启动，改用 `python -m python_example.sdk_pybind_b1_example <ip>`。[wheel]【fw1.7 #7】1.7 栈固定 `==1.5.6`（与 `d5d8f7a` 同日发布、API 层级一致，有 `kJointCntK1`；它的 `b1-cli` 入口同样拼错，改用 `python3 -m python_example.sdk_pybind_b1_example <ip>`）。不要用 1.3.9：它的绑定是用旧头文件编的。 |
| `boosteros` | `python3 -m pip install boosteros`；需要语音或检测时装 `"boosteros[brain]"` | 【源】`developer-guide__booster-os-python-sdk__quick-start.md` |

### 2.3 ROS 2 接口

- 在 ROS 2 工作区里 `colcon build` 包 `booster_interface`（依赖 `rclcpp`、`rosidl_default_generators`，示例包为 `booster_rpc_client`）。【源】`refs/booster_robotics_sdk_ros2/booster_ros2_interface/CMakeLists.txt`、`booster_ros2_example/rpc_client/CMakeLists.txt`
- 机器人上已有预编译接口，使用前执行 `source /opt/booster/BoosterRos2Interface/install/setup.bash`。【源】`developer-guide__open-source__booster-deploy.md`
- robocup_demo 启动时使用 `FASTRTPS_DEFAULT_PROFILES_FILE=/opt/booster/BoosterRos2/fastdds_profile_udp_only.xml`（仅 UDP）。【源】`refs/robocup_demo/scripts/start.sh`

---

## 3. `B1LocoClient` 完整 API（K1 也使用 B1LocoClient）

没有单独的 "K1LocoClient"。头文件明确写 `Supported model: K1 | T1 | T2`，机型差异在服务端判断。【源】`include/booster/robot/b1/b1_loco_client.hpp`（下文未注明来源的均出自此文件或 `b1_loco_api.hpp`）

### 3.1 基础设施方法

| 方法 | 说明 |
|---|---|
| `void Init()` / `void Init(const std::string& robot_name)` | 绑定 `rt/LocoApiTopic[/<name>]`。Python 中为 `Init()` / `InitWithName(name)` |
| `bool WaitForService(int64_t timeout_ms=5000, bool require_response_path=true)` | 等待服务端点就绪；未 Init 时返回 false |
| `bool WaitForOperationService(int64_t timeout_ms=5000, bool require_event_path=true)`【fw1.7 #6】1.7 没有 | 等待异步 Operation 端点就绪 |
| `int32_t SendApiRequest(LocoApiId, const std::string& json[, int64_t timeout_ms])` | 同步调用，默认超时 1 s |
| `int32_t SendApiRequestFireAndForget(LocoApiId, json)` | 返回 0 只表示已提交，不代表已执行 |
| `int32_t SendApiRequestWithResponse(LocoApiId, json, Response&)` | 取原始响应，`resp.GetBody()` |
| `AsyncSendApiRequest(id, json[, SendApiRequestOptions])` → `ApiOperationSubmitResult`；`AsyncCancelOperation(handle)` → `std::shared_future<int32_t>`【fw1.7 #6】1.7 没有 | 异步长任务，start/result 回调；Python 中有 `ApiOperationResultCode.kSucceeded/kAborted/kCanceled/kRejected/kTimeout`（[wheel] `sdk_pybind_b1_async_operation_example.py`） |

最低固件版本（【源】`refs/booster_docs/developer-guide__cpp__rpc__motion.md`，指机器人固件而非 SDK 包；表中未列出的接口按 ≥ v1.7.1.0 处理）：ChangeMode/Move/RotateHead ≥1.0.0；WaveHand ≥1.0.2；GetFrameTransform ≥1.0.5.0；Handshake ≥1.0.6.0；Dance/GetMode ≥1.2.0.2；MoveHandEndEffector(V2)/StopHandEndEffector/GetStatus/GetRobotInfo ≥1.3.1.1；WholeBodyDance/UpperBodyCustomControl/GetUpWithMode/ZeroTorqueDrag/Record/ReplayTrajectory ≥1.4.0.7；ResetOdometry/Enter/ExitWBCGait/Load/Activate/UnloadCustomTrainedTraj ≥1.5.0.9；VisualKick ≥1.5.2.1；SwitchGait/LionDance* ≥1.6.0.10；ResetOdometryTo/GetTrainedTrajStatus ≥1.8.0.9。【fw1.7 #13】1.7 新增的 GetUpVersion kV2、GaitType 3、RotateHeadWithTime、GetSensors/GetHands/GetRobotModel、HandEyeCalibClient、CameraClient、SetLEDLightColors、`rt/odom|imu/data|joint_states` 都要求固件 ≥ 1.7.1；机器人若是 1.7.0.x，先实测返回码。

### 3.2 `RobotMode` 与切换顺序

【源】`include/booster/robot/common/robot_shared.hpp`、`product-manual__k1__basic-operations__modes.md`、`developer-guide__cpp__rpc__motion.md`

| 枚举 | 值 | 含义 | 可切入/切出 |
|---|---|---|---|
| `kUnknown` | -1 | 错误占位 | – |
| `kDamping` | 0 | 全关节阻尼，机器人会倒，需要支撑；属于安全模式 | 只能 → PREP（或 CUSTOM） |
| `kPrepare` | 1 | 双脚站立并保持姿态，抗扰能力弱 | → 任意模式 |
| `kWalking` | 2 | 行走、转向、踢球及行走模式下的动作，抗扰能力强 | → 任意模式（切回 DAMP 前要有支撑） |
| `kCustom` | 3 | 关节交给 `rt/joint_ctrl`。固件 ≥ v1.8.0.9 时，进入后会先保持站立，直到收到有效的 joint_ctrl【fw1.7 #8】1.7 上不会自动保持站立，必须先预发保持帧 | 只能从 PREP/DAMP 进入，只能切到 DAMP/PREP |
| `kSoccer` | 4 | 足球运动与动作，**仅 K1/T1**（T2 禁用） | 从 WALK 进入（robocup 文档中遥控器 LT+A 会进入 kSoccer），也可用 `GetUpWithMode(kSoccer)`。**通过 SDK 直接 ChangeMode(kSoccer) 时的合法前置状态待实机验证** |
| PROTECT（非枚举） | – | 超限或摔倒时自动进入，关节行为同 DAMP | 排查原因后重启 |

- 典型序列：`ChangeMode(kPrepare)` → 确认稳定站立 → `ChangeMode(kWalking)`。官方 C++ quick-start 在两步之间插了一次 `GetUp()`，本地 example 和 robocup 流程都没有这一步，**是否需要待实机验证**。
- C++ 的 `ChangeMode` 只返回 RPC 结果，不保证切换已经完成。可靠做法是之后轮询 `GetMode()`/`GetStatus()` 直到模式符合预期（booster_deploy 就是这样做的：最多重试 20 次 ChangeMode，每次后用 GetStatus 校验，【源】`refs/booster_deploy/booster_deploy/controllers/booster_robot_controller.py`）。`boosteros.set_mode()` 内部已经会等待切换完成。
- `BodyControl`（`GetStatus` 与 `rt/robot_states` 中返回）：0 Unknown，1 Damping，2 Prepare，3 HumanlikeGait，4 ProneBody，5 SoccerGait，6 Custom，7 GetUp，8 WholeBodyDance，9 Shoot，10 InsideFoot（即 visual-kick V2），11 Goalie，12 WBCGait，13 LionDancePreparePose，14 VisualKickV1。

### 3.3 运动与步态

| 方法 | 参数与单位 | K1 | 说明 |
|---|---|---|---|
| `Move(float vx, float vy, float vyaw)` | m/s, m/s, rad/s | ✅ | 同步，等待回复（默认 1 s）。服务端按当前模式和机型限值裁剪 |
| `MoveCommand(vx, vy, vyaw)` | 同上 | ✅ | fire-and-forget，用于周期性下发速度 |
| `SwitchGait(GaitType)` | `kWholeBodyHumanlikeGait=0`、`kHalfBodyHumanlikeGait=1`、`kHalfBodyHumanlikeGaitV2=2`、`kWholeBodyHumanlikeGaitV2=3` | ✅（四种主要在 K1 上配置） | 找不到对应控制器时返回 502 |
| `EnterWBCGait()` / `ExitWBCGait()` | – | ✅（当前 K1 固件提供） | 退出后回到 humanlike 步态 |
| `ResetOdometry()` | – | ✅ | 把 (x,y,θ) 置零 |
| `ResetOdometryTo(double x, double y, double theta)`【fw1.7 #9】`d5d8f7a` 没有，只能 `ResetOdometry()` 清零 | m, m, rad，必须是有限值 | ✅（固件 ≥ 1.8.0.9） | 文档说明要在"步态控制激活时"调用；boosteros 的 `reset_odom` 不在 walk 模式时会抛错 |

速度范围：SDK 和文档都**没有给出数值上下限**，只写了服务端裁剪。参考值：
- K1 规格：步行 1.1 m/s，转向 1.5 rad/s（`product-manual__k1__getting-started__specifications.md`）。
- 各示例取值：C++ example 为 ±0.2 m/s、±1.0 rad/s（`example/high_level/b1_loco_example_client.cpp`）；Python example 为 vx 0.8 / vy ±0.6 / 后退 −0.6 / yaw ±0.6（[wheel]）；boosteros 建议初次测试 ≤ 0.3 m/s。
- robocup_demo 在 K1 上的限幅是 `vx_limit 1.0, vy_limit 0.4, vtheta_limit 1.2`，并设了最小值 `min_vx 0.3, min_vy 0.3, min_vtheta 0.25`，注释为 "to prevent no response"（【源】`refs/robocup_demo/src/brain/config/config.yaml`）。boosteros 的 FAQ 也提到"速度太小不动"。**实际死区和上限待实机验证。**

### 3.4 头部

| 方法 | 参数 | K1 | 说明 |
|---|---|---|---|
| `RotateHead(float pitch, float yaw)` | rad | ✅ | pitch 正值为低头，yaw 正值为向左（依据：C++ example 中 `hd` pitch=1.0 低头、`hu` −0.3 抬头、`hl` yaw=+0.785 向左；boosteros 的 `set_head_angle` 文档也这样定义） |
| `RotateHeadWithTime(pitch, yaw, int time_millis)` | rad, ms | ✅ | 在指定时间内到达目标 |
| `RotateHeadWithDirection(int pitch_dir, int yaw_dir)` | 取值 −1/0/1 | ✅ | 连续转动，到关节限位时被裁剪 |

K1 头部关节限位：Head Yaw ±59°（约 ±1.03 rad），Head Pitch −19°～+49°（约 −0.33～+0.86 rad）（`specifications.md`）。C++ example 中 `hd` 用的 pitch=1.0 已经超过 K1 限位。boosteros 文档说明超限**不会报错，但会停止响应**。robocup_demo 默认限幅为 yaw ±1.1、pitch 上限 0.45（`src/brain/src/brain_config.cpp`）。

### 3.5 足球相关（重点）

| 接口 | K1 | 细节 |
|---|---|---|
| `ChangeMode(RobotMode::kSoccer)` | ✅（K1/T1） | 足球步态 `BodyControl::kSoccerGait=5` |
| `GetUpWithMode(RobotMode mode, GetUpVersion v=kV1)` | ✅ | `mode` 取 `kWalking` 或 `kSoccer`；`kV2`（"BMM get-up"）**仅 K1** 支持 |
| `VisualKick(bool start, VisualKickVersion v=kV1)` | ✅（固件 ≥ 1.5.2.1） | 侧脚视觉踢球的开关。没有机型门控：`kV1` 走基础路径；`kV2` 在开启了 WBC 的配置下走 WBC 路径，否则回退到非 WBC 路径。动作不可达时返回 502。JSON 为 `{"start":bool,"version":int}`【fw1.7 #10】这是 1.6.3 头文件的注释；`d5d8f7a` 对 kV2 的注释是「stronger kicking force」（`b1_loco_api.hpp:1091`），实际行为由固件决定 |
| 话题 `rt/kick_ball`（`b1::kTopicKickReference`） | ✅（K1/T1） | 视觉踢球的参考输入，类型 `brain::msg::Kick`（`include/booster/idl/b1/Kick.h`），字段：`header`；`x, y`（球相对机器人，m）；`dir`（期望踢球方向，相对机器人，rad）；`goal_x, goal_y`（球门相对机器人）；`robot_theta_to_field`（rad）；`power`（期望踢远距离）。字段含义取自 `refs/robocup_demo/src/brain/msg/Kick.msg` 的注释。Python 端发布器为 `B1VisualKickReferencePublisher`（[wheel] `.so` 符号），**对应的 Python 消息类名待验证**，可用 `help()` 查看 |
| `Shoot()` | ⚠️ | "powerful kick"。没有机型门控，"T1 provides the intended shooting motion"；K1 上若没有可达动作会返回 502。**K1 是否可用待实机验证** |
| 话题 `rt/robocup_behavior_status` | ✅（K1/T1） | `RobocupBehaviorStatus.status()`：0 RUNNING，1 SHOOTING，2 PASSING |
| 话题 `rt/prone_body_control_status` | 字段存在 | `posture`：…4 kSoccerLocomotion，5 kSoccerKicking。**非 inactive 状态由 T1 专用控制器产生** |
| `WholeBodyDance(kBoxingStyleKick=5 / kRoundhouseKick=6)` | ✅（K1） | 表演类踢腿轨迹，不是比赛射门 |

推荐的踢球流程（综合三份来源）：
- boosteros `SoccerKickManager`：`start()`（进入足球模式并开启视觉踢球）→ `update_command(direction rad, power 1.0–10.0)` → 持续调用 `update_ball(x,y)`（机器人系，m，x 向前、y 向左）→ `stop()`。【源】`…automatic-soccer-kick-manager__*.md`
- robocup_demo：先减速到 0 → `VisualKick(start)`（body 只有 `{"start":true}`）→ 每帧发布 `/kick_ball`（远于 6 m 时 power=1.5，否则 6.0）→ 退出时减速并 `ChangeMode(kWalking)`。【源】`refs/robocup_demo/src/brain/src/brain_tree.cpp`（`RLVisionKick`）、`brain.cpp`（`pubKickMsg`）
- 官方 5v5 Demo 1.6 文档：`visual_kick_version: kV2` 是推荐配置，理由是摆腿幅度大、踢得远、对测距误差容忍度高。【源】`developer-guide__open-source__robocup-demo.md`

C++ SDK 中等价的流程**待实机验证**：`ChangeMode(kSoccer)`（或保持 kWalking）→ `VisualKick(true, kV2)` → 以固定频率发布 `rt/kick_ball` → `VisualKick(false)`。

### 3.6 起身、躺下与摔倒

| 接口 | K1 | 说明 |
|---|---|---|
| `GetUp(GetUpVersion v=kV1)` | ✅（kV2 仅 K1） | `kV1=0` 为基础起身，`kV2=1` 为 BMM 起身。1.7.2 固件优化过 K1 起身（`changelog__v1-7-2-firmware-release.md`） |
| `GetUpWithMode(mode, v)` | ✅ | 起身后直接进入 kWalking 或 kSoccer |
| `LieDown()` | ⛔ **K1 禁用** | 头文件警告：K1 配置的嵌套轨迹槽位都是占位，调用可能返回成功但执行零位轨迹。该接口标注为不稳定【fw1.7 #3】 |
| 话题 `rt/fall_down` | ✅ | `FallDownState{ fall_down_state: IS_READY=0/IS_FALLING=1/HAS_FALLEN=2/IS_GETTING_UP=3, is_recovery_available: bool }`（`include/booster/idl/b1/FallDownState.h`） |

自动起身逻辑可参考 robocup_demo 的 `CheckAndStandUp`：当检测到 `HAS_FALLEN`、未处于罚下状态且重试次数小于上限（默认 2–3）时，发送 `kGetUp`。它订阅的是固件的 ROS 2 话题 `fall_down_recovery_state`（`RawBytesMsg`，结构为 `{uint8 state, is_recovery_available, current_planner_index}`），并用 `current_planner_index==1/2/8/10/20` 这类魔数判断，**这些魔数在 SDK 里没有文档**（【源】`src/brain/src/brain.cpp:1389`、`brain_tree.cpp`、`include/types.h`）。SDK 库内部确实有 `booster_interface::msg::FallDownRecoveryState` 类型，但没有公开头文件。

### 3.7 手臂与手（足球比赛基本用不到）

| 方法 | K1 | 说明 |
|---|---|---|
| `MoveHandEndEffectorV2(const Posture& target, int time_ms, HandIndex)` | ✅ | 推荐接口。躯干系，m/rad |
| `MoveHandEndEffector(...)` | ✅（已弃用） | 存在隐式旋转偏置 |
| `MoveHandEndEffectorWithAux(target, aux, time_ms, hand)` | ✅ | 圆弧辅助点 |
| `MoveDualHandEndEffector(left, right, time_ms)` | ✅ | 双臂同步 |
| `StopHandEndEffector()` | ✅ | 规划器未激活时返回 400 |
| `ControlGripper(GripperMotionParameter, GripperControlMode, HandIndex)` / `ControlDexterousHand(vector<DexterousFingerParameter>, HandIndex, BoosterHandType)` | 取决于硬件 | K1 标配没有手；需要 `GetHands()` 报告有对应设备 |
| `SwitchHandEndEffectorControlMode(bool)` | ⛔ 已弃用 | robot-state-manager 后端返回 400。ROS 2 示例里仍在使用，不要照抄 |
| `UpperBodyCustomControl(bool)` | ✅ | 上半身交给 `rt/joint_ctrl`（ArmController 使用此接口） |
| `ZeroTorqueDrag(bool)` / `RecordTrajectory(bool)` / `ReplayTrajectory(path)` | ✅ | 拖动示教 |

`HandIndex`：`kLeftHand=0`，`kRightHand=1`。`HandAction`：`kHandOpen=0`（开始），`kHandClose=1`（停止）。

### 3.8 动作、声音、轨迹

| 方法 | K1 | 说明 |
|---|---|---|
| `WaveHand(HandAction)` | ✅（开始和停止都支持） | 固定右手 |
| `Handshake(HandAction)` | 取决于配置 | |
| `Dance(DanceId)` | ✅ | 0 NewYear … 7 LuckyCat，1000 Stop |
| `WholeBodyDance(WholeBodyDanceId)` | ✅ 0–3、5–9 | 没有 ID 4；10、11 仅 T2 |
| `PlaySound(path)` / `StopSound()` | ✅ | `path` 是机器人服务端的路径 |
| `LionDancePrepare(bool)` / `LionDanceMove(bool)` / `LionDanceStart(int id)` | ✅ | 严格的状态机顺序。从其他状态直接调用 Start 会导致手臂跳变 |
| `LoadCustomTrainedTraj(traj, std::string& tid)` / `ActivateCustomTrainedTraj(tid)` / `UnloadCustomTrainedTraj(tid)` / `GetTrainedTrajStatus(resp)`【fw1.7 #11】`d5d8f7a` 没有 `GetTrainedTrajStatus`（Load/Activate/Unload 有） | ✅（K1/T2） | 只传递机器人上的 ONNX 路径，不上传文件内容 |
| `HandOnChestGreeting(bool)` | ❌ 仅 T2 | |
| `kPushUp=2019` | 没有封装 | 取决于配置 |

### 3.9 查询

| 方法 | 输出 |
|---|---|
| `GetMode(GetModeResponse&)` | `mode_` |
| `GetStatus(GetStatusResponse&)` | `current_mode_`、`current_body_control_`、`current_actions_`（`Action` 枚举：1 HandShake、2 HandWave … 15 RunRecordedTraj） |
| `GetRobotInfo(GetRobotInfoResponse&)` | `name_ nickname_ version_ model_ serial_number_ edition_ region_` |
| `GetFrameTransform(Frame src, Frame dst, Transform&)` | `Frame`：kBody=0、kHead=1、kLeftHand=2、kRightHand=3、kLeftFoot=4、kRightFoot=5；输出为位置加四元数 (x,y,z,w) |
| `GetSensors` / `GetHands` / `GetRobotModel(DeviceInfo&)` | 用 `device_info_parser.hpp` 中的 `ImuInfoListFromDeviceInfo` 等函数解析 |

### 3.10 LocoApiId 数值（生 RPC 与 ROS 2 会用到）

2000 ChangeMode｜2001 Move｜2004 RotateHead｜2005 WaveHand｜2006 RotateHeadWithDirection｜2007 LieDown｜2008 GetUp｜2009 MoveHandEndEffector｜2010 ControlGripper｜2011 GetFrameTransform｜2012 SwitchHandEndEffectorControlMode｜2013 ControlDexterousHand｜2015 Handshake｜2016 Dance｜2017 GetMode｜2018 GetStatus｜2019 PushUp｜2020 PlaySound｜2021 StopSound｜2022 GetRobotInfo｜2023 StopHandEndEffector｜2024 Shoot｜2025 GetUpWithMode｜2026 ZeroTorqueDrag｜2027 RecordTrajectory｜2028 ReplayTrajectory｜2029 WholeBodyDance｜2030 UpperBodyCustomControl｜2031 ResetOdometry（ResetOdometryTo 共用此 ID，body 为 `{"x","y","theta"}`）｜2032–2034 Load/Activate/UnloadCustomTrainedTraj｜2035 EnterWBCGait｜2036 ExitWBCGait｜2037 MoveDualHandEndEffector｜2038 VisualKick｜2039 LionDancePrepare｜2040 LionDanceStart｜2041 LionDanceMove｜2042 SwitchGait｜2043 RotateHeadWithTime｜2044 GetSensors｜2045 GetHands｜2046 GetRobotModel｜2047 GetTrainedTrajStatus｜2050 HandOnChestGreeting。【fw1.7 #12】`d5d8f7a` 的 LocoApiId 到 2046（GetRobotModel）为止，没有 2047–2050；2031 只有 ResetOdometry。

常用 JSON body：ChangeMode 为 `{"mode":2}`；Move 为 `{"vx":0.3,"vy":0,"vyaw":0}`；RotateHead 为 `{"pitch":0.3,"yaw":0}`；GetUp 为 `{"version":1}`；GetUpWithMode 为 `{"mode":4,"version":1}`；VisualKick 为 `{"start":true,"version":1}`；SwitchGait 为 `{"gait_type":2}`。

### 3.11 返回码处理建议

【源】`include/booster/robot/rpc/error.hpp`、`refs/booster_docs/developer-guide__cpp__cpp-api.md`

| 码 | 常量 | 处理 |
|---|---|---|
| -1 | `kRpcStatusCodeInvalid` | 未 Init 或请求没发出去 |
| 0 | `kRpcStatusCodeSuccess` | 成功 |
| 100 | `kRpcStatusCodeTimeout` | 检查网卡 IP、domain 和服务状态；只对幂等操作做有限次重试。MoveController 遇到 MoveCommand 超时会当作丢包继续 |
| 400 | `kRpcStatusCodeBadRequest` | 参数或机型不对，不要原样重试 |
| 409 | `kRpcStatusCodeConflict` | 上一次切换还没完成，等待后先 GetMode 再重试 |
| 429 | `kRpcStatusCodeRequestTooFrequent` | 降低频率，连续控制改用 MoveCommand |
| 500 | `kRpcStatusCodeInternalServerError` | 保留日志 |
| 501 | `kRpcStatusCodeServerRefused` | 该能力在出厂配置中被关闭，或固件不支持 |
| 502 | `kRpcStatusCodeStateTransitionFailed` | 当前状态不允许这个动作，按规定顺序重来 |
| 503 | `kRpcStatusCodeLowBattery`【fw1.7 #2】`d5d8f7a` 未定义 | 电量低，拒绝运动（官方文档表格里漏了这一项，头文件中有） |

### 3.12 `MoveController`（C++ 头文件内实现，Python 有同名版本）

- 构造函数 `MoveController(ip="")`：`ChannelFactory::Init(0, ip)` → `client.Init()` → 订阅 `rt/odometer_state` → 最多等 5 s（超时抛 `std::runtime_error("Odometer not responding.")`）→ `sleep 2 s` → 最多 5 次 `ResetOdometry()`。
- 方法：`MoveToTarget(x, y, vel)`（在里程计系下先转向再平移，容差 0.20 m，**没有总超时**）、`MoveToRelative(dx, dy, vel)`（按里程计系坐标轴，不随机器人朝向旋转）、`TurnAround(angle, vel)`（**正角度会发出负 yaw 指令**，符号与直觉相反）、`Stop()`、`Close()`。
- 内部以 `MoveCommand` 每 20 ms 发一次。**它是阻塞的，不适合放进比赛决策循环**，只能作为参考实现。【源】`include/booster/robot/b1/move_controller.hpp`

---

## 4. 其他 RPC 客户端（简表）

| 客户端 | 主要方法 | 最低固件 | 对足球比赛的价值 |
|---|---|---|---|
| `vision::VisionClient` | `StartVisionService(pos, color, face)`、`StopVisionService()`、`GetDetectionObject(vector<DetectResults>&, focus_ratio=0.33)`；`DetectResults` 包含 `xmin_ ymin_ xmax_ ymax_ position_ tag_ conf_ rgb_mean_` | ≥1.5.0.9 | 通用检测，不是足球专用模型；比赛一般用自己的检测器（robocup_demo 自带 vision 节点） |
| `vision::HandEyeCalibClient`【fw1.7 #13】 | `StartCalibration/StopCalibration/GetStatus/GetResult/ApplyResult` | ≥1.7.1.0 | ✅ 测距不准、踢偏时重做手眼标定，结果保存到 `/opt/booster/vision.yaml`（robocup-demo 文档） |
| `camera::CameraClient` | `GetCameras(DeviceInfo&)` → `CameraListFromDeviceInfo` | – | 查询相机型号和话题 |
| `x5_camera::X5CameraClient` | `ChangeMode(CameraSetMode)`（0 Normal、1 HighRes、2/3 为持久化版本）、`GetStatus` | ≥1.5.0.9 | 仅兼容 K1/T2 的相机版本；可切高分辨率看远处的球 |
| `light::LightControlClient`【fw1.7 #13】 | `SetLEDLightColor(r,g,b)`、`SetLEDLightColors(vector)`（≥1.7.1.0）、`StopLEDLightControl()` | ≥1.5.0.9 | ✅ 用灯色显示角色或状态，方便场边调试 |
| `audio::AudioManager` | `Init`、`CreatePlayer/Recorder/Localizer/CaptureStream`、音量、蓝牙；`AudioLocalizer::GetDoaAngle(int* deg)` | ≥1.6（音频服务） | 可用于哨声识别（原始采集流，默认 16 kHz、3 通道、16 bit）和声源方向，**效果待实机验证** |
| `AiClient` / `LuiClient` | `StartAiChat/Speak/StartFaceTracking`；`StartAsr/StartTts/SendTtsText/SynthesizeSpeech/RecognizeAudioOnce…` | ≥1.3.1.1 起，部分接口 ≥1.8.0.9 | 比赛基本用不到；话题 `rt/ai_subtitle`、`rt/lui_asr_chunk` |
| `B1LocoClient::GetSensors/GetHands/GetRobotModel`【fw1.7 #13】 | `DeviceInfo`（kind_ 与 json_） | 按 ≥1.7.1.0 | 取 URDF 和 IMU 目录 |

【源】`refs/booster_docs/developer-guide__cpp__rpc__{vision,camera,light,audio,ai-lui,device-info}.md`，头文件在 `include/booster/robot/{vision,camera,x5_camera,device/light,audio,ai}/`

---

## 5. 高层可用的 DDS 话题

订阅方式（C++）：`ChannelSubscriber<MSG> sub(topic, handler[, reliable=false]); sub.InitChannel();`，默认 best-effort。Python 中为 `br.B1XxxSubscriber(cb).InitChannel()`。【源】`include/booster/robot/channel/channel_subscriber.hpp`、`refs/booster_docs/developer-guide__cpp__low-level-topics.md`、[wheel] `sdk_pybind_low_level.py`

| DDS 话题（ROS 2 为 `/…`） | C++ 常量 | C++ 类型 | 关键字段 | Python 订阅类 | 最低固件 |
|---|---|---|---|---|---|
| `rt/odometer_state` | `b1::kTopicOdometerState` | `booster_interface::msg::Odometer` | `x() y() theta()`（float，m/rad） | `B1OdometerStateSubscriber` | 1.3.1.1 |
| `rt/odom` | `b1::kTopicRosOdometer` | `nav_msgs::msg::Odometry` | 标准 ROS 格式（需要 ROS 桥） | `B1RosOdometrySubscriber` | 1.7.1.0 |
| `rt/robot_states` | `b1::kTopicRobotStates` | `RobotStatesMsg` | `current_mode() current_body_control() current_actions()` | `B1RobotStatesSubscriber` | 1.3.1.1 |
| `rt/fall_down` | `b1::kTopicFallDown` | `FallDownState` | `fall_down_state()`（0 就绪、1 正在倒、2 已倒、3 正在起身），`is_recovery_available()` | `B1FallDownStateSubscriber` | 1.2.0.2 |
| `rt/battery_state` | 没有常量，使用字符串 | `BatteryState` | `voltage() current() soc() average_voltage()` | `B1BatteryStateSubscriber` | – |
| `rt/button_event` | 使用字符串 | `ButtonEventMsg` | `button()`，`event()`（PRESS_DOWN…LONG_PRESS_END，取值 0–7） | `B1ButtonEventSubscriber` | 1.7.1.0 |
| `rt/remote_controller_state` | 使用字符串 | `RemoteControllerState` | `lx ly rx ry`、`a b x y lb rb lt rt …`、`hat_*` | `B1RemoteControllerStateSubscriber` | 1.2.0.2 |
| `rt/robocup_behavior_status` | `b1::kTopicRobocupBehaviorStatus` | `RobocupBehaviorStatus` | `status()` | `B1RobocupBehaviorStatusSubscriber` | 1.7.1.0 |
| `rt/kick_ball`（发布） | `b1::kTopicKickReference` | `brain::msg::Kick` | 见 §3.5 | `B1VisualKickReferencePublisher` | 1.7.1.0 |
| `rt/prone_body_control_status` | `b1::kTopicProneBodyControlStatus` | `ProneBodyControlStatus` | `posture()` | `B1ProneBodyControlStatusSubscriber` | 1.7.1.0 |
| `rt/trained_traj_status` | `b1::kTopicTrainedTrajStatus`【fw1.7 #11】1.7 没有此话题和订阅类 | `TrainedTrajStatus` | 状态与 id | `B1TrainedTrajStatusSubscriber` | 1.8.0.9 |
| `rt/low_state` | `b1::kTopicLowState` | `LowState` | `imu_state().rpy/gyro/acc`，`motor_state_serial/parallel()[i].q/dq/ddq/tau_est` | `B1LowStateSubscriber` | 1.0 |
| `rt/imu/data`、`rt/joint_states` | `kTopicRosImu`、`kTopicRosJointStates` | `sensor_msgs::msg::Imu` / `JointState` | 标准 ROS 格式 | `B1RosImuSubscriber` / `B1RosJointStateSubscriber` | 1.7.1.0 |
| `rt/tf` | `b1::kTopicTF` | `tf2_msgs::msg::TFMessage` | **当前只能通过 ROS 2 订阅**，没有公开 IDL 头文件 | – | 1.1.0.6 |
| `rt/joint_ctrl`（低层，仅 Custom 模式） | `b1::kTopicJointCtrl` | `LowCmd` | 见低层文档 | `B1LowCmdPublisher` | 1.0 |



K1 的关节顺序使用 `JointIndexK1`，共 22 个关节（`kJointCntK1`），**没有腰部关节**。T1 的 `JointIndex` 有 23 个关节，不要混用。【源】`include/booster/robot/b1/b1_api_const.hpp`

---

## 6. ROS 2 接口

### 6.1 包与定义（`refs/booster_robotics_sdk_ros2/booster_ros2_interface`，包名 `booster_interface`）

| 类别 | 名称 | 要点 |
|---|---|---|
| RPC | `srv/RpcService` | 请求 `BoosterApiReqMsg msg{int64 api_id, string body}`，响应 `BoosterApiRespMsg msg{int64 status, string body}` |
| RPC | `srv/AgentService` | `string body → string body` |
| 状态 | `LowState{ImuState imu_state; MotorState[] motor_state_parallel; motor_state_serial}`、`ImuState{float32[3] rpy,gyro,acc}`、`MotorState{mode,q,dq,ddq,tau_est,temperature,lost,reserve[2]}`、`Odometer{x,y,theta}`、`FallDownState`、`RobotStatesMsg`、`ProneBodyControlStatus`、`RobotReplayTrajID`、`RemoteControllerState`、`ButtonEventMsg`、`Subtitle` | 与 SDK IDL 同构 |
| 控制 | `LowCmd{int8 cmd_type(PARALLEL=0/SERIAL=1); MotorCmd[] motor_cmd}`、`MotorCmd{mode,q,dq,tau,kp,kd,weight}`、`HandCommand/HandDdsMsg/HandParam` | |
| 其他 | `RawBytesMsg{char[] msg}`、`HandActionStatus` | |

- 辅助头文件 `booster_interface/message_utils.hpp`：`CreateMsg<LocoApiId::kX, XParameter>(args...)`，以及旧接口 `CreateChangeModeMsg/CreateMoveMsg/CreateRotateHeadMsg/CreateWaveHandMsg/CreateGetUpMsg…`。
- **定义上的坑**：`ButtonEventMsg.msg` 里的常量写成了 `PRESS_DOWN=0, PRESS_UP=1, SINGLE_CLICK=0, DOUBLE_CLICK=1…`（重复的 0/1），与 C++ IDL 中枚举的 0–7 不一致，而且字段类型是 `int8`，C++ 是 `uint32`。判断事件时应以 C++ 枚举为准，**实际线上取值待实机验证**。
- **示例的坑**：`booster_ros2_example/rpc_client/src/client.py` 发 2009 时，JSON 键写成 `"position_"`/`"orientation_"`，而 `Posture::ToJson()` 生成的键是 `"position"`/`"orientation"`（`include/booster/robot/common/entities.hpp`）。手写 JSON 时应以 `ToJson` 为准。

### 6.2 服务与话题名

| 名称 | 类型 | 用途 | 来源 |
|---|---|---|---|
| `booster_rpc_service` | `booster_interface/srv/RpcService` | 调用 Loco RPC，返回 status 和 body | ros2 示例、booster_deploy |
| `booster_rtc_service` | 同上 | AI 对话 | `rtc_client/src/client.cpp` |
| `LocoApiTopic[/<robot>]Req` | `booster_msgs/msg/RpcReqMsg{uuid,header,body}` | fire-and-forget RPC | robocup_demo |
| `/low_state`、`/odometer_state`、`/remote_controller_state`、`/joint_ctrl` 等 | `booster_interface/msg/*` | 与 `rt/*` 同一话题 | robocup_demo、booster_deploy |
| `/kick_ball` | `brain/msg/Kick` | 视觉踢球参考 | robocup_demo |
| `fall_down_recovery_state`、`/head_pose` | `RawBytesMsg`、`geometry_msgs/Pose` | 固件提供，SDK 没有文档（**待实机验证**） | robocup_demo `brain.cpp:191-194` |

### 6.3 与 robocup_demo 的协同

- robocup_demo 在 `src/interface/` 下自带了一份 `booster_ros2_interface`（比 ros2 SDK 多 `RawBytesStamped`，少 `RobotStatesMsg/ProneBodyControlStatus/RobotReplayTrajID/Subtitle/HandActionStatus`）和 `booster_msgs`（RpcReqMsg/RpcRespMsg/BinaryData）。**如果同一工作区还 source 了机器人上的 `/opt/booster/BoosterRos2Interface`，会出现包名重复的覆盖问题，要确认 overlay 顺序。**
- `RobotClient`（`src/brain/src/robot_client.cpp`）封装了：`moveHead` → 2004；`setVelocity` → 2001（带限幅和最小速度）；`standUp` → 2008 `{}`；`RLVisionKick` → 2038 `{"start":bool}`；`robocupWalk` → 2000 kWalking；`enterDamping` → 2000 kDamping；`waveHand` → 2005。**全部是 fire-and-forget，没有返回码**，函数恒定返回 0。
- 要在 robocup_demo 里加 SDK 功能（比如 SwitchGait 或 GetUpWithMode(kSoccer, kV2)），最直接的做法是照同样的模式 `call(CreateMsg<LocoApiId::kSwitchGait, SwitchGaitParameter>(GaitType::kX))`；需要返回码时改用 `booster_rpc_service` 客户端。
- 多机器人：`config.yaml` 中的 `robot.robot_name` 会加到 `LocoApiTopic/<name>Req` 和各订阅话题的后缀上（仿真多机场景使用）。
- 与官方 5v5 Demo 1.6 文档的差异：文档里有 `RLVisionKick.visual_kick_version: kV2` 和 LT+A 进入 kSoccer，本地仓库代码中**没有** `visual_kick_version` 或 kSoccer 相关代码。说明本地 robocup_demo 与文档描述的 K1_5v5_Demo_1.6 不是同一版本。

---

## 7. 最小可运行示例

> ⚠️ 首次运行要吊装或有人扶着，场地要空旷。运行前先在 App 或遥控器上确认机器人处于 PREP 或 DAMP 状态。

### 7.1 C++

改写自 `refs/booster_robotics_sdk/example/high_level/b1_loco_example_client.cpp`、`refs/booster_docs/developer-guide__cpp__quick-start.md`，流式速度的做法参照 `include/booster/robot/b1/move_controller.hpp`。

```cpp
#include <booster/robot/b1/b1_loco_client.hpp>
#include <booster/robot/channel/channel_factory.hpp>
#include <booster/robot/rpc/error.hpp>
#include <chrono>
#include <iostream>
#include <thread>
using namespace booster::robot;
using namespace std::chrono_literals;

static bool WaitMode(b1::B1LocoClient& c, RobotMode want, int tries = 30) {
  for (int i = 0; i < tries; ++i) {                 // ChangeMode 只保证 RPC 被接受
    b1::GetModeResponse r;
    if (c.GetMode(r) == kRpcStatusCodeSuccess && r.mode_ == want) return true;
    std::this_thread::sleep_for(200ms);
  }
  return false;
}

int main(int argc, char** argv) {
  const std::string net = argc > 1 ? argv[1] : "127.0.0.1";   // 在本体上运行用 127.0.0.1
  ChannelFactory::Instance()->Init(0, net);                    // 1) 先初始化 DDS
  b1::B1LocoClient client;
  client.Init();                                               // 2) 绑定 rt/LocoApiTopic
  if (!client.WaitForService(5000)) { std::cerr << "loco service unavailable\n"; return 1; }

  int32_t ret = client.ChangeMode(RobotMode::kPrepare);        // 3) DAMP -> PREP
  if (ret != kRpcStatusCodeSuccess || !WaitMode(client, RobotMode::kPrepare)) {
    std::cerr << "prepare failed: " << ret << "\n"; return 1; }
  std::this_thread::sleep_for(2s);                             // 等站稳（时长待实机验证）

  ret = client.ChangeMode(RobotMode::kWalking);                // 4) PREP -> WALK
  if (ret != kRpcStatusCodeSuccess || !WaitMode(client, RobotMode::kWalking)) {
    std::cerr << "walking failed: " << ret << "\n"; return 1; }

  for (int i = 0; i < 100; ++i) {                              // 5) 以 50 Hz 流式发送 0.2 m/s，持续 2 s
    ret = client.MoveCommand(0.2F, 0.0F, 0.0F);
    if (ret != kRpcStatusCodeSuccess && ret != kRpcStatusCodeTimeout)
      std::cerr << "MoveCommand err " << ret << "\n";
    std::this_thread::sleep_for(20ms);
  }
  ret = client.Move(0.0F, 0.0F, 0.0F);                         // 6) 停止：用阻塞版确认送达
  std::cout << "stop ret=" << ret << "\n";
  // 需要放倒时：先让机器人有支撑，再 client.ChangeMode(RobotMode::kPrepare / kDamping)
  return 0;
}
```
编译：按 §2.1 安装后，`g++ -std=c++17 main.cpp -lbooster_robotics_sdk -lpthread -ldl -lrt`，或使用 §2.1 的 CMake。

### 7.2 Python（`booster_robotics_sdk_python`）

改写自 [wheel] `python_example/sdk_pybind_b1_example.py`（参考 `booster_robotics_sdk_python/move_controller.py`）和 `refs/booster_gym/deploy/deploy.py`。

```python
import sys, time
import booster_robotics_sdk_python as b1

net = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
b1.ChannelFactory.Instance().Init(0, net)          # 1) DDS
client = b1.B1LocoClient()
client.Init()                                      # 多机器人时用 client.InitWithName("robot0")

def wait_mode(want, tries=30):
    for _ in range(tries):
        try:
            if client.GetMode().mode == want:      # Python 版直接返回对象
                return True
        except RuntimeError:
            pass
        time.sleep(0.2)
    return False

try:
    client.ChangeMode(b1.RobotMode.kPrepare)       # 非 0 返回码会抛 RuntimeError
    assert wait_mode(b1.RobotMode.kPrepare)
    time.sleep(2.0)
    client.ChangeMode(b1.RobotMode.kWalking)
    assert wait_mode(b1.RobotMode.kWalking)
    t_end = time.time() + 2.0
    while time.time() < t_end:                     # 以 50 Hz 流式发送速度
        client.MoveCommand(0.2, 0.0, 0.0)
        time.sleep(0.02)
finally:
    try:
        client.Move(0.0, 0.0, 0.0)                 # 停止
    except RuntimeError as e:
        print("stop failed:", e)
```

等价的 `boosteros` 写法（【源】`…motion-control-apis__set-mode.md`、`…__set-velocity.md`，只能在本体上运行）：
```python
import time
from boosteros.robots.booster import BoosterRobot
robot = BoosterRobot(timeout=30)          # 刚开机时服务起得慢，FAQ 建议调大 timeout
robot.set_mode("prepare"); robot.set_mode("walk")   # set_mode 会阻塞到切换完成
try:
    robot.set_velocity(0.2, 0.0, 0.0); time.sleep(2.0)
finally:
    robot.set_velocity(0.0, 0.0, 0.0)
```

---

## 8. 常见坑

| # | 坑 | 说明与对策 | 证据 |
|---|---|---|---|
| 1 | 网卡 IP 传错 | `Init(0, ip)` 的第二个参数是**本机**网卡地址。在本体上用 `127.0.0.1`；在开发机上用开发机的 IP（有线直连时开发机 192.168.10.10，机器人 192.168.10.102）。传错时 `WaitForService` 会超时，接口返回 100 | `channel_factory.hpp`、`connect-robot.md`、`robocup_demo/configs/fastdds.xml` |
| 2 | 多机器人串台 | 所有机器人默认都在 domain 0，话题名也一样（`rt/LocoApiTopic`）。同一个 Wi-Fi 下从开发机发出的指令可能被**所有**机器人收到。对策：比赛程序跑在本体上，并用 127.0.0.1 或 UDP 白名单限制；或者用 `Init(robot_name)` 做话题隔离（需要服务端配合）。boosteros 可以传 `domain_id`，但机器人服务端的 domain 怎么改没有文档，**待实机验证** | `architecture.md`、boosteros `initialization.md` |
| 3 | 模式顺序 | DAMP 不能直接到 WALK；CUSTOM 只能从 PREP/DAMP 进入、只能退到 PREP/DAMP；从 WALK 回 DAMP 前必须有支撑。违反顺序通常返回 502 或 409 | `modes.md`、`error.hpp` |
| 4 | 把"已接受"当成"已完成" | `ChangeMode`、`LionDancePrepare`、`SendApiRequestFireAndForget` 返回 0 只代表 RPC 被接受或提交。要轮询 `GetMode/GetStatus` 或订阅 `rt/robot_states` | `b1_loco_client.hpp`、booster_deploy |
| 5 | 在循环里阻塞 | `Move()` 等 RPC 最多等 1 s，`WaitForService` 默认 5 s，`MoveController` 的方法没有总超时，`MoveController` 构造本身会 sleep 2 s 以上。决策循环里应使用 `MoveCommand` | `rpc_client.hpp`、`move_controller.hpp` |
| 6 | 调用频率 | 服务端有 429（请求过频），但**限值没有文档**。官方 MoveController 用约 50 Hz 的 MoveCommand。查询类和模式切换不要高频调用 | `error.hpp`、`move_controller.hpp` |
| 7 | 速度死区 | 太小的速度机器人不会动。robocup_demo 把速度抬到 0.3/0.3/0.25 的最小值；boosteros FAQ 建议从 0.1 起逐步加大 | robocup_demo `config.yaml`、boosteros `faq.md` |
| 8 | 头部超限 | K1 pitch 范围 −19°～+49°。示例中 `RotateHead(1.0, 0)` 已经超限，超限不报错但会停止响应 | `specifications.md`、boosteros `set-head-angle.md` |
| 9 | K1 调用 LieDown | 可能返回成功却执行零位轨迹，有危险。**K1 禁止调用** | `b1_loco_client.hpp` |
| 10 | 用 T1 的关节表 | K1 是 22 个关节，没有腰部（`JointIndexK1`）。按 T1 的 23 关节表写 `rt/joint_ctrl` 会驱动错误的执行器 | `b1_api_const.hpp` |
| 11 | 版本不配套 | 旧 Demo 文档要求"固件 1.6 配 SDK 1.3.6"，不匹配时会编译失败或运行时崩溃。当前仓库 v1.6.3 面向固件 1.8.0。PyPI 上 `booster_robotics_sdk_python` 同为 1.6.3。新接口要看 §3.1 的最低固件表，低版本固件调用会返回 400 或 501。比赛前统一用 `booster-cli version` 核对【fw1.7 #4】 | `robocup-demo.md`、`cpp__changelog.md`、git log |
| 12 | 机器人刚开机 | 服务要 30–60 秒才会起来。boosteros 会抛 `LocoClientInitError`；C++ 的 `WaitForService` 返回 false | boosteros `faq.md` |
| 13 | 能力被出厂配置关闭 | 返回 501 表示当前配置禁用了该能力（例如 T1_7DofArm 禁用挥手、起身），与机型名无关。**用返回码探测能力，不要硬编码机型** | `b1_loco_api.hpp` |
| 14 | Python 异常语义 | pybind 接口遇到非 0 返回码会抛 `RuntimeError`，不像 C++ 那样返回 int。控制循环里要 try/except，否则一次超时就会让主循环退出 | [wheel] `sdk_pybind_b1_example.py`、`move_controller.py` |
| 15 | boosteros 实例重复 | 同一台机器人只能建一个 `BoosterRobot`，多个实例会导致多个控制发布者互相冲突 | boosteros `initialization.md` |
| 16 | 速度通道互斥 | 视觉踢球期间底盘由踢球控制器接管。champion 示例把 kick 和 set_velocity 设计成互斥；robocup_demo 退出踢球时会先减速再切回 kWalking | `booster_champion_example/src/soccer_framework/robot.py`、robocup_demo `brain_tree.cpp` |
| 17 | 在 CUSTOM 模式下想用高层 API | 在 Custom 模式里 `rt/joint_ctrl` 优先。高层运动接口需要先回到 PREP 再切 WALK（切换规则见坑 3） | `modes.md`、`low-level-topics.md` |
| 18 | ROS 2 定义与 C++ 不一致 | `ButtonEventMsg` 常量重复；ROS 2 Python 示例里 Posture 的 JSON 键带下划线 | §6.1 |

---

## 9. 存疑点（待实机验证）

1. `ChannelFactory::Init` 第二个参数在开发机跨机运行时到底应填本机 IP 还是机器人 IP（本文按"本机网卡"理解）。
2. `ChangeMode(kSoccer)` 的合法前置模式；`Shoot()` 在 K1 上是否可用；比赛中 kWalking 和 kSoccer 该如何选（robocup_demo 代码使用 kWalking，官方 1.6 文档使用 kSoccer）。
3. `VisualKick` 与 `rt/kick_ball` 的发布频率要求、`power` 的物理含义（boosteros 取值范围 1–10；robocup_demo 用 1.5 和 6.0）；Python 版 Kick 消息的类名。
4. `Move`/`MoveCommand` 的实际上限、死区，以及 429 的触发阈值。
5. 官方 quick-start 在 PREP 与 WALK 之间调用 `GetUp()` 是否必要。
6. robocup_demo 使用的 `fall_down_recovery_state` 与 `current_planner_index` 魔数的含义，以及 `/head_pose` 的来源。
7. 机器人服务端 DDS domain 如何修改，用于多机隔离。
