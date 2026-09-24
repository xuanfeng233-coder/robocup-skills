# Booster RoboCup Demo 源码深度解析（K1 视角）

> ⚠ **本队现用主办方发放的 `K1_5v5_demo_1.7`（本地 `refs/K1_5v5_demo_1.7`）+ 固件 ≥ 1.7 + HSL GameController 7.0.0-rc.3（v20）**。本文分析的是公开仓库 main，它是理解整体架构的底稿；Demo 1.7 在 GC 协议（同时收 v12/v20）、队内通信（改成广播）、视觉配置、起身和踢球版本、行为树等方面都有改动。**改比赛程序时以 `refs/K1_5v5_demo_1.7` 为准**，差异清单见 `fw1.7-demo-v1.7.md` §3；部署和上场流程见 `event-sop.md`。文中【fw1.7 #N】标注对应 `fw1.7-demo-v1.7.md` §4 的勘误。

> 分析对象：`refs/robocup_demo`（GitHub `BoosterRobotics/robocup_demo` main 分支浅克隆，无 git 历史，快照日期未知）。
> 下文路径均相对 `refs/robocup_demo/`，行号为本快照的近似位置。
> 结论标注「待实机验证」表示仅凭代码或文档无法确认。
> 官方文档 `booster_docs/developer-guide__open-source__robocup-demo.md` 描述的是 **K1_5v5_Demo v1.6 release 包**，它与本仓库 main 分支**有若干不一致**（见 §0.2），请以你实际部署的代码为准。

---

## 0. 速览

### 0.1 一句话架构

三个 ROS 2 Humble 节点：
- `vision_node`：YOLOv8 检测与分割，结果投影到地面，得到机器人系坐标。
- `game_controller_node`：把 GameController 的 UDP 包转成 ROS 话题。
- `brain_node`：用 BehaviorTree.CPP v4 做决策，通过 ROS 话题 `LocoApiTopicReq` 向固件发送 Loco RPC 请求（走路、转头、起身、切模式、VisualKick）；另外把 `/kick_ball` 发给固件内置的 RL 视觉踢球控制器。

全程不使用关节级（`LowCmd`）控制。

### 0.2 与官方 V1.6 文档的差异（重要）

| 项 | 本仓库 main | 官方 V1.6 文档 |
|---|---|---|
| 视觉配置来源 | `install/vision/share/vision/config/vision.yaml` + `vision_local.yaml`（`src/vision/launch/launch.py:19-21`）。运行时**没有任何代码读取** `/opt/booster/vision.yaml`，只有标定程序会写它（`src/vision/src/calibration/calibration_node.cpp:369-396`） | 称 `/opt/booster/vision.yaml` 优先 |
| 相机话题 | `/StereoNetNode/rectified_image`、`/StereoNetNode/stereonet_depth` 等 d-robotics 话题（`src/vision/config/vision.yaml:6-8`、`src/brain/config/config.yaml:84-86`） | `/boostercamera/head/rgb`、`/boostercamera/head/depth` |
| VisualKick 版本 | 不传 version，body 只有 `{"start":true}`（`src/brain/src/robot_client.cpp:50-59`），SDK 默认 kV1 | `RLVisionKick.visual_kick_version: kV2` |
| GameController | HL 结构体 version 12（`src/game_controller/include/RoboCupGameControlData.h:10`） | GameController 1.0.1，发的正是 HL v12，与本仓库 main 的 v12 解析代码兼容（按上游 GC 2025.1.1 逐字节核实）【已更正，#31】。README 指向的 2026 适配分支 `sandbox/support_2026_game_controller` 只收 v19/v20，收不到 GC 1.0.1 的包 |【fw1.7 #24】本赛事用 HSL GC 7.0.0-rc.3（v20）：main 只收 v12，收不到；Demo 1.7 按包长同时收 v12/v20（`fw1.7-demo-v1.7.md` §3.2）
| 队内通信 | UDP 单播（README NOTICE：不符合最新规则）【fw1.7 #27】Demo 1.7 已改为广播到 `10000+team_id`，但每 100 ms 一条，会耗尽 GC 额度（`issues.md` T10） | — |

---

## 1. 总体架构与数据流

### 1.1 ASCII 架构图

```
 ┌──────────────────────── K1 固件 / Booster SDK（DDS，ROS2 话题 X ≙ DDS "rt/X"） ────────────────────────┐
 │ 头部双目深度相机驱动(StereoNetNode…)   运动控制(Loco RPC 服务)   状态发布   RL VisualKick 控制器          │
 └──┬──────────────┬─────────────┬──────────────┬───────────────┬───────────────▲──────────────▲──────────┘
    │color/depth/  │ /head_pose  │/odometer_state│ /low_state   │fall_down_     │LocoApiTopicReq│ /kick_ball
    │camera_info   │ (Pose)      │ (Odometer)    │ (LowState)   │recovery_state │(RpcReqMsg)    │(brain/Kick)
    ▼              ▼             │               │              │(RawBytesMsg)  │               │
 ┌─────────────── vision_node ─────────┐         │              │               │               │
 │ det: YOLOv8(9类)  seg: YOLOv8-seg   │         │              │               │               │
 │ p_eye2base=head2base·comp·eye2head  │         │              │               │               │
 │ 射线∩地面 z=0 → 机器人系 (x,y)       │         ▼              ▼               ▼               │
 └───┬────────────────────┬────────────┘   ┌──────────────────── brain_node ──────────────────────┴───────┐
     │/booster_soccer/     │/booster_soccer/ │ 回调线程(executor)：更新 BrainData / 黑板                     │
     │detection            │line_segments    │ tick 线程 ~100Hz：log→publish→updateMemory→handleSpecialStates │
     └────────────────────►└────────────────►│   →handleCooperation→BT tickOnce(game.xml)                   │
                                             │ RobotClient::call() → LocoApiTopicReq（发出即不管，不等回应） │
      depth image + depth camera_info ──────►│ 深度点云→占据栅格→避障                                        │
                                             └──▲────────────▲─────────────────┬────────────────┬──────────┘
   GameController PC ─UDP bcast :3838─► game_controller_node ─/booster_soccer/game_controller─┘ │
          ▲                                                   (GameControlData)                 │
          └────────── UDP 单播 :3939 "RGrt" ALIVE 1Hz（由 brain 发出） ◄──────────────────────────┘
   队友 brain ◄── UDP 广播 :20000+team_id（discovery 1Hz）/ UDP 单播 :30000+team_id（状态 10Hz）──► brain
   手柄 /remote_controller_state、Agent /booster_agent/soccer_game_control ──► brain（独立 context 线程）
```

### 1.2 话题 / 接口表

频率一栏：「按帧」表示随相机帧率触发。代码没有写死相机帧率；`save_every_n_frame_ = 30/save_fps`（`vision_node.cpp:113`）隐含按 30fps 假设，待实机验证。

| 话题 / 通道 | 类型 | 发布 → 订阅 | 频率 | 源码 |
|---|---|---|---|---|
| `camera.color_topic`（默认 `/StereoNetNode/rectified_image`） | `sensor_msgs/Image`；话题名含 `compressed` 时用 CompressedImage | 相机驱动 → vision（det、seg 各订阅一次） | 相机帧率 | `vision_node.cpp:263-291` |
| `camera.depth_topic` | Image/CompressedImage | 驱动 → vision（仅 `use_depth: true` 时订阅，默认 false） | 相机帧率 | `vision_node.cpp:273-280` |
| `camera.intrin_topic` | `CameraInfo` | 驱动 → vision（收 5 条后取消订阅） | — | `vision_node.cpp:241-243, 876-882` |
| `/head_pose` | `geometry_msgs/Pose`（head→base） | 固件 → vision、brain | 固件决定，待验证 | `vision_node.cpp:299`，`brain.cpp:193` |
| `/booster_soccer/detection[/robot_name]` | `vision_interface/Detections` | vision → brain | 按帧 | `vision_node.cpp:282`，`brain.cpp:189` |
| `/booster_soccer/line_segments[/robot_name]` | `vision_interface/LineSegments` | vision → brain | 按帧 | `vision_node.cpp:292`，`brain.cpp:190` |
| `/booster_soccer/t_head2base` | `TransformStamped` | vision 发；offline_mode 下 vision 自己订阅 | 随 `/head_pose` | `vision_node.cpp:297-301` |
| `/booster_soccer/cal_param` | `vision_interface/CalParam` | 外部 → vision（运行时 pitch/yaw/z 补偿） | 事件 | `vision_node.cpp:300, 762-768` |
| `/booster_soccer/ball` | `vision_interface/Ball` | 只创建，**从不发布** | — | `vision_node.cpp:294` |
| `/odometer_state` | `booster_interface/Odometer`(x,y,theta) | 固件 → brain | 固件决定 | `brain.cpp:191, 1321-1335` |
| `/low_state` | `booster_interface/LowState` | 固件 → brain（`motor_state_serial[0]`=头 yaw，`[1]`=头 pitch） | 固件决定 | `brain.cpp:1337-1342` |
| `fall_down_recovery_state`（相对名） | `booster_interface/RawBytesMsg` → `{state, is_recovery_available, current_planner_index}` | 固件 → brain | — | `brain.cpp:194, 1389-1415`；`types.h:181-185` |
| `vision.image_camera_info_topic` | `CameraInfo` | → brain（只用来取图像宽高） | — | `brain.cpp:196-197, 1344-1348` |
| `vision.depth_image_topic` / `depth_camera_info_topic` | Image(16UC1/32FC1) 或 Compressed；CameraInfo | 驱动 → brain（做避障栅格） | 深度帧率 | `brain.cpp:199-219, 2027-2164` |
| `/remote_controller_state` | `booster_interface/RemoteControllerState` | 固件 → brain（`brain_node_ext`） | — | `main.cpp:42` |
| `/booster_soccer/game_controller` | `game_controller_interface/GameControlData` | gc 节点 → brain | 每收到一个 UDP 包发一次（GC 广播频率，常见约 2Hz，待验证） | `game_controller_node.cpp:29, 111`；`main.cpp:43` |
| `/booster_agent/soccer_game_control` | `std_msgs/String`（locate/ready/play/stop） | App / Booster Studio → brain | 事件 | `main.cpp:44`；`brain.cpp:2382-2431` |
| `LocoApiTopicReq[/robot_name]` | `booster_msgs/RpcReqMsg{uuid, header:{"api_id":N}, body:json}` | brain → 固件 Loco 服务 | 每次调用 `setVelocity`/`moveHead`…都发，一个 tick 内可发多条 | `robot_client.cpp:10-28` |
| `/kick_ball` | `brain/msg/Kick` | brain → 固件视觉踢球控制器（SDK `kTopicKickReference="rt/kick_ball"`，IDL 命名空间正是 `brain::msg`） | 每个 tick 都发（只要 `ballDetected`） | `brain.cpp:209, 989-1023`；SDK `include/booster/idl/b1/Kick.h:85` |
| `/booster_soccer/robot_pose` / `ball_position` / `teammates_poses` | Pose2D / Point / Float64MultiArray | brain → 可视化 | 每 tick | `brain.cpp:2609-2642` |
| `/booster_soccer/field_dimensions` | Float64MultiArray（transient_local） | brain → 可视化 | 启动时一次 | `brain.cpp:2585-2607` |
| `/booster_soccer/visualization_markers` / `_point_cloud` / `_obstacle_grid` / `player_decision` | MarkerArray / PointCloud2 / OccupancyGrid / String | brain → 可视化 | 每 tick、每个深度帧 | `visualization_publisher.cpp:14-21` |
| TF `map→odom` | 实际填的是 robotPoseToField（命名上有歧义） | brain | 每 tick | `brain.cpp:2558-2583` |
| `/booster_soccer/log/scalars/<entity>` | `diagnostic_msgs/KeyValue` | brain（性能、队友状态标量） | 每 tick | `brain_log.cpp:52-86` |
| UDP :3838（收） | `HlRoboCupGameControlData` | GC → gc 节点 | GC 决定 | `game_controller_node.cpp:46-115` |
| UDP :3939（发，单播到 `game_control_ip`） | `HlRoboCupGameControlReturnData`（"RGrt"，v2，message=2 ALIVE） | brain → GC | 1Hz | `brain_communication.cpp:76-102, 237-252` |
| UDP 广播 :20000+team_id | `TeamDiscoveryMsg` | brain ↔ 队友 | 1Hz | `brain_communication.cpp:254-274` |
| UDP 单播 :30000+team_id | `TeamCommunicationMsg`（原始 struct，memcpy 收发） | brain ↔ 队友 | 10Hz（100ms） | `brain_communication.cpp:365-418, 475-568` |

### 1.3 brain 如何让机器人动起来（SDK 接口点）

所有高层动作都走 `RobotClient::call()`（`src/brain/src/robot_client.cpp:16-28`）：把 `BoosterApiReqMsg{api_id, body}` 包成 `booster_msgs/RpcReqMsg`，发布到 ROS 话题 `LocoApiTopicReq`，对应 DDS 的 `rt/LocoApiTopicReq`，也就是 SDK 的 `rt/LocoApiTopic` RPC 请求通道（`booster_robotics_sdk/include/booster/robot/b1/b1_loco_api.hpp:80`）。**只发不收，没有错误反馈**。

| RobotClient 方法 | LocoApiId（SDK `b1_loco_api.hpp:90-137`） | 用途 | 源码 |
|---|---|---|---|
| `setVelocity(vx,vy,vtheta)` | `kMove=2001`（`CreateMoveMsg`） | 走路。先把小速度抬到 `min_v*`，再裁剪到 `v*_limit` | `robot_client.cpp:77-122` |
| `crabWalk(angle,speed)` | 最终调用 setVelocity | 「走着踢」：朝球方向横移直冲（`vx*=vx_factor`，`angle+=yaw_offset`），vtheta=0 | `robot_client.cpp:124-141` |
| `moveHead(pitch,yaw)` | `kRotateHead=2004` | 转头。yaw 裁剪到 [-1.1, 1.1]，**pitch = max(pitch, 0.45)**（最多只能抬到 0.45 rad） | `robot_client.cpp:30-38` |
| `standUp()` | `kGetUp=2008` | 摔倒自起 | `robot_client.cpp:40-48` |
| `RLVisionKick(start)` | `kVisualKick=2038`，body `{"start":true}` | 进入固件 RL 视觉踢球 | `robot_client.cpp:50-59` |
| `robocupWalk()` | `kChangeMode=2000`，`RobotMode::kWalking` | 退出视觉踢球，回到行走 | `robot_client.cpp:61-65` |
| `waveHand(bool)` | `kWaveHand=2005` | 挥手（行为树没有用到） | `robot_client.cpp:72-75` |
| `enterDamping()` | ChangeMode kDamping | 未使用 | `robot_client.cpp:67-70` |

- **踢球有两条路径**：
  - ① 行走踢（`Kick` 节点）：用 `crabWalk` 直接撞球，没有独立的踢腿动作。
  - ② RL 视觉踢（`RLVisionKick` 节点，仅 K1，固件 ≥1.5.2，见 README）：调用 `kVisualKick` 后，由固件控制器根据 `/kick_ball` 中的球位（机器人系）、期望方向 `dir`、`power` 自主走位并踢球。
- **转头**：`CamTrackBall`、`CamFindBall`、`CamScanField`、`CamFastScan`、`MoveHead` 节点都调用 `moveHead`。
- **本仓库不使用 IMU**。头部姿态完全来自固件的 `/head_pose`（head→base，是否包含躯干倾角待实机验证）；头关节角来自 `/low_state`。

---

## 2. vision 包

### 2.1 模型与推理

- **网络**：YOLOv8。检测和分割各一个模型（`detector.h` / `segmentor.h`）。
  - CUDA 构建走 TensorRT，只支持 TRT **8.6** 或 **10.3** 两个分支（`include/booster_vision/model/trt/impl.h:10, 91`；文件名 `_10.3.engine` 对应 JetPack 6.2）。
  - `-DNO_CUDA=ON` 时改用 ONNX Runtime，按 OpenVINO > CUDA > CPU 的顺序选择 EP（`src/model/onnx/detection_impl.cpp:82-119`）。
- **默认模型**（`src/vision/config/vision.yaml:55-75`）：
  - 检测 `./src/vision/model/best_digua_second_10.3.engine`，conf 0.2，nms 0.4。
  - 分割 `best_seg_orin_10.3.engine`，conf 0.3。
  - 仿真用 `sim_data_det_0126.onnx` / `sim_data_seg_0126.onnx`。
  - 其它候选：`best_digua_10.3.engine`、`best_digua_1223_10.3.engine`、`k1_realsense_10.3.engine`、`best_seg_orin.engine`（推测为 TRT8.6 版本）。
  - **所有模型文件都是 Git LFS 指针（133 字节）**，需要先 `git lfs pull`（`.gitattributes`）。
  - 相对模型路径会拼接到 vision 包的 share 目录（`vision_node.cpp:77-97`）；这些文件由 `install(DIRECTORY model …)` 安装。
- **检测类别**（9 类，顺序固定）：`Ball, Goalpost, Person, LCross, TCross, XCross, PenaltyPoint, Opponent, BRMarker`。
  - 硬编码在 `src/model/detector.cc:14-15` 的 `kClassLabels`，同时写在 yaml 的 `classnames` 里，两处必须一致。
  - TRT8.6 另有 `kNumClass=9`（`trt/config.h`）。
  - 分割类别：`CircleLine, Line`（`segmentor.cc`）。
- **预处理**（TRT10）：BGR→RGB，右下角补灰 (114) 成正方形，resize 到 640×640，/255（`src/model/trt/impl.cpp:463-497`）。**输入必须是 640 方形**（断言在 `impl.cpp:473-474`）。输出按 ultralytics 的 `[1, 4+nc, 8400]` 解析（`impl.cpp:655-700`）。
- **NMS**：TRT10 路径写死 `NMSBoxes(…, 0.25, 0.4)`（`impl.cpp:705, 908`），会忽略 yaml 的 `nms_threshold`，并且把最低置信度抬到 0.25。ONNX 路径使用配置值（`detection_impl.cpp:260`）。
- **后处理**：先按类别置信度过滤（`post_process.confidence_thresholds`，`vision_node.cpp:347-359`）。可选 `single_ball_assumption`（默认 false），只保留置信度最高的球。之后 `confidence *= 100` 发布（`vision_node.cpp:413`），所以 brain 的阈值 50 对应 0.5。
- **颜色分类**：只有 yaml 中存在 `robot_color_classifier` 时才启用（`vision_node.cpp:200-203`），默认 yaml 没有这一项，即不启用。
- **分割出线段**：`FitFieldLineSegments`（`pose_estimator.cpp:495-555`）的步骤：
  1. 把每个轮廓的像素逐点投影到地面。
  2. 3D RANSAC 拟合直线（阈值 0.07m，100 次迭代）。
  3. 取两端点。
  4. 丢弃面积 < `line_segment_area_threshold`(75) 或内点率 < 25% 的轮廓（`vision_node.cpp:578-583`）。
  5. 以 `[x0,y0,x1,y1,…]` 的形式发布（机器人系，米）。
- **执行模型**：`MultiThreadedExecutor(4)`，det 和 seg 在不同回调组并行处理同一路彩色图（`main.cpp:24`，`vision_node.cpp:246-291`）。
- **性能**：仓库里没有基准数据。`vision.log` 会打印 `color callback takes: X ms` 和 `[Detections Pub Interval]`（`vision_node.cpp:449-461, 521-523`）。brain 会发布 `brain_tick_duration_ms`、`detection_lag`、`fieldline_detection_lag`、`gamecontrol_lag`（`brain.cpp:2235-2265`；`main.cpp:29`）。**帧率和延迟待实机验证。**

### 2.2 相机输入

- 默认相机是 d-robotics StereoNet 的彩色（rectified）图、深度图和 camera_info。yaml 里注释了 sim、orbbec、realsense、zed 的备选话题（`vision.yaml:1-20`）。
- 分辨率不写死。内参先从 yaml 读取（`fx=fy=206.45, cx=224.96, cy=242.72`，`vision.yaml:21-28`），收到 `intrin_topic` 的 CameraInfo 后动态覆盖，并重建所有 PoseEstimator（`vision_node.cpp:770-873`）。
  - 由 yaml 主点可以推断图像大约是 450×485 量级，**待实机验证**。
  - 这里有线程竞争：重建 `pose_estimator_map_` 的同时，检测回调可能正在读取它。
- 畸变模型：`plumb_bob` 按 kInverseBrownConrady 处理，其它非零畸变按 kBrownConrady 处理，全零则视为 kNone（`vision_node.cpp:786-807`；`intrin.cpp:70-110`）。
- 颜色编码：rgb8 会转成 BGR（`vision_node.cpp:509-511`）；`img_bridge.cpp:42-61` 支持常见编码。

### 2.3 像素 → 机器人坐标

坐标约定：
- 相机系：x 右，y 下，z 前。
- head/base 系：x 前，y 左，z 上（`vision.yaml:30` 注释）。
- base 系的 z=0 平面被当作地面。代码用射线与 z=0 求交，所以 `/head_pose` 给出的 base 原点应该在地面（足底）处，**待实机验证**。

变换链（`vision_node.cpp:325-326`，seg 在 `564` 行同理）：

```
p_eye2base = p_head2base(/head_pose, 按时间戳就近同步) · p_headprime2head(pitch/yaw/z 补偿) · p_eye2head(yaml extrin 4×4)
```

- `p_head2base`：`PoseCallBack` 用**接收时刻的节点时钟**给 pose 打时间戳（`vision_node.cpp:737-750`）。`DataSyncer` 在 500 帧 pose 缓冲里找与图像 `header.stamp` 最近的一帧（`data_syncer.cpp:125-134`）；时差超过 40ms 会打印告警（`vision_node.cpp:312-314`）。
- `p_headprime2head = Pose(0,0,z_comp, 0, pitch_comp°, yaw_comp°)`（`vision_node.cpp:137-141`）。可以通过 `/booster_soccer/cal_param` 在运行时修改。
- **地面投影公式**（`CalculatePositionByIntersection`，`pose_estimator.cpp:8-21`）：
  - 归一化射线 `r = K⁻¹[u,v,1]`（含去畸变）。
  - 旋转到 base 系：`d = R·r`，其中 `R, t` 取自 `p_eye2base`。
  - 求交点 `s = -t_z / d_z`，`P = t + s·d`。
- 各类别取哪个像素点：
  - Ball：bbox **底边中点**（`pose_estimator.cpp:47-53`）。
  - Person / Opponent / Goalpost：底边中点（`HumanLikePoseEstimator`，`102-107`）。
  - 场地标志点：bbox 中心（`23-29`）。`field_marker_pose_estimator.refine=true` 时改用 Canny+Hough 找交点精修（`441-450`），默认 false。
- **深度路径**（默认全部关闭，`use_depth: false`）：
  - 球：PCL 球面拟合，半径 0.109，仅在 ≤1.2m 时启用（`55-93`）。
  - 人形：平面拟合（`109-146`）。
  - brain **只使用 `position_projection`**，不用 `position`（`brain.cpp:1669-1672`）。
- 每帧还会把图像四角和中心投影到地面，放进 `corner_pos`；brain 用它算视野框 `VisionBox`（`vision_node.cpp:434-441`；`brain.cpp:1816-1859`）。
- 头部关节在视觉里的作用：只通过 `/head_pose` 间接体现。brain 另外用 `/low_state` 的头角做追球（`CamTrackBall`）和深度视野判断。

### 2.4 标定

| 项 | 位置 |
|---|---|
| 内参 / 外参 / 补偿 | `src/vision/config/vision.yaml:21-54`（`camera.intrin`、`camera.extrin`、`pitch/yaw/z_compensation`）。可放 `vision_local.yaml` 覆盖（该文件已被 `.gitignore`） |
| brain 也读这个外参 | `brain.cpp:267-313` 读 `vision_config_path` 的 `camera.extrin` 得到 `camToHead`，用于深度点云转换（`brain.cpp:1364-1387`） |
| 手眼标定 | `ros2 run vision calibration_node handeye src/vision/config/vision.yaml [--ros-args -p board_w:=11 -p board_h:=8 -p board_square_size:=0.05]`（默认参数见 `calibration_node.cpp:103-105`）。按 `s` 采集、`c` 计算，结果可以覆盖输入 yaml 并写入 `/opt/booster/vision.yaml`，失败时写 `/tmp/vision.yaml`（`calibration_node.cpp:231-396`）。**只在 aarch64 上编译**（`src/vision/src/CMakeLists.txt`） |
| 外参偏置标定 | `calibration_node offset <cfg>`。以 `calibration.offset.field_marker_path`（`src/vision/config/field.yaml`，某个非标准场地的标志点真值）为参照（`calibration_node.cpp:437-622`） |
| 标定日志 | `~/Workspace/calibration_log/{handeye,offset}/<time>` |

注意：手眼标定结果写到 `/opt/booster/vision.yaml` 后，**main 分支的 vision / brain 不会读它**。需要手动拷贝到 `src/vision/config/vision.yaml` 或 `vision_local.yaml`，然后重新 `build.sh`，因为运行时读的是 install/share 下的副本。【fw1.7 #26】Demo 1.7 同样不读（`start.sh:33`）；标定程序第一个问题答 `y` 会直接改写 `src/vision/config/vision.yaml`（`event-sop.md` §6.5）。

### 2.5 数据记录

- `save_data` 在 launch 中默认为 **true**，`save_fps=2`（`src/vision/launch/launch.py:83-97`）。
- 记录内容写到 `~/Workspace/vision_log/<时间>/`：`color_*.jpg`、`depth_*.png`、`pose_*.yaml`，以及合并后的 `vision_local.yaml`（`vision_node.cpp:184-186, 482-490`）。长时间运行要注意磁盘占用。
- `save_data_nonstationary: true` 时，只在头部运动时记录。
- **潜在崩溃**：`save_data:=false` 时 `data_logger_` 为 nullptr，但 `vision_node.cpp:186` 仍然调用 `data_logger_->LogYAML`。待实机验证。

---

## 3. brain 包

### 3.1 进程与线程模型（`src/brain/src/main.cpp`）

- 线程 t：`while(ok){ brain->tick(); sleep(10ms) }`。实际频率低于 100Hz，等于 1/(tick 耗时+10ms)。
- 线程 t1：独立的 rclcpp Context，节点名 `brain_node_ext`，订阅手柄、GameController、Agent 指令。
- 主线程：`SingleThreadedExecutor` 负责视觉、里程计、深度等回调。
- `BrainData` 里只有 robots/goalposts/markings/fieldLines/obstacles 五个 vector 有互斥锁（`brain_data.h:58-104`），其它字段（ball、pose、penalty 等）跨线程读写都没有加锁。

### 3.2 行为树框架

- **BehaviorTree.CPP v4**：CMake 依赖 `behaviortree_cpp`（`CMakeLists.txt`），XML 使用 `BTCPP_format="4"`。用到的特性有 `_while` 前置条件、`_autoremap`、`Script`、`ScriptCondition`、`IfThenElse`、`RunOnce`、`Sleep`、`ReactiveSequence`。最低需要的 4.x 小版本待验证；Humble 可用 `ros-humble-behaviortree-cpp`。
- 加载方式：`registerBehaviorTreeFromFile(tree_file_path)` → `createTree("MainTree")`（`brain_tree.cpp:66-67`）。`tree_file_path` 由 launch 参数 `tree:=game.xml` 决定（`launch.py:23-29`），XML 位于 `src/brain/behavior_trees/`。
- 黑板：`BrainTree::getEntry/setEntry` 直接读写 root blackboard（`brain_tree.h:24-38`），初始值见 `initEntry()`（`brain_tree.cpp:72-114`）。
- 节点注册：`REGISTER_BUILDER(Name)` 把 `Brain*` 注入节点（`brain_tree.cpp:21-58`）。定位类节点在 `locator.cpp:13-23` 注册。

### 3.3 行为树结构（`src/brain/behavior_trees/game.xml`）

```
MainTree: Sequence
├─ RunOnce{ control_state=3 }            ← 启动即进入自动模式（game.xml:13）
├─ [control_state==1 || go_manual || assist_*] 手动/辅助：SimpleChase / Kick（通常什么都不做，交给手柄）
├─ [control_state==2] LT+A：CamScanField(!odom_calibrated) / CamFindAndTrackBall / SelfLocateEnterField
└─ [control_state==3 && !go_manual] 自动比赛
   ├─ SubTree AutoGetUpAndLocate → CheckAndStandUp（摔倒自起，最多 retry_max_count 次）
   ├─ [gc_is_under_penalty] 罚下：SetVelocity(0) + 找球/跟踪 + SelfLocateEnterField
   └─ [!gc_is_under_penalty]
      ├─ [sub_state_type=='TIMEOUT'] 站立 + 定位
      ├─ [sub_state_type=='NONE']
      │   ├─ INITIAL：扫场 / 跟球 + SelfLocateEnterField（场边入场定位）
      │   ├─ READY  ：MoveHead(0.35,0) + GoToReadyPosition + Locate
      │   ├─ SET    ：CamFindAndTrackBall + SetVelocity(0) + Locate
      │   ├─ PLAY   ：StrikerPlay | GoalKeeperPlay（按黑板 player_role）
      │   └─ END    ：SetVelocity(0)
      └─ [sub_state_type=='FREE_KICK' && PLAY]
          ├─ STOP     ：跟球 + Locate + 站立
          ├─ GET_READY：Locate + StrikerFreekick | GoalKeeperFreekick
          └─ SET      ：跟球 + Locate + 站立
```

- **StrikerPlay**（`subtrees/subtree_striker_play.xml`）：
  1. SelfLocate(trust_direction) + Locate。
  2. `wait_for_opponent_kickoff` 为真时原地看球。
  3. `ball_out` 为真时执行 GoBackInField。
  4. 否则依次执行 CamFindAndTrackBall → CalcKickDir → StrikerDecide，再按 `decision` 分派：`find`→FindBall、`assist`→Assist、`chase`→Chase、`auto_visual_kick`→RLVisionKick、`adjust`→Adjust、`kick`→Kick(0.8)、`cross`→Kick(0.4)。
- **GoalKeeperPlay**（`subtree_goal_keeper_play.xml`）：GoalieDecide 的输出为 `find`/`retreat`→GoToGoalBlockingPosition，`chase`→Chase，`adjust`→Adjust，`kick`→Kick(1.2)。守门员**不使用 RL 视觉踢**。
- **FindBall**（`subtree_find_ball.xml`）：GoBackInField + CamFastScan → TurnOnSpot(π, 朝最后看到球的方向) → 再扫一次 → GoToReadyPosition + Sleep 5s。
- **Locate**（`subtree_locate.xml`）：SelfLocate(trust_direction) → 1M → 2T → PT → LT → 2X → Border（后六个 msecs_interval=300、max_dist=3、max_drift=2）。

### 3.4 节点功能表（`src/brain/src/brain_tree.cpp`）

| 节点 | 行号 | 行为要点 |
|---|---|---|
| `CamTrackBall` | 142-190 | 球离图像中心超过 30% 宽/高时按像素差×FOV/3.5 修正头角；看不到球时以 1% 步长缓慢转向记忆中的球（或队友报告的球） |
| `CamFindBall` | 192-244 | 6 点头部扫描序列（pitch 1.0 / 0.2，yaw ±1.1），1s 切换一次 |
| `CamScanField` | 246-264 | 按 `msec_cycle` 左右扫，上半周期用 high_pitch，下半周期用 low_pitch |
| `CamFastScan` | 1260-1281 | 7 点快速扫描（300ms 一点） |
| `Chase` | 266-357 | 目标点设在球后 `dist` 处（沿 kickDir）。偏角 > 90°×1.2 时绕到球后，绕行半径 `safe_dist`。`avoid_during_chase` 时按深度栅格避障。vx=min(vx_limit, range)，再乘 sigmoid(\|vθ\|)。计算了平滑量但**没有使用** |
| `SimpleChase` | 359-392 | 直接朝球走（仅手动辅助模式使用） |
| `Adjust` | 645-715 | 绕球切向移动，对准 kickDir。切向速度 far/near 按 \|Δdir\|·R 与 near_threshold 比较切换；径向保持 `range` |
| `CalcKickDir` | 717-760 | 射门角窗口 < `cross_threshold`(0.2) 且球在中圈外 → `cross`（传向对方点球点一半距离处）；防守任意球 → `block`（朝向远离本方球门的方向）；其余 → `shoot`（瞄对方球门中心） |
| `StrikerDecide` | 762-874 | 决策树见 §7.3 |
| `GoalieDecide` | 876-938 | 球 x>0（在对方半场）→ retreat；range>3 → chase；机器人→球方向指向对方半场 → kick；否则 adjust |
| `Kick` | 980-1067 | `crabWalk(ballYaw, speed)`，速度从 0.5 每 tick 加 0.1，直到 `speed_limit`。持续时间 = `min_msec_kick + range/speed`。`abort_kick_when_ball_moved` 时球远离超过 0.3m 或丢球 1s 即中止 |
| `RLVisionKick` | 1073-1195 | 先减速 500ms → `kVisualKick` → 头部 pitch 0.4→0.7。退出条件：(球>5m 或 cost>8，且超过 min_msec_kick) 或 lose_ball 或 ball_out，满足后减速再执行 `robocupWalk()` |
| `GoToReadyPosition` | 1344-1389 | 站位（见 §3.6），调用 `moveToPoseOnField2` |
| `GoToFreekickPosition` | 400-504 | 任意球进攻/防守站位，按 `myStrikerIDRank` 分配 |
| `GoToGoalBlockingPosition` | 508-556 | 守门员站在球与本方球门中心连线上、距底线 `dist_to_goalline`(2.5m) 处，y 限幅 |
| `Assist` | 558-643 | 非 lead 前锋站在球后 2m（次要者 4m），对齐本方球门方向；有两名助攻时左右错开 ±0.5 |
| `GoBackInField` | 1391-1419 | 出界后以 0.4m/s 走回场内 |
| `TurnOnSpot` | 1283-1319 | 用里程计 θ 积分原地转指定角度（5s 超时） |
| `MoveToPoseOnField` | 1321-1342 | 通用导航节点（`moveToPoseOnField2`） |
| `CheckAndStandUp` | 1441-1478 | 满足 `recoveryState==HAS_FALLEN && current_planner_index==1` 且未超过重试次数 → `standUp()`，并设置 `shouldExitRLVisionKick`（planner index 的含义取自固件，待验证） |
| `StandStill`/`SetVelocity`/`StepOnSpot`/`MoveHead`/`WaveHand`/`CalibrateOdom`/`PrintMsg` | — | 工具节点 |

### 3.5 角色分配与协作（`brain.cpp:379-606 handleCooperation`）

- 初始角色来自 `game.player_role`（`striker`|`goal_keeper`），launch 参数 `role:=` 可以覆盖。运行时角色存在黑板 `player_role` 中。
- **lead（控球者）选举**：每个 tick 按 `updateCostToKick()` 计算代价（`brain.cpp:764-844`），近似为「到踢球需要的秒数」。代价项：
  - 距上次看到球的秒数；
  - 丢球 +5；
  - 球距离；
  - 途中有障碍 +0.5；
  - \|球方位角\|；
  - 会与队友相撞，每名 +2；
  - 绕球调整角 ×0.4/0.3；
  - 已摔倒 +15；
  - 未定位 +100。

  最后做 EMA 平滑（0.8/0.2）。
  - 满足 `(队友最小cost < ball_control_cost_threshold(20) && 我 > 队友最小)` 或 `我的排名 ≥ 2` 时，我不是 lead，决策变为 `assist`（`brain.cpp:516-529`）。
- **队友球位融合**：取存活且看到球的队友中 `ballRange` 最小者；它报告的球距离我超过 `tm_ball_dist_threshold` 才信任。在我自己已忘记球时，用它覆盖我的球记忆（`brain.cpp:437-477`）。
- **守门员换人**：守门员是 lead，并且离本方球门比所有队友都远时，发送 `cmd=10+最近队友id`，对方变为守门员，自己变为前锋。冷却 2s（`brain.cpp:532-567, 569-591`）。
- **按罚下补位**：`enable_role_switch`（默认 false）开启后，场上人数不满时我必须当前锋；我被罚且只差我一人时，我是守门员（`brain.cpp:481-497`）。
- **角色复位**：INITIAL，或 READY 时满员，恢复为初始角色（`brain.cpp:499-501, 596-603`）。手柄 LT+Y 可以切换角色（`brain.cpp:1088-1094`）。
- **多前锋站位**：`myStrikerIDRank` 等于 id 比我小的存活前锋数，决定 READY 和任意球站位（`brain.cpp:507-515`）。

### 3.6 站位（`GoToReadyPosition`，`brain_tree.cpp:1344-1389`）

场地坐标系：原点在中圈，+x 指向对方球门，+y 在左侧，θ 逆时针为正（`types.h:38-43`）。本方球门位于 x=-L/2。

| 角色 / rank | 目标 (x, y) |
|---|---|
| striker rank0 | 我方开球 (-R-0.5, 0)，否则 (-2R, 0)；R 为中圈半径 |
| striker rank1 | 同上 x，y=-1.5 |
| striker rank2 | (-L/2+penaltyAreaLength, R/2) |
| striker rank3 | (-L/2+penaltyDist, -R/2) |
| goal_keeper | (-L/2+goalAreaLength, 0)，θ=0 |

靠近边界（distToBorder>-1）时，限速降到 vx 0.6、vy 0.4。

场地尺寸常量（`types.h:33-35`），字段顺序为 `{L, W, penaltyDist, goalWidth, circleR, penAreaL, penAreaW, goalAreaL, goalAreaW}`：
- `FD_KIDSIZE{9,6,1.5,2.6,0.75,2,5,1,3}`
- `FD_ADULTSIZE{14,9,2.1,2.6,1.5,3,6,1,4}`
- `FD_ROBOLEAGUE{22,14,3.6,2.6,2,2.25,6.9,0.75,3.9}`

由 `game.field_type` 选择（`brain_config.cpp:524-547`）。仓库默认是 `adult_size`，官方 5v5 文档示例用的是 `kid_size`。

### 3.7 自定位

**不是持续运行的粒子滤波，而是「里程计 + 周期性重定位」**：
- 位姿 = `odomToField ∘ robotPoseToOdom`（`brain.cpp:1321-1335`）。其中里程计 x、y 要乘以 `robot.odom_factor`。
- 定位成功后，`calibrateOdom(x,y,θ)` 重新计算 `odomToField`，并刷新球、机器人、门柱、标志点的场地坐标（`brain.cpp:933-986`）。

**全局求解器 `Locator::locateRobot`**（`locator.cpp:273-345`）：
- 性质：基于标志点的随机粒子搜索 / 退火。
  1. 在约束盒 `PoseBox2D` 内均匀撒 200 个粒子。
  2. 残差 = Σ(变换后的标志点到同类地图点的最近距离 / 标志点距离 × 3)（`182-196`）。
  3. 以 `N(min-2σ, σ)` 作为权重做重采样（`219-262`）。
  4. 每轮粒子数 ×0.85，扰动 ×0.8。
  5. 最多 20 轮。x、y、θ 三个方向的离散度都 < 0.2 时判为收敛。
  6. 平均残差 < `locator.max_residual`（0.35）才算成功。
- 标志点数 < `locator.min_marker_count`（5）直接失败（code 4）。
- 使用的地图标志点：X（中圈 2 点）、P（2 个点球点）、T（中线两端、禁区/球门区与底线交点）、L（禁区角、球门区角、四个场角）（`locator.cpp:34-68`）。
- 输入是视觉的 `LCross/TCross/XCross/PenaltyPoint` 检测，置信度 ≥50（`brain.cpp:1758-1779`；`brain_data.cpp:22-46`）。

**约束模式**：
- `SelfLocateEnterField`（`locator.cpp:429-496`）：假设机器人站在**本方半场左或右边线外 0~1m**，面朝场内（±30°），x∈[-L/2, -R]。左右各解一次，取残差小的一侧。INITIAL、罚下、LT+A 时使用。
- `SelfLocate mode=trust_direction`（`348-427`）：θ 限制在 ±1°，x、y 盒随「距上次成功的时间 × 0.1m/s」扩大。默认 10s 最多执行一次。另有 `face_forward`、`fall_recovery` 两种模式。

**局部修正**（只修 x、y，不修 θ；修正后都会用全体标志点残差验证）：
- `1M`：最近的已识别标志点，需在画面中央（`498-603`）。
- `2T`：两个 T 点组成的底线 pattern（`706-820`）。
- `LT`（`822-937`）。
- `PT`：门柱 + T（`939-1053`）。
- `2X`：中圈两 X 点（`605-704`）。
- `Border`：用已识别的边线 / 底线 / 中线求垂距（`1055-1219`）。

**场地线识别**：`processFieldLines` 先合并共线段，再只保留横向或纵向、且长度 > 0.2m 的线，与 `mapLines` 按概率加特征加分匹配（T 点、门柱、定位球状态下球在线上等），得到 `identifyFieldLine`（`brain.cpp:1452-1637`）。

### 3.8 队内通信（`brain_communication.cpp`）【fw1.7 #27】

- 端口：discovery 广播 `20000+team_id`；状态单播 `30000+team_id`（`initCommunication`，`39-62`）。`enable_com`（默认 true）或 launch `disable_com:=true` 控制开关。
- 报文结构：`TeamCommunicationMsg`（`team_communication_msg.h:7-27`），包含 role、isAlive、isLead、球信息、cost、机器人位姿、kickDir、cmdId/cmd。原始 C struct 直接收发，只按长度和 `validation=31202` 校验，依赖双方编译器与架构一致。
- 队友判活：超过 5s 没有收到消息，或被 GC 罚下，即判离线（`brain.cpp:414-430`）。
- ⚠ README NOTICE：新规则**禁止单播并限制包大小**。比赛前必须改写 `brain_communication.cpp`；2026 分支已有适配。

### 3.9 参数表（`src/brain/config/config.yaml`）【fw1.7 #28】Demo 1.7 的 `config.yaml` 多了 95 个键、默认值也不同（`team_id 70`、`number_of_players 5`、`robo_league`、`game_control_ip 172.169.80.24`），见 `event-sop.md` §6.2。

参数加载顺序（后者覆盖前者）：
1. `config/config.yaml`
2. `config/config_local.yaml`
3. `~/agents/booster_soccer/brain.yaml`
4. launch 参数字典（`launch.py:32-78`）

注意事项：
- 修改 `src/…/config.yaml` 后必须重新 `build.sh`，因为 `--symlink-install` 对 install 目录的 config 是否生效待验证；官方文档要求重编。
- 只有在构造函数中 `declare_parameter` 过的键才生效（`brain.cpp:28-136`）。未声明的键被 ROS 2 忽略，只能拿到 `get_parameter_or` 的默认值，例如 `strategy.ball_out_threshold`、`obstacle_avoidance.enable`、`robot.head_*_limit`。

| 键 | 默认值(yaml) | 含义 / 使用处 |
|---|---|---|
| `game.team_id` | 29 | 必须与 GC 一致；同时决定通信端口 |
| `game.player_id` | 1 | 1..11；GC 罚下数组索引为 id-1 |
| `game.field_type` | adult_size | adult_size / kid_size / robo_league |
| `game.player_role` | striker | striker / goal_keeper |
| `game.treat_person_as_robot` | false | 调试时把 Person 当作障碍机器人 |
| `game.number_of_players` | 3 | 满员判断（角色复位与补位）；5v5 应设为 5 |
| `robot.robot_height` | 0.8（T1 为 1.12） | 近似算出俯仰角 `pitchToRobot`，供追球头部指向（`brain.cpp:1676, 1935`） |
| `robot.odom_factor` | 0.8（T1 为 1.2） | 里程计 x、y 缩放（`brain.cpp:1324-1325`） |
| `robot.vx_factor` | 0.5 | crabWalk 中 vx 的缩放，补偿 x/y 实际速度比（`robot_client.cpp:125-132`） |
| `robot.yaw_offset` | 0.0 | crabWalk 方向补偿 |
| `robot.vx_limit / vy_limit / vtheta_limit` | 1.0 / 0.4 / 1.2 | **全局速度上限**，所有 setVelocity 都会被裁剪（`robot_client.cpp:91-93`） |
| `robot.min_vx / min_vy / min_vtheta` | 0.3 / 0.3 / 0.25 | 非零小速度抬高到该值，防止机器人不响应 |
| `strategy.ball_confidence_threshold` | 50 | 球置信度下限（×100 刻度） |
| `strategy.ball_memory_timeout` | 2.0 s | 超时后 `ball_location_known=false` |
| `strategy.tm_ball_dist_threshold` | 2.0 m | 信任队友球位的距离门限 |
| `strategy.limit_near_ball_speed / near_ball_speed_limit / near_ball_range` | false / 0.2 / 3.0 | Chase 近球限速 |
| `strategy.abort_kick_when_ball_moved` | true | Kick 中止条件 |
| `strategy.ball_out_threshold` | 2.0 | **未声明，yaml 值无效**，实际使用 getter 默认值 2.0 |
| `strategy.cooperation.enable_role_switch` | false | 按罚下补位 |
| `strategy.cooperation.ball_control_cost_threshold` | 20.0 | lead 判定阈值 |
| `obstacle_avoidance.*` | 见 yaml:37-58 | 深度栅格：采样步长 16px，高度 >0.45m 视为障碍，格 0.2m，范围 x 3m × y ±5m，排除自身 0.4×0.5，占据阈值 2000，碰撞走廊 0.3m，安全距离 2.0，避障时长 3s，追球避障开（3.5m），踢球避障关。`enable_freekick_avoid` 已声明**但没有代码读取**；`get_enable_obstacle_avoidance()` 读的是未声明的 `obstacle_avoidance.enable`，恒为 false |
| `RLVisionKick.enableAutoVisualKick` | true（T1 必须 false） | 是否启用固件视觉踢 |
| `RLVisionKick.autoVisualKickEnableDistMin / DistMax / Angle` | 0.2 / 4.0 / 0.8 | 触发区间：距离 [0.2, 4.0]m，\|球方位\| < 0.8×1.3 |
| `locator.min_marker_count / max_residual` | 5 / 0.35 | 全局定位门限 |
| `enable_com` | true | 队内通信 |
| `recovery.retry_max_count` | 2 | 自起重试次数 |
| `vision.image_camera_info_topic` | `/StereoNetNode/rectified_image` | ⚠ 这是**图像**话题，却按 CameraInfo 订阅，类型不匹配，回调永不触发，`cameraImageWidth/Height` 停在默认 1280×720（`brain_config.h:112-113`）。会影响 CamTrackBall 居中、`isBoundingBoxInCenter`、TurnOnSpot。**待实机验证**，建议改为 `/StereoNetNode/stereonet_depth/camera_info` 或彩色图的 camera_info |
| `vision.depth_image_topic / depth_camera_info_topic` | StereoNet 深度 | 避障与 FOV |
| `game_control_ip` | 127.0.0.1 | **必须改成 GC 机 IP**，否则 GC 看不到机器人在线（RGrt 单播目标） |

launch 参数：`tree`、`role`、`team_id`、`player_id`、`robot_name`、`sim`（use_sim_time）、`disable_com`、`agent_mode`、`vision_config_path`（`launch.py:83-133`）。示例：`./scripts/start.sh role:=goal_keeper player_id:=1`。

**K1 与 T1 差异**（README）：

| 项 | K1 | T1 |
|---|---|---|
| `robot.robot_height` | 0.8 | 1.12 |
| `robot.odom_factor` | 0.8 | 1.2 |
| `RLVisionKick.enableAutoVisualKick` | true | false（T1 不支持 VisualKick） |
| 相机话题 | 按实际相机设置 | 按实际相机设置 |
| 检测模型 | `best_digua_second_10.3.engine` | README 写 `best_1223_10.3.engine`，**仓库里没有此文件**，只有 `best_digua_1223_10.3.engine` |
| 分割模型 | `best_seg_orin_10.3.engine` | 同左 |

---

## 4. game_controller 包

- **接收**（`game_controller_node.cpp:46-115`）：UDP bind `0.0.0.0:port`，port 默认 3838（`launch.py:18`）。包长必须严格等于 `sizeof(HlRoboCupGameControlData)`，`version == 12`（`HL_GAMECONTROLLER_STRUCT_VERSION`），**不校验 "RGme" header**。
  - 结构体约 688 字节（推算值；启动日志 `:67` 会打印实际大小）。
  - 可选 IP 白名单：`enable_ip_white_list` / `ip_white_list`（`launch.py:20-26`）。
  - 通过校验的包由 `handle_packet` 逐字段转成 `game_controller_interface/GameControlData`，发布到 `/booster_soccer/game_controller`（`:134-200`）。
- **数据结构**：`HlRoboCupGameControlData` / `HlTeamInfo` / `HlRobotInfo`（`include/RoboCupGameControlData.h:131-171`），对应的 msg 定义在 `src/interface/game_controller_interface/msg/`。
- **状态映射**（brain 侧 `gameControlCallback`，`brain.cpp:1098-1227`）：

| GC 字段 | brain 黑板 |
|---|---|
| `state` 0..4 | `gc_game_state` ∈ {INITIAL, READY, SET, PLAY, END}（FINISHED 映射为 "END"；数组没有越界保护） |
| `kick_off_team == team_id` | `gc_is_kickoff_side` |
| `secondary_state`：0→NONE；3→TIMEOUT；4 直接任意球、5 间接任意球、6 点球、7 角球、8 球门球、9 界外球 → 全部视为 `FREE_KICK`，真实类型存入 `data->realGameSubState`，其中 4/6/8 同时置 `isDirectShoot`；**1 点球大战、2 加时 → default → FREE_KICK（不正确）** | `gc_game_sub_state_type` |
| `secondary_state_info[1]` 0/1/2 | `gc_game_sub_state` ∈ {STOP, GET_READY, SET} |
| `secondary_state_info[0] == team_id` | `gc_is_sub_state_kickoff_side` |
| `teams[i].players[j].penalty`；红牌 → SUBSTITUTE | `data->penalty[]`，`gc_is_under_penalty`。刚被罚下时置 `odom_calibrated=false`，以便重新入场定位 |
| score / secs_remaining | `data->score` 等；进球时 `we_just_scored` 为真（没有节点使用） |

- **开球处理**（`brain.cpp:680-714`）：我方不开球时，在 SET/READY 期间置 `wait_for_opponent_kickoff`；进入 PLAY 后，球移动超过 max(0.15·range, 0.3m) 或过 10s 才解除。我方开球或任意球时 `isFreekickKickingOff` 保持 10s，期间 StrikerDecide 要求 `reachedKickDir` 才出脚（`brain.cpp:344-367`）。
- **返回包**：由 **brain**（不是 gc 节点）每秒向 `game_control_ip:3939` 单播 `HlRoboCupGameControlReturnData{"RGrt", v2, team, player, message=2 ALIVE}`（`brain_communication.cpp:237-252`）。**不发送** MAN_PENALISE / UNPENALISE。
- **没有 GC 时**：`gc_game_state` 初始为 ""，自动模式下没有分支匹配，机器人除自起外原地不动。另外 `penalty[]` 初值为 SUBSTITUTE（`brain_data.cpp:6`），队友会认为我不在线。离线测试需要用 agent 模式或本地 GC（§5.4）。
- **2026 规则 / 新 GC**：main 只支持 HL v12 包，而官方文档中的 GameController 1.0.1 发的正是 HL v12，与 main 兼容，不需要换分支【已更正，#37】。HSL 2026 的新 GameController（v19/v20）、5v5、哨声检测请参考 `sandbox/support_2026_game_controller` 分支（README）；该分支只收 v19/v20，收不到 GC 1.0.1 的包。该分支的依赖包含 `libasound2-dev`、`libfftw3-dev`（据 GitHub 页面）。点球策略仍未实现。【fw1.7 #24】本赛事裁判机是 GC 7.0.0-rc.3（v20），用 Demo 1.7（已支持 v20），不要用 main。

---

## 5. 编译、部署与调试

### 5.1 依赖

- 系统：ROS 2 Humble（脚本 source `/opt/ros/humble`）、`ros-humble-backward-ros`（README）。
- brain：`behaviortree_cpp`（v4）、OpenCV、Eigen3、yaml-cpp、tf2*、visualization_msgs、nav_msgs、diagnostic_msgs（`src/brain/CMakeLists.txt`）。
- vision：PCL、image_transport、OpenCV ≥4.5、YAML-CPP；链接 `booster_robotics_sdk.a fastrtps fastcdr`（`src/vision/src/CMakeLists.txt`）。仓库内置 ceres、munkres、googletest（`src/vision/thirdparty`，LFS）。
- 已安装的 **Booster Robotics SDK** 头文件（`booster/robot/b1/b1_loco_api.hpp` 等）。brain 通过 `booster_interface/message_utils.hpp` 用它构造 JSON 参数。
- 推理后端二选一：
  - CUDA + TensorRT 8.6 / 10.3（aarch64 使用 `/usr/local/cuda/targets/aarch64-linux`；x86 硬编码 `/usr/local/TensorRT-8.6.1.6`，见 `src/vision/src/model/CMakeLists.txt`）；
  - ONNX Runtime 1.21.0（`src/vision/scripts/install_onnxruntime.sh`，装到 `/usr/local`）。README 写的 `./third_party_aarch64/...` 路径在 main 中不存在。
- 官方文档版本配套：K1 固件 1.6 + SDK 1.3.6（V1.6 包）。README 另要求固件 ≥1.5.2 才能使用 VisualKick。

### 5.2 构建

```bash
git lfs pull                      # 模型与三方库是 LFS 指针
./scripts/build.sh                # colcon build --symlink-install --base-paths src
./scripts/build_no_cuda.sh        # 仿真 / 无 GPU：-DNO_CUDA=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo
# Windows 拷贝导致 ^M 时：find scripts -type f -print0 | xargs -0 sed -i 's/\r$//'
```

`scripts/build_agent.sh` 依赖仓库外的 `booster_agent_framework`。

【fw1.7 #28】Demo 1.7：模型 engine 已随 zip 附带，不需要 `git lfs pull`；`build.sh` 不带 `--symlink-install`（改配置后必须重新 build）；brain include 的 `booster_internal` 头文件哪里都没有发布，只被未调用的 `walkMode()` 使用，编译报错时删掉即可（`fw1.7-demo-v1.7.md` §0 #6）。

### 5.3 在 K1 上启动

- `./scripts/start.sh [brain launch 参数]`：
  1. 先执行 `stop.sh`（`pkill -9` vision_node、brain_node、game_controller）。
  2. 设置 `FASTRTPS_DEFAULT_PROFILES_FILE=/opt/booster/BoosterRos2/fastdds_profile_udp_only.xml`，这是机器人上的文件；仓库里的 `configs/fastdds.xml` 没有脚本引用。
  3. 用 nohup 启动三个 launch，日志分别写到仓库根目录的 `vision.log`、`brain.log`、`game_controller.log`。
  4. 【fw1.7 #28】Demo 1.7 的 `start.sh` 还会 `pkill -9 python3`、`disable --now booster-agent-manager.service`、mask apt 定时任务、`jetson_clocks`（`start.sh:9-19`）。
- 上场顺序（官方文档 §6.2）：PREP → WALK(RT+A) → **LT+A**（`control_state=2`：清除定位，扫场，入场定位）→ 等待定位完成 → **LT+B**（`control_state=3`：自动比赛）。LT+X 是 `control_state=1`（取消 / 手动）。
  - 摇杆任一轴 >0.1 置 `go_manual`，自动控制暂停（`brain.cpp:1046-1096`）。
  - 注意：`game.xml:13` 在启动时就把 `control_state` 设为 3。
  - 官方文档说 LT+A 同时切入 kSoccer 模式；但 main 的 `joystickCallback` 没有调用任何切模式 API。这一步不是固件处理手柄，而是 demo 代码完成的：V1604 在 `game.xml` 的 LT+A（control_state==2）分支里执行 `<RunOnce><RobocupWalk/></RunOnce>`，调用 `changeRobocupMode()`，先 `ChangeMode(kSoccer)` 再 `VisualKick(false)`（`robot_client.cpp:71-78`）【已更正，#38】。
- vision launch 参数：`show_det`、`show_seg`（cv::imshow，需要显示器）、`save_data`、`save_depth`、`save_fps`、`offline_mode`、`detection_model_path`、`segmentation_model_path`、`color_topic`、`depth_topic`、`intrin_topic`、`sim`、`vision_config_path`（`src/vision/launch/launch.py:61-128`）。
  - `vision_node` 只使用 argv[1]（vision.yaml）和 argv[2]（vision_local.yaml），launch 传入的第三个文件 `~/agents/booster_soccer/vision.yaml` **会被忽略**（`src/vision/src/main.cpp:17-21`）。
- 单独调试：`start_brain.sh`、`start_vision.sh`（前台运行，默认带 `sim:=true`）。

### 5.4 仿真与离线测试

- **单机仿真**：`./scripts/sim_start.sh`。所有节点带 `sim:=true`。需要把 vision.yaml 的话题改为 `/camera/robot0_rgbd_camera/...`，模型改为 `sim_data_*_0126.onnx`（README）。仿真器为 Booster Studio Simulator；issue #8、#10 提到了 Isaac Sim。
- **多机仿真**：`./scripts/sim_start_multi.sh`，3v3，队伍 29 和 30。每台机器人用 `detection_converter`，把仿真器发布的 JSON 检测结果（`/camera/<robot>_rgbd_camera/detections`，std_msgs/String）转成 Detections 和 LineSegments（`src/detection_converter/scripts/detection_converter_node.py`，置信度固定为 99），**完全绕过视觉模型**。brain 用 `robot_name:=robotN`，给话题加后缀。
- **无 GC 测试**：`agent_mode:=true` 后发布 `ros2 topic pub --once /booster_agent/soccer_game_control std_msgs/msg/String "{data: play}"`。可用指令为 `locate`/`ready`/`play`/`stop`，`play` 会同时设为我方开球（`brain.cpp:2382-2431`）。agent 模式会清空罚下状态，忽略 GC 包。
- **视觉离线回放**：`offline_mode:=true` 时 vision 改为订阅 `/booster_soccer/t_head2base`，可配合 rosbag 回放（`vision_node.cpp:296-302`）。`DataSyncer::LoadData` 可以读取 vision_log 目录（color_/depth_/pose_ 文件），供标定程序离线使用（`data_syncer.cpp:9-92`）。

### 5.5 日志与可视化

- `brain.log`：每 30 tick 打印一次彩色状态（队伍、GC 状态、开球、比分、通信、控制状态）（`brain.cpp:2267-2318`）。`log->debug()` 走 `RCLCPP_DEBUG`，默认级别不显示，需要调低 brain_node 的日志级别（launch 没有提供开关，待验证）。
- 定位日志 `/locate/*`、`self_locate`、`SelfLocateEnterField` 走 INFO（`locator.cpp`）。
- **`booster_soccer.layout`**：Foxglove 风格的布局 JSON（`configById`/`layout` 结构），供 **Booster Studio** 导入（README）。面板：
  - Image：`/camera/robot0_rgbd_camera/rgb/image_compressed`，叠加 Python 自定义层，用 `/booster_soccer/detection` 画框；
  - Publish：向 `/booster_agent/soccer_game_control` 发 "locate"；
  - Canvas：用 `/booster_soccer/field_dimensions`、`robot_pose`、`ball_position` 画场地；
  - 3D：MarkerArray、点云、占据栅格；
  - Terminal。

  自定义层使用 `@on_message` / `draw2d` 的 Python DSL，属于 Booster Studio 专有；**不是 rerun 布局**。在原版 Foxglove 中能否渲染待验证。标准话题（MarkerArray frame `map`）也可以直接用 RViz2 或 Foxglove 查看。

---

## 6. 二次开发指南

### 6.1 改哪里

| 目标 | 文件:行 | 说明 |
|---|---|---|
| 改进攻决策（何时追、调整、踢、传、视觉踢） | `src/brain/src/brain_tree.cpp:762-874`（StrikerDecide） | 阈值为 `chase_threshold`（XML）、`ball.range<1.5`、`\|ballYaw\|<π/2`、`reachedKickDir` 等 |
| 改节点参数（不改 C++） | `src/brain/behavior_trees/subtrees/subtree_striker_play.xml:25-33`，`subtree_goal_keeper_play.xml:27-32` | Chase、Adjust、Kick 的速度与阈值都是 XML 端口 |
| 改比赛状态机 | `src/brain/behavior_trees/game.xml` | GC 状态分支；新树通过 `tree:=xxx.xml` 选择 |
| 改守门员 | `brain_tree.cpp:876-938`（GoalieDecide）、`508-556`（封堵站位） | 守门员目前不用 RL 视觉踢 |
| 加新行为节点 | ① `include/brain_tree.h` 仿照 `SetVelocity`（`:530-547`）声明类与 `providedPorts`；② `src/brain_tree.cpp` 实现 `tick`/`onStart`/`onRunning`；③ 在 `BrainTree::init()` 加 `REGISTER_BUILDER(X)`（`:26-70`）；④ 新黑板键在 `initEntry()`（`:72-114`）中给初值；⑤ 在 XML 中使用 | CMake 用 `file(GLOB src/*.cpp)`，新 cpp 会自动编入 |
| 加新全局状态 / 感知预处理 | `brain.cpp:316-342`（tick）、`608-614`（updateMemory）、`brain_data.h` | 注意跨线程访问 |
| 改站位 | `brain_tree.cpp:1344-1389`（READY）、`400-448`（任意球）、`594-600`（Assist） | 场地尺寸在 `types.h:33-35` |
| 改踢球方向 / 射门窗口 | `brain_tree.cpp:717-760`（CalcKickDir）；`brain.cpp:716-747`（门柱角，优先使用看到的 OL/OR 门柱）；`846-863`（isAngleGood，margin 0.3，窗口过窄时改用 0.5） | — |
| 调 RL 视觉踢 | `config.yaml:60-64`；触发条件 `brain_tree.cpp:811-827`（含硬编码 `length/2-14.3`、`\|y\|<5`、`cost<7`）；退出条件 `:1127-1140`；`/kick_ball` 的 dir / power 在 `brain.cpp:989-1023`（power：球到对方球门中心 >6m 取 1.5，否则 6.0） | 固件版本与 VisualKick 版本（kV1/kV2）需要与 SDK 匹配 |
| 调行走踢 | `brain_tree.cpp:980-1067`（Kick）；`robot_client.cpp:124-141`（crabWalk）；`config.yaml` 的 `vx_factor`、`yaw_offset`、`abort_kick_when_ball_moved` | 踢偏时先调 `yaw_offset`、`vx_factor` |
| 调走路速度 | 全局上限 `config.yaml:17-22` → `robot_client.cpp:77-93`；各节点 XML 的 `vx_limit`；导航 `robot_client.cpp:250-349`（moveToPoseOnField2） | 全局上限会覆盖 XML 中更大的值 |
| 调头部扫描 / 追球 | `brain_tree.cpp:142-264`、`1260-1281`；限位 `robot_client.cpp:32-33` + `brain_config.cpp:92-102` | pitch 下限 0.45 rad 是硬限，想看远处需要改这里（K1 头 pitch 关节范围 -19°~49°，见 K1 规格书） |
| 调定位 | `config.yaml:66-68`；`locator.cpp:436-437`（入场约束盒，入场位置不同时要改）；`subtree_locate.xml` | — |
| 换检测模型 / 类别 | `src/vision/config/vision.yaml:55-71`；`src/vision/src/model/detector.cc:14-15`；`trt/config.h`（TRT8.6）；brain 标签分组 `brain.cpp:1244-1264`；各类阈值 `brain.cpp:1708, 1760, 1783, 1806` | 输入必须 640×640，输出格式为 ultralytics `[4+nc, 8400]` |
| 生成 TRT engine | TRT8.6：`src/vision/scripts/model/build_engine.sh <best.pt>`（pt → wts → `yolov8_det -s`）。**TRT10.3 下 `yolov8_det` 是空壳**（`src/model/trt/yolov8_det.cpp:168-171`），推测需要 `yolo export format=onnx imgsz=640` + `trtexec --onnx --saveEngine --fp16`，在目标机器上生成 | 待实机验证 |
| 换相机 | `vision.yaml:1-28`（话题、内参）+ `config.yaml:75-91`（brain 的相机 / 深度话题）+ 重新手眼标定 | — |
| 队内通信合规化 | `brain_communication.cpp:341-418`（改广播并压缩字段）、`team_communication_msg.h` | README NOTICE |
| 新 GC 协议 | `src/game_controller/*`、`game_controller_interface/msg`、`brain.cpp:1098-1227` | 参考 2026 分支 |

### 6.2 已知局限、疑似 Bug 与改进点（均源自代码）【fw1.7 #25】各条在 Demo 1.7 里的状态见 `fw1.7-demo-v1.7.md` §3.3：定位 bug（#3 等）仍在，代码搬到了 `brain_tree.cpp`。

1. **队内通信不合规**：单播加原始 struct（README NOTICE；`brain_communication.cpp:365-418`）。
2. **GC**：只支持 HL v12（`game_controller_node.cpp:97`）。点球大战、加时映射成 FREE_KICK（`brain.cpp:1168-1170`）。`gameStateMap[msg.state]` 和 `gameSubStateMap[...]` 没有越界检查（`brain.cpp:1118, 1173`）。只发 ALIVE。【fw1.7 #24】Demo 1.7 已支持 v20，越界检查已加；加时/点球按 v20 的 `game_phase` 处理（v12 下仍落到 default）；回包 v4。
3. **定位 Bug**：
   - `SelfLocate2X` 的 `dy` 误用 `p1+p1`（`locator.cpp:667`）。
   - `SelfLocatePT` 两处条件都比较 x，并且模板点用了 `fd.length`（应为 L/2），实际几乎不会命中（`locator.cpp:973-974, 1005`）。
   - `SelfLocateLT` / `PT` 内层循环在另一个 vector 上用 `j=i+1`，会漏掉候选（`:853, 969`）。
4. **图像尺寸配置疑似错误**：`vision.image_camera_info_topic` 指向图像话题（`config.yaml:84`），导致宽高使用 1280×720 默认值（`brain_config.h:112-113`），影响追球居中。待实机验证。
5. **参数失效**：yaml 中的 `strategy.ball_out_threshold` 未声明；`obstacle_avoidance.enable` 从未声明，任意球避障路径（`moveToPoseOnField3`）永远不会走到；`enable_freekick_avoid` 没有读取者；`strategy.enable_shoot`、`power_shoot.*`、`*_block` 等声明了但无人使用（`brain.cpp:68-89`）。
6. **死代码**：`Kick::_calcSpeed`（且读取了未声明的端口，`brain_tree.cpp:940-978`）、`Brain::calcKickDir`、`RobotClient::moveToPoseOnField`（v1）、`RLVisionKick::isMinIntervalSatisfied`、`msecs_stablize` 端口、`isKickingOff` 与 `we_just_scored`（只记录不使用）、`calibrate_*` 黑板项、`/booster_soccer/ball` 发布器。
7. **Chase 平滑无效**：计算了 `smoothV*` 却发送原始值（`brain_tree.cpp:346-354`）。
8. **头部硬限**：pitch ≥ 0.45 rad（`robot_client.cpp:33`）会把 CamFindBall 的 0.2、READY 的 0.35 都截断；yaw 限 ±1.1 rad，大于 K1 规格 ±59°。
9. **硬编码**：
   - StrikerDecide 场地常量 14.3 和 5（`brain_tree.cpp:821-824`）；
   - kick power 的 6m / 1.5 / 6.0（`brain.cpp:1009-1013`）；
   - `/kick_ball` 的 goal 固定为对方球门中心（`brain.cpp:998-1018`）；
   - 视觉 NMS 0.25 / 0.4（`impl.cpp:705, 908`）；
   - 标志点、门柱、机器人置信度阈值 50（`brain.cpp:1760, 1783, 1806`）；
   - 入场约束盒假设从本方半场边线进场（`locator.cpp:436-437`）。
10. **线程安全**：`BrainData` 的大部分字段和黑板都被 tick 线程、executor、ext 线程、通信线程并发读写，没有加锁（`brain.h:59` 的 TODO 也承认黑板和 data 存在重复）。vision 的 `CameraInfoCallback` 重建估计器与检测回调并发（`vision_node.cpp:847-870`）。
11. **视觉**：
    - 深度校验默认关闭，测距完全依赖外参与 `/head_pose`，所以标定质量决定踢球精度。
    - 球的测距用 bbox 底边，在球被遮挡或截断时有偏差。
    - `save_data` 默认开启，会持续写盘。
    - `save_data:=false` 时 `vision_node.cpp:186` 空指针。
    - 运行时不读 `/opt/booster/vision.yaml`。
12. **RLVisionKick 退出**：没有调用 `VisualKick(false)`，而是 ChangeMode(kWalking)（`brain_tree.cpp:1104, 1149`）；也没有传 VisualKickVersion。与固件的兼容性待实机验证。
13. **策略空白**：
    - 没有点球策略（README）；
    - `we_just_scored` 等庆祝逻辑没有接入；
    - 守门员没有扑救或下蹲（`use_squat_block` 未实现）；
    - 对手只在 `msecsToCollide` 中作为障碍考虑，并且只作用于未使用的 v1 导航；
    - 没有持续的概率滤波定位（没有 EKF/PF 跟踪），θ 完全信任里程计（trust_direction 只给 ±1°）。
14. **性能开销**：每个 tick 都重建并发布整套场地 MarkerArray（`brain.cpp:2433-2556`），并发布多个标量话题；`/kick_ball` 在非视觉踢状态下也持续发布。
15. **文档不一致**：README 中 T1 模型名、ONNX 安装脚本路径与仓库不符；`launch.py:94` 描述的 XML 目录（`src/brain/config/behavior_trees`）与实际（`src/brain/behavior_trees`）不符。

---

## 7. 关键代码片段

### 7.1 主决策循环

```cpp
// src/brain/src/main.cpp:22-32 —— 独立线程按 ~100Hz 调 tick（HZ=100，tick 后再 sleep 10ms）
thread t([&brain]() {
    while (rclcpp::ok()) {
        auto start_time = brain->get_clock()->now();
        brain->tick();
        auto end_time = brain->get_clock()->now();
        auto duration = (end_time - start_time).nanoseconds() / 1000000.0;
        brain->log->log_scalar("performance", "brain_tick_duration_ms", duration);
        this_thread::sleep_for(chrono::milliseconds(static_cast<int>(1000 / HZ)));
    }
});

// src/brain/src/brain.cpp:316-342
void Brain::tick()
{
    logDebugInfo(); logLags(); logStatusToConsole();
    publishVisualizationMarkers();   // 每 tick 发整套场地/机器人/球 Marker
    publishOdomToMapTF();
    publishRobotPose(); publishBallPosition(); publishTeammatesPoses();
    pubKickMsg();                    // /kick_ball：给固件视觉踢的参考
    updateMemory();                  // 球/机器人/障碍记忆超时、开球等待
    handleSpecialStates();           // 开球/任意球计时、进球标记
    handleCooperation();             // cost、lead、角色切换、队友球位
    tree->tick();                    // BehaviorTree tickOnce → 节点内调用 RobotClient
}
```

### 7.2 坐标变换（像素 → 机器人系 → 场地系）

```cpp
// src/vision/src/vision_node.cpp:325-326 —— 构造相机到 base 的位姿
Pose p_head2base = synced_data.pose_data.data;               // 来自 /head_pose，按时间戳同步
Pose p_eye2base = p_head2base * p_headprime2head_ * p_eye2head_; // 补偿 · yaml 外参

// src/vision/src/pose_estimator/pose_estimator.cpp:8-21 —— 射线与地面 z=0 求交
cv::Point3f CalculatePositionByIntersection(const Pose &p_eye2base, const cv::Point2f target_uv, const Intrinsics &intr) {
    cv::Point3f normalized_point3d = intr.BackProject(target_uv);          // K^-1 [u v 1]（含去畸变）
    cv::Mat mat_obj_ray = (cv::Mat_<float>(3, 1) << normalized_point3d.x, normalized_point3d.y, normalized_point3d.z);
    cv::Mat mat_rot = p_eye2base.getRotationMatrix();
    cv::Mat mat_trans = p_eye2base.toCVMat().col(3).rowRange(0, 3);
    cv::Mat mat_rot_obj_ray = mat_rot * mat_obj_ray;
    float scale = -mat_trans.at<float>(2, 0) / mat_rot_obj_ray.at<float>(2, 0); // s = -t_z / d_z
    cv::Mat mat_position = mat_trans + scale * mat_rot_obj_ray;                // P = t + s·d
    return cv::Point3f(mat_position.at<float>(0, 0), mat_position.at<float>(1, 0), mat_position.at<float>(2, 0));
}
// 球取 bbox 底边中点：pose_estimator.cpp:50
//   cv::Point2f target_uv = cv::Point2f(bbox.x + bbox.width / 2, bbox.y + bbox.height);

// src/brain/src/brain.cpp:1669-1683 —— brain 只用投影结果，并转到场地系
gObj.posToRobot.x = obj.position_projection[0];
gObj.posToRobot.y = obj.position_projection[1];
gObj.range = norm(gObj.posToRobot.x, gObj.posToRobot.y);
gObj.yawToRobot = atan2(gObj.posToRobot.y, gObj.posToRobot.x);
transCoord(gObj.posToRobot.x, gObj.posToRobot.y, 0,
           data->robotPoseToField.x, data->robotPoseToField.y, data->robotPoseToField.theta,
           gObj.posToField.x, gObj.posToField.y, gObj.posToField.z);

// src/brain/include/utils/math.h:80-85 —— 2D 位姿复合（s 在 st 坐标系下 → 世界）
inline void transCoord(const double &xs, const double &ys, const double &thetas,
                       const double &xst, const double &yst, const double &thetast,
                       double &xt, double &yt, double &thetat) {
    thetat = toPInPI(thetas + thetast);
    xt = xst + xs * cos(thetast) - ys * sin(thetast);
    yt = yst + xs * sin(thetast) + ys * cos(thetast);
}
// 里程计 → 场地：brain.cpp:1324-1332  robotPoseToField = transCoord(robotPoseToOdom(×odom_factor), odomToField)
```

### 7.3 踢球决策（StrikerDecide 核心）

```cpp
// src/brain/src/brain_tree.cpp:794-850（节选）
double deltaDir = toPInPI(kickDir - dir_rb_f);                 // 期望踢向 vs 机器人→球方向
bool reachedKickDir = deltaDir * lastDeltaDir <= 0 && fabs(deltaDir) < M_PI / 6 && dt < 100;
reachedKickDir = reachedKickDir || fabs(deltaDir) < 0.1;       // 绕球时“越过”目标方向也算对准
string newDecision;
if (!(iKnowBallPos || tmBallPosReliable)) {
    newDecision = "find";
} else if (brain->config->get_enable_auto_visual_kick() && brain->data->tmImLead &&
           brain->data->tmMyCostRank == 0 && !brain->tree->getEntry<bool>("ball_out") &&
           brain->data->lose_ball == false && brain->data->tmMyCost < 7.0 &&
           ball.range < cfg DistMax(4.0) && ball.range > cfg DistMin(0.2) &&
           fabs(ball.yawToRobot) < cfg Angle(0.8) * 1.3 &&
           ball.posToField.x > L/2 - 14.3 && fabs(ball.posToField.y) < 5 && /* 机器人同理 */ ...) {
    newDecision = "auto_visual_kick";                          // → RLVisionKick（固件 RL 踢）
    brain->data->tmImInVisualKick = true;
} else if (!brain->data->tmImLead) {
    newDecision = "assist";                                    // 非控球者去支援位
} else if (ballRange > chaseRangeThreshold * (lastDecision == "chase" ? 0.9 : 1.0)) {
    newDecision = "chase";                                     // 迟滞防抖
} else if (((angleGoodForKick && !brain->data->isFreekickKickingOff) || reachedKickDir)
           && brain->data->ballDetected && fabs(brain->data->ball.yawToRobot) < M_PI / 2.
           && !avoidKick && ball.range < 1.5) {
    newDecision = (brain->data->kickType == "cross") ? "cross" : "kick"; // → Kick(crabWalk)
    brain->data->isFreekickKickingOff = false;
} else {
    newDecision = "adjust";                                    // 绕球对准 kickDir
}
setOutput("decision_out", newDecision);
// 注：上面 "cfg …" 与 "/* 机器人同理 */" 是对原代码中 config getter 调用的缩写，原文见 811-825 行
```

```cpp
// src/brain/src/brain_tree.cpp:730-751 —— CalcKickDir：射门/传中/解围方向
if (thetal - thetar < crossThreshold && brain->data->ball.posToField.x > fd.circleRadius) {
    brain->data->kickType = "cross";                            // 射门窗口太窄 → 传向点球点附近
    brain->data->kickDir = atan2(-bPos.y, fd.length/2 - fd.penaltyDist/2 - bPos.x);
} else if (brain->isDefensing()) {                              // 对方任意球 → 朝远离本方球门方向
    brain->data->kickType = "block";
    brain->data->kickDir = atan2(bPos.y, bPos.x + fd.length/2);
} else {
    brain->data->kickType = "shoot";                            // 瞄对方球门中心
    brain->data->kickDir = atan2(-bPos.y, fd.length/2 - bPos.x);
    if (brain->data->ball.posToField.x > brain->config->fieldDimensions.length / 2) brain->data->kickDir = 0;
}
```

### 7.4 下发到机器人（RPC 封装）

```cpp
// src/brain/src/robot_client.cpp:10-28, 77-93, 121（节选）
void RobotClient::init(string robot_name) {
    string suffix = robot_name.empty() ? "" : ("/" + robot_name);
    publisher = brain->create_publisher<booster_msgs::msg::RpcReqMsg>("LocoApiTopic" + suffix + "Req", 10);
}
int RobotClient::call(booster_interface::msg::BoosterApiReqMsg msg) {
    auto message = booster_msgs::msg::RpcReqMsg();
    message.uuid = gen_uuid();
    nlohmann::json req_header; req_header["api_id"] = msg.api_id;   // 如 2001=kMove, 2004=kRotateHead
    message.header = req_header.dump();
    message.body = msg.body;                                        // SDK Parameter::ToJson()
    publisher->publish(message);                                    // 只发不收，无返回码
    return 0;
}
int RobotClient::setVelocity(double x, double y, double theta) {
    if (fabs(x) < minx && fabs(x) > 1e-5) x = x > 0 ? minx : -minx; // 小速度抬到 min_v*
    ...
    x = cap(x, brain->config->get_vx_limit(), -brain->config->get_vx_limit()); // 全局限速
    ...
    return call(booster_interface::CreateMoveMsg(x, y, theta));
}
```

---

## 8. 存疑与待实机验证清单

- `/head_pose` 的 base 原点是否在地面、是否包含 IMU 躯干倾角；发布频率；与图像时间戳是否同钟（vision 用接收时刻打戳）。
- StereoNet 图像的实际分辨率和帧率；`vision.image_camera_info_topic` 配置错误的实际影响。
- TRT10 engine 的生成流程；实际推理耗时；Geek 版 K1（非 Jetson，48 TOPS）能否使用 TRT 路径（K1 规格书：Education 为 Orin NX 8GB，Professional 为 AGX Orin 32GB）。
- 固件 `current_planner_index` 各取值（1/2/8/10/20）的含义（`brain_tree.cpp:1443-1470`）。
- VisualKick 默认版本（kV1）与官方推荐 kV2 的差异；ChangeMode(kWalking) 能否正确退出视觉踢。
- LT+A 切入 kSoccer 模式由谁负责（固件或 demo）。【已更正，#38】已查明由 demo 负责：V1604 通过 BT `RunOnce<RobocupWalk>` 调用 `ChangeMode(kSoccer)`。
- launch_ros 对不存在的参数文件（`config_local.yaml`、`~/agents/booster_soccer/brain.yaml`）是跳过还是报错（Humble 上预期告警并跳过）。
- GameController 广播频率；GC 1.0.1 与 HL v12 结构体的兼容性：已按上游 GC 2025.1.1 的序列化代码核实为兼容（688 B），应使用 main/V1604 这类 v12 代码，2026 分支反而收不到 1.0.1 的包【已更正，#37】（1.0.1 本体仍要抓包确认）。【fw1.7 #24】本赛事改用 GC 7.0.0-rc.3（v20），此条只对已废弃的 v1.6 栈有意义。
