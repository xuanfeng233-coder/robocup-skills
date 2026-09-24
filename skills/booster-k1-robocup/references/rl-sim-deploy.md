# 训练 / 仿真 / 部署生态参考（Booster K1）

> ⚠ **本队使用固件 ≥ 1.7 + SDK `d5d8f7a`（`refs/booster_robotics_sdk@fw1.7`，= 主办方 `sdk_release.zip`）+ 主办方 Demo 1.7。** 本文按最新 SDK 1.6.3（`87a9a26`）/ 固件 1.8 撰写；在 1.7 上不同的地方用【fw1.7 #N】标出，完整说明见 `fw1.7-demo-v1.7.md` §4。

> 路径约定：文中所有文件路径均相对于 `refs/`（例如 `booster_gym/envs/T1.yaml` 即 `refs/booster_gym/envs/T1.yaml`），`:N` 表示行号。
> 资料快照：2026-09-24，本地各仓库 HEAD 已通过 GitHub API 核对，与上游最新提交一致。
> 标注说明：**【已验证】**＝读代码或解析文件确认；**【推断】**＝由代码推理得出；**【待验证】**＝资料不足或需要实机/实跑确认；**【外部】**＝本地资料里没有的外部常识。

---

## 0. 先看这几条（TL;DR）

1. **公开仓库里没有 K1 行走/踢球的 RL 训练代码。**
   - `booster_gym` 只提供 T1 的配置（`booster_gym/envs/T1.yaml`，只注册了 `T1`）。
   - `booster_train` 只有 3 个 K1 **BeyondMimic 动作跟踪**任务（打斗、MJ 舞蹈），没有速度跟踪行走、踢球或起身任务。
   - `booster_deploy` 自带一个训练好的 K1 行走策略 `k1_walk.pt`，但**没有配套训练代码**。
2. 同一套部署代码同时跑 sim2sim（MuJoCo）和 sim2real（ROS 2），用的是 `booster_deploy`：`python scripts/deploy.py --task k1_walk --mujoco` 跑仿真，去掉 `--mujoco` 就是跑真机。【fw1.7 #29】booster_deploy 要求固件 ≥ v1.7.2，本队的 1.7.2.0 满足（1.7.0/1.7.1 不满足，先确认小版本）。
3. **版本漂移（重要）**：`booster_assets` 在 2026-08-28 的提交 `38a0ae84b1` 里"unify joint/link names"，把 K1 的名字改成了小写，例如 `left_hip_pitch_joint`、`trunk`。但 `booster_train` 最后一次提交是 2026-04-02，仍然引用旧名字（`Left_Hip_Pitch`、`Trunk`、`left_foot_link`）。结果是：**用 `booster_train` 训练要把 booster_assets 固定在 `508cbee6ca` 这个旧提交；用 `booster_deploy` 跑 MuJoCo 要用 HEAD 版 booster_assets。**
4. 3v3 仿真赛框架（`sim-3v3-simple-framework`、`booster_champion_example`）只做**高层策略**：输入是仿真真值位姿和裁判机 JSON，输出是 `set_velocity` 和 `SoccerKickManager` 这类高层指令。它**不做关节级控制**，所以不能直接用来测自己的 RL 步态。
5. 观测顺序各仓库**不一致**。booster_gym 是 `[gravity, ang_vel, …]`，booster_deploy 的行走策略是 `[ang_vel, gravity, …]`。真机上**没有线速度**（`root_lin_vel_w` 恒为 0），策略观测里不能放 base 线速度。
6. macOS 上跑不了 Isaac Gym 和 Isaac Lab。能在 Mac 上做的是 MuJoCo sim2sim（`booster_deploy --mujoco`、`booster_gym/play_mujoco.py`）和 Booster Studio 虚拟机器人（支持 Apple Silicon）。训练需要 Linux + NVIDIA GPU。

---

## 1. 各仓库定位一览

| 仓库 | 用途 | 依赖 / 仿真器 | K1 支持 | 成熟度 | 最近更新（HEAD） |
|---|---|---|---|---|---|
| `booster_gym` | T1 行走 RL 全流程：train → play → play_mujoco → export → deploy | Isaac Gym Preview 4、Python 3.8、PyTorch 2.0、CUDA 11.8、MuJoCo（`booster_gym/README.md`） | **否**。只有 T1（`envs/T1.yaml`、`envs/t1.py`）。README 说 K1 请用新流程 | 可用但已被新流程替代，代码简洁，适合改造 | 2025-12-23 "Add new RL pipeline info to README" |
| `booster_train` | Isaac Lab RL 任务。目前只有 BeyondMimic 动作跟踪 | Isaac Lab 2.2 + Isaac Sim 5.0、rsl_rl、booster_assets（`booster_train/README.md`） | **是**（只有动作跟踪）：`Booster-K1-Fight_001-v0`、`Booster-K1-MJ_Dance_002-v0`、`Booster-K1-MJ_Dance_004-v0` | 早期（6 个提交），任务很少；与 HEAD booster_assets 命名不兼容 | 2026-04-02 "update robot joint config for K1" |
| `booster_deploy` | 部署框架，同一套 Policy 代码跑 MuJoCo 和真机 | Python 3.10+、torch、mujoco、onnxruntime、evdev；真机需要 ROS 2 + `booster_interface`（`booster_deploy/README.md`、`requirements.txt`） | **是**：任务 `k1_walk`、`k1_mj2`、`k1_fight`，配置在 `booster_deploy/robots/k1.py` | 最活跃，2026-09 发布新版本（K1 行走、ONNX 支持） | 2026-09-13 "Add a locomotion for K1 … Add ONNX support" |
| `booster_assets` | 机器人模型（URDF/MJCF）、重定向后的动作 CSV，以及 `BOOSTER_ASSETS_DIR` 辅助包 | 纯数据 + setuptools | **是**：K1_22dof urdf/xml、K1_22dof_parallel.xml、K1_locomotion.urdf | 持续更新；2026-08 改过命名 | 2026-09-03 "add t2 with gripper and hand" |
| `sim-3v3-simple-framework` | Booster Champion 3v3 仿真赛的**简化版**策略模板（状态机） | `booster_agent_framework`、`boosteros`、ROS 2、`py_trees==2.4.0`；运行在 Booster Studio 虚拟机器人里 | agent.toml 里 `models = ["Booster T1","Booster K1"]` | 模板级，默认策略比较朴素 | 2026-07-20 "readme update" |
| `booster_champion_example` | 同一赛事的**完整版**示例（行为树、Playbook、Role） | 同上 | 同上 | 结构完整，文档齐全（`docs/developer_protocol.md`、`docs/bt_structure.md`） | 2026-07-17 "enter 3v3 match situation in default" |

---

## 2. booster_gym（Isaac Gym，T1 行走）

### 2.1 环境定义与 K1 支持

- 任务注册方式：`booster_gym/envs/__init__.py` 里只有 `from envs.t1 import T1`。`utils/runner.py:27` 用 `eval(cfg["basic"]["task"])` 找类，所以**任务名 = 类名 = `envs/<task>.yaml` 的文件名**。
- 机器人资源：`booster_gym/resources/T1/T1_locomotion.urdf`（训练用）和 `T1_locomotion.xml`（MuJoCo 用），12 个腿部 DOF。
- **K1**：仓库里没有 K1 的 yaml、类或资源。移植方法见 2.9。

配置文件 `booster_gym/envs/T1.yaml` 的主要段落：

| 段 | 关键值 |
|---|---|
| `env` | `num_envs: 4096`，`num_observations: 47`，`num_privileged_obs: 14`，`num_actions: 12` |
| `sim` | `dt: 0.002`，physx TGS，`substeps: 1` |
| `control` | `stiffness {Hip:200, Knee:200, Ankle:50}`，`damping {Hip:5, Knee:5, Ankle:1}`，`action_scale: 1.`，`decimation: 10`（策略频率 50 Hz） |
| `asset` | `file: resources/T1/T1_locomotion.urdf`，`base_name: Trunk`，`foot_names: [left_foot_link, right_foot_link]`，`default_dof_drive_mode: 3`（effort，PD 在 Python 里算） |
| `init_state` | `pos z=0.72`，`default_joint_angles {Hip_Pitch:-0.2, Knee_Pitch:0.4, Ankle_Pitch:-0.25, default:0}` |
| `commands` | vx、vy ∈ [-1,1] m/s，vyaw ∈ [-1,1] rad/s，`gait_frequency: [1.0, 2.0]` Hz，`still_proportion: 0.1`，每 8–12 s 重采样一次，`curriculum: false` |
| `terrain` | `trimesh`；比例 `[plane, slope, random, discrete] = [0, 0, 0.5, 0.5]` |

### 2.2 观测空间（47 维）与特权观测（14 维）

来源：`booster_gym/envs/t1.py:574-603`，与 `play_mujoco.py:106-116`、`deploy/utils/policy.py:47-62` 一致。

| 下标 | 内容 | 缩放 / 噪声 |
|---|---|---|
| 0:3 | `projected_gravity`（机体系重力方向） | ×1.0，噪声 σ=0.01 |
| 3:6 | `base_ang_vel`（机体系角速度） | ×1.0，噪声 σ=0.1 |
| 6:9 | 指令 `vx, vy, vyaw` | ×1.0 |
| 9 | `cos(2π·gait_process)`（gait_frequency=0 时置 0） | — |
| 10 | `sin(2π·gait_process)` | — |
| 11:23 | `dof_pos - default_dof_pos`（12 腿关节） | ×1.0，σ=0.01 |
| 23:35 | `dof_vel` | ×0.1，σ=0.1 |
| 35:47 | 上一步 `actions` | — |

特权观测（只给 critic）：`base_mass_scaled`(4) + `base_lin_vel`(3) + `base_height`(1) + `push_force`(3) + `push_torque`(3) = 14（`t1.py:593-602`）。

### 2.3 动作空间与 PD

- `dof_targets = default_dof_pos + action_scale * clip(action, -1, 1)`（`t1.py:439-440`）。
- PD 力矩在 Python 里按 `decimation` 个子步逐步计算：`τ = Kp(target − q) − Kd·q̇ − friction`，再按 URDF effort 限幅。每个 env 在 `[0, decimation)` 内随机一个**动作延迟子步**（`t1.py:316, 444-450`）。
- 网络结构：actor 为 `47→256→128→128→12`（ELU），critic 为 `(47+14)→256→256→128→1`，`logstd` 初值 -2（`utils/model.py`）。

### 2.4 奖励项与权重

来源 `booster_gym/envs/T1.yaml:251-278`，函数实现在 `envs/t1.py:606-730`。非零权重的项会**乘以 dt**（`t1.py:285`）。`only_positive_rewards: true`。

| 奖励项 | 权重 | 含义 |
|---|---|---|
| `survival` | 0.25 | 存活常数 |
| `tracking_lin_vel_x` / `_y` | 1.0 / 1.0 | exp(-err²/0.25)，用滤波后的线速度 |
| `tracking_ang_vel` | 0.5 | yaw 角速度跟踪 |
| `base_height` | -20 | (h − 0.68)² |
| `orientation` | -5 | 重力投影 xy 分量平方 |
| `torques` | -2e-4 | Σ τ² |
| `torque_tiredness` | -1e-2 | Σ (τ/τ_max)² |
| `power` | -2e-3 | Σ max(τ·q̇, 0) |
| `lin_vel_z` | -2 | 竖直速度 |
| `ang_vel_xy` | -0.2 | roll/pitch 角速度 |
| `dof_vel` / `dof_acc` / `root_acc` | -1e-4 / -1e-7 / -1e-4 | 平滑项 |
| `action_rate` | -1 | 相邻两帧动作差 |
| `dof_pos_limits` | -1 | 超出软限位 |
| `collision` | -1 | `penalize_contacts_on` 列出的 body 发生接触 |
| `feet_slip` | -0.1 | 触地时脚的速度 |
| `feet_yaw_diff` / `feet_yaw_mean` | -1 / -1 | 两脚 yaw 一致、与躯干 yaw 对齐 |
| `feet_roll` | -0.1 | 脚掌 roll |
| `feet_distance` | -1 | 两脚横向距离 < 0.2 时惩罚 |
| `feet_swing` | +3 | 按步态相位奖励摆动腿离地（`swing_period: 0.2`） |
| `dof_vel_limits` / `torque_limits` / `feet_vel_z` | 0 | 关闭 |

终止条件：躯干高度 < 0.45、速度平方和 > 50、超时 30 s（`t1.py:551-558`）。

### 2.5 域随机化与噪声（`T1.yaml:147-249`）

| 类别 | 项目与范围 |
|---|---|
| 初始状态 | 关节 +N(0, 0.05)；xy 位置 U(-1, 1)；初速度 N(0, 0.1)；yaw 在 0~2π 随机 |
| 扰动 | 每 2 s 给一次随机速度（线速度 N(0, 0.1)、角速度 N(0, 0.02)）；每 5 s 施加持续 1 s 的推力（力 N(0, 10) N、力矩 N(0, 2)） |
| 执行器 | Kp、Kd ×U(0.95, 1.05)；关节摩擦 U(0, 2)；动作延迟 0~9 个 physics 子步 |
| 接触 | 足底摩擦 U(0.1, 2.0)、compliance U(0.5, 1.5)、restitution U(0.1, 0.9) |
| 质量 | base 质心偏移 U(±0.1)、质量 ×U(0.8, 1.2)；其他 link 质心 U(±0.005)、质量 ×U(0.98, 1.02) |
| 观测噪声 | gravity σ=0.01、ang_vel σ=0.1、dof_pos σ=0.01、dof_vel σ=0.1 |

PPO 参数（`T1.yaml:17-37`、`utils/runner.py`）：horizon 24、mini_epochs 20、lr 1e-5（按 KL 自适应，目标 0.01）、γ 0.995、λ 0.95、`bound_coef` 1.0、`entropy_coef` -0.01。
注意：`symmetric_coef: 10.` 在代码里**没有被使用**（全仓 grep 无引用）【已验证】。

### 2.6 命令速查

```bash
# 训练（日志与 checkpoint 写入 logs/<date-time>/，默认开启 wandb）
python train.py --task=T1 [--headless] [--num_envs=4096] [--sim_device=cuda:0] [--rl_device=cuda:0]
tensorboard --logdir logs
# 在 Isaac Gym 中回放（录像写入 videos/）
python play.py --task=T1 --checkpoint=-1
# 在 MuJoCo 中交叉验证：终端输入 "vx vy vyaw" 改指令。不依赖 isaacgym
python play_mujoco.py --task=T1 --checkpoint=-1
# 导出 TorchScript：只导出 actor，输出与 .pth 同名的 .pt。本仓库不导出 ONNX
python export_model.py --task=T1 --checkpoint=-1
```

`--checkpoint=-1` 的含义是取 `logs/**/*.pth` 中修改时间最新的文件（`export_model.py:20-21`）。

### 2.7 MuJoCo sim2sim 的实现要点（`booster_gym/play_mujoco.py`）

- MJCF 的 timestep 被覆盖为 `cfg.sim.dt=0.002`，每 `decimation=10` 步推理一次。
- 关节顺序直接取 `qpos[7:]`、`qvel[6:]`，默认角和 PD 参数按 **actuator 名子串**匹配。这要求 MJCF 的 `nu` 等于 12，并且 actuator 顺序与 Isaac Gym 的 DOF 顺序一致。
- 四元数：MuJoCo 的 `framequat` 传感器输出 wxyz，代码用 `[1,2,3,0]` 重排成 xyzw 再计算 gravity（`play_mujoco.py:102`）。
- 传感器名必须是 `orientation` 和 `angular-velocity`（K1 的 MJCF 也用这两个名字）【已验证】。

### 2.8 真机部署（T1 版，`booster_gym/deploy/`）

1. 安装：`pip install -r deploy/requirements.txt`（torch、evdev、sshkeyboard），再按飞书文档编译 **Booster Robotics SDK 的 Python 绑定**（`deploy/README.md`）。
2. 机器人切到 **PREP 模式**，平稳站在地面上。
3. 运行 `python deploy.py --config=T1.yaml [--net=127.0.0.1]`。按手柄/键盘 `b` 进入 Custom 模式，按 `r` 启动 RL 步态。键盘用 `w/s/a/d/q/e` 调速度，空格清零（`deploy/utils/remote_control_service.py`）。
4. 退出前先切回 PREP 模式。程序检测到 IMU 的 |roll| 或 |pitch| > 1.0 rad 会停止运行，并切到 `kDamping`（`deploy/deploy.py:77-79, 235`）。

实现细节（`deploy/deploy.py`、`deploy/utils/policy.py`、`deploy/configs/T1.yaml`）：
- 推理 50 Hz，下发 500 Hz。下发前做一阶低通：`filtered = 0.8·filtered + 0.2·target`。
- 全身用 23 关节（`B1JointCnt`）顺序，策略只取 `[11:]`（腿部），头、手臂、腰保持 `default_qpos`。
- 并联踝关节（下标 `[15,16,21,22]`）走**力矩通道**：`q=当前值, kp=0, tau=clip(Kp·(target−q))`，避免串并联转换带来的非线性。
- 真机 PD 用的是 `T1.yaml:common.stiffness/damping`，与训练值一致（腿 200/5，踝 50/3）。进入 Custom 模式时使用单独的 `prepare` 段（更硬的 PD + 预备姿态）。
- 手柄按钮提示与按钮映射不一致：提示写 "Press button B"，实际 Logitech 映射是 `BTN_C`。以实测为准【待验证】。

### 2.9 把 booster_gym 移植到 K1 的检查清单【推断，均待实跑验证】

| 项目 | T1 原值 | K1 需要改成（依据） |
|---|---|---|
| 任务类 | `envs/t1.py: class T1` | 新建 `envs/k1.py: class K1(T1): pass`，在 `envs/__init__.py` 里 import，再新建 `envs/K1.yaml` |
| URDF | `resources/T1/T1_locomotion.urdf` | `booster_assets/robots/K1/K1_locomotion.urdf`（头和手臂是 fixed，腿 12 个 revolute）【已验证】 |
| 关节名匹配 | stiffness/damping/default 用子串 `"Hip"`、`"Knee"`、`"Ankle"`、`"Hip_Pitch"` 匹配 | HEAD 版 URDF 是小写（`left_hip_pitch_joint`），匹配是**区分大小写的子串**（`t1.py:74-80`），所以要改成 `"hip"`、`"knee"`、`"ankle"`、`"hip_pitch"` 等。如果改用旧版（`508cbee6ca`）资源，原来的键可以继续用 |
| base / 脚 body | `Trunk`；`left_foot_link` / `right_foot_link` | HEAD 版：`trunk`，`left_ankle_roll_link` / `right_ankle_roll_link`。旧版：`Trunk` / `left_foot_link` |
| `penalize_contacts_on` | T1 的 link 名片段 | 改成 K1 的 link 名片段（HEAD 版小写） |
| `feet_edge_pos`、`base_height_target`、`init_state.pos`、`terminate_height` | 0.68 / 0.72 / 0.45 | K1 更矮：booster_train 的 K1 初始高度是 0.57（`booster_train/.../assets/robots/booster.py:37`），其余需要在仿真里实测 |
| PD / 默认姿态 | 200/5、50/1；hip -0.2、knee 0.4、ankle -0.25 | 可参考已经能在真机上走的 `k1_walk` 配置：腿 Kp 100、踝 65；Kd 2（踝 1）；hip -0.15、knee 0.3、ankle -0.15（`booster_deploy/tasks/locomotion/robots/k1/__init__.py`） |
| 力矩上限 | URDF 的 effort | URDF：hip pitch 68、roll 43、yaw 38.3、knee 112、ankle 38.3。`k1_walk` 部署时的限幅要保守得多：30/20/15/35/24/15。建议训练时也按部署限幅截断 |
| MuJoCo 文件 | `T1_locomotion.xml`（nu=12） | 仓库**没有** K1 的 12 DoF MJCF。`K1_22dof.xml` 的 nu=22，`play_mujoco.py` 需要改成只取腿部下标 10:22，头和手臂用 PD 保持 |
| 真机部署 | `deploy/`，23 关节，腿部从下标 11 开始，并联踝下标 [15,16,21,22] | K1 是 22 关节（`kJointCntK1=22`，见 `booster_robotics_sdk/include/booster/robot/b1/b1_api_const.hpp:214`），腿部从下标 10 开始，踝在 [14,15,20,21]。`B1JointCnt` 在 Python 绑定里是否有 K1 版本【待验证】。**建议直接改用 booster_deploy 部署**，见第 4 节 |

---

## 3. booster_train（Isaac Lab）

### 3.1 任务列表（全部是 K1 BeyondMimic 动作跟踪）

| Task ID | 动作文件（`{BOOSTER_ASSETS_DIR}/motions/K1/…`） | 定义位置 | 备注 |
|---|---|---|---|
| `Booster-K1-Fight_001-v0` / `…-v0-Play` | `k1_fight_001.npz` | `booster_train/source/booster_train/booster_train/tasks/manager_based/beyond_mimic/robots/k1/fight_001/` | 额外加了手、脚、躯干的跟踪奖励（权重 5–30）；推力更大 |
| `Booster-K1-MJ_Dance_002-v0` / `…-v0-Play` | `k1_mj2_seg1.npz` | `…/k1/mj_dance_002/` | 基线配置 |
| `Booster-K1-MJ_Dance_004-v0` | `k1_mj4.npz` | `…/k1/mj_dance_004/` | 没有 `-Play` 注册；booster_assets 里也**没有 k1_mj4 的 CSV** |

没有行走、踢球、起身任务。`BOOSTER_T1_CFG` 已经定义好了（`assets/robots/booster.py:122`），但没有任何任务用到它。

### 3.2 K1 机器人配置（`booster_train/.../assets/robots/booster.py`、`actuator.py`）

- URDF 路径是 `{BOOSTER_ASSETS_DIR}/robots/K1/K1_22dof.urdf`，初始高度 0.57，初始手臂 `Left/Right_Shoulder_Roll = ∓1.3`。
- 执行器用 `BoosterDelayedPDActuator`：延迟 2–8 个 physics 步；带 T-N 曲线限幅，即速度超过拐点后力矩按线性下降。
- 刚度和阻尼由电机转动惯量推出：`Kp = J·(2π f)²`，`Kd = 2ζ·J·(2π f)`。

| 关节组 | 电机型号 | effort / vel limit / armature | f, ζ |
|---|---|---|---|
| Hip_Pitch | E6408 | 68 / 14.66 / 0.0478 | 4 Hz, 1.5 |
| Hip_Roll | E4315 | 76 / 12.57 / 0.0340 | 4, 1.5 |
| Hip_Yaw | E4310 | 38.3 / 17.59 / 0.0283 | 4, 1.5 |
| Knee_Pitch | E6416 | 112 / 12.57 / 0.0956 | 4, 1.0 |
| Ankle_Pitch/Roll | E4310 + `BoosterK1AnkleParaWrapperCfg`（armature×2） | 38.3 / 17.59 / 0.0565 | 4, 1.5 |
| 手臂（4×2） | R14 | 14 / 33.51 / 0.001 | 默认 10 Hz, 2.0 |
| 头 | HT4438 | 6 / 7.85 / 0.001 | 默认 |

动作缩放：`K1_ACTION_SCALE[j] = 0.25 · effort / Kp`（`booster.py:105-116`）。

### 3.3 BeyondMimic MDP（`…/beyond_mimic/robots/k1/mj_dance_002/tracking_env_cfg.py`）

- 时间设置：`sim.dt=0.005`，`decimation=4`（策略频率 50 Hz），`episode_length_s=10`。
- 实际使用的是 `…WoStateEstimation` 配置，**去掉了 `motion_anchor_pos_b` 和 `base_lin_vel`**（`env_cfg.py:37-42`），因为真机没有线速度和全局位置。
- 策略观测维度 = command（参考关节位置 22 + 速度 22）+ `motion_anchor_ori_b`(6) + `base_ang_vel`(3) + `joint_pos_rel`(22) + `joint_vel_rel`(22) + `last_action`(22) = **119**。解析 `booster_deploy/tasks/beyond_mimic/robots/k1/models/*.pt` 得到首层权重形状 119×512，吻合【已验证】。
- 奖励：全局锚点位置、姿态各 0.5；body 相对位置、姿态、线速度、角速度各 1.0；`action_rate_l2` -0.1；`joint_limit` -10；`undesired_contacts` -0.1。
- 域随机化：摩擦 U(0.3, 0.6)，默认关节角 ±0.01，躯干质心偏移，每 1–3 s 推一次（速度推扰）。
- 终止条件：锚点 z 误差 > 0.25、姿态误差 > 0.8、末端 z 误差 > 0.25。
- PPO（`agents/rsl_rl_ppo_cfg.py`）：`[512,256,128]` ELU，`empirical_normalization=True`，lr 1e-3（自适应），γ 0.99，每个 env 采 24 步。K1 fight 任务 `max_iterations=50000`。

### 3.4 命令

```bash
# 前提：已安装 Isaac Lab（官方推荐 conda），并 pip install -e booster_assets
python -m pip install -e source/booster_train
# CSV -> NPZ：在 Isaac Sim 中按 FK 回放，写出 body_pos_w、body_quat_w 等
python scripts/csv_to_npz.py --headless --input_file=<ASSETS>/motions/K1/<M>.csv --input_fps=<FPS> \
       --output_name=<ASSETS>/motions/K1/<M>.npz [--frame_range S E] [--output_fps 50]
python scripts/list_envs.py                      # 列出 id 中包含 "Booster-" 的任务
python scripts/rsl_rl/train.py --task=Booster-K1-MJ_Dance_002-v0 --headless --device cuda:0
python scripts/rsl_rl/play.py  --task=Booster-K1-MJ_Dance_002-v0-Play --checkpoint=<.../model_XXXX.pt>
# play.py 会同时导出 logs/rsl_rl/<exp>/<run>/exported/<exp>_<run>.pt 和 .onnx（play.py:165-173）
```

NPZ 的键：`fps, joint_pos, joint_vel, body_pos_w, body_quat_w, body_lin_vel_w, body_ang_vel_w, joint_names, body_names`（`scripts/csv_to_npz.py:237-246`）。

### 3.5 兼容性警告【已验证】

- `booster_train` 用的名字是 `Left_Hip_Pitch` 这类正则、`Trunk`、`Head_2`、`Left_Arm_2`、`left_foot_link` 等（`booster.py`、`k1/*/env_cfg.py:18-34`）。这些名字**只存在于 booster_assets 的 `508cbee6ca`（2026-03-12）及更早版本**。
- HEAD 版 booster_assets 有三处不同：
  - URDF 改成小写（`left_hip_pitch_joint`、`trunk`、`left_ankle_roll_link`）；
  - `motions.py` 里的 `K1_JOINT_NAMES` 也改成小写，而且写的是 `left_shoulder_pitch_joint`，URDF 里实际是 `aaleft_shoulder_pitch_joint`，两者不一致；
  - CSV 增加了**表头行**，文件名去掉了 `_30fps`/`_50fps` 后缀。
- 后果【推断】：`csv_to_npz.py` 里 `np.loadtxt` 没有 `skiprows`，遇到表头会报错；`find_joints` 按名字找关节也会失败。
- 做法：训练时执行 `cd booster_assets && git checkout 508cbee6ca`（旧版 fight CSV 名为 `k1_fight_001_30fps.csv`，对应 `--input_fps 30`）；部署时再切回 HEAD。
- 官方文档 `booster_docs/developer-guide__open-source__booster-assets.md` 描述的还是旧版（带 `K1_22dof-ZED.urdf`、大写关节名、`_30fps` 文件名）。

---

## 4. booster_deploy（sim2sim / sim2real 统一框架）

### 4.1 架构

```
scripts/deploy.py --task X [--mujoco] [--device cpu] [--exit-mode walking|damping]
  ├─ pkgutil.walk_packages 自动 import tasks/**，各任务在 __init__ 中 register_task(name, ControllerCfg)
  ├─ --mujoco → MujocoController(cfg).run()                      # booster_deploy/controllers/mujoco_controller.py
  └─ 否则   → BoosterRobotPortal(cfg).run()                       # booster_deploy/controllers/booster_robot_controller.py
                 └─ fork 一个推理进程 → BoosterRobotController（BaseController 子类）
BaseController.run 的循环:  update_state() → policy_step() = Policy.inference() → ctrl_step(dof_targets)
```

| 抽象 | 文件 | 职责 |
|---|---|---|
| `ControllerCfg`（configclass） | `booster_deploy/controllers/controller_cfg.py` | `policy_dt=0.02`、`robot: RobotCfg`、`vel_command`、`policy: PolicyCfg`、`mujoco: MujocoControllerCfg(decimation=10, init_pos, …)`、`booster: BoosterRobotControllerCfg(exit_mode)` |
| `RobotCfg` | 同上；实例见 `booster_deploy/robots/k1.py` | `joint_names`（真机顺序）、`sim_joint_names`（Isaac Lab 顺序）、`joint_stiffness/damping`、`default_joint_pos`、`effort_limit`、`mjcf_path`、`prepare_state`、`prepare_mode` |
| `RobotData` | `controllers/base_controller.py` | `joint_pos/vel`（真机顺序）、`root_quat_w`（wxyz）、`root_ang_vel_b`、`root_lin_vel_b`；自动生成 `real2sim_joint_indexes` 和 `sim2real_joint_indexes` |
| `Policy` | `controllers/base_controller.py` | 需要实现 `reset()` 和 `inference() -> dof_targets`（真机顺序、绝对角度）。`self.task_path` 是任务所在目录 |
| 推理后端 | `utils/policy_runner.py` | 按后缀自动选择：`.pt/.jit/.torchscript` 用 TorchScript，`.onnx` 用 onnxruntime（CPU） |

### 4.2 同一套代码在仿真与真机上的差异

| 项 | MuJoCo（`mujoco_controller.py`） | 真机（`booster_robot_controller.py`） |
|---|---|---|
| 状态来源 | `qpos[7:]`、`qvel[6:]`，base 的四元数和角速度直接取自 `qpos`/`qvel` | ROS 2 `/low_state`：`motor_state_serial` 的 q、dq、tau_est，加上 IMU 的 rpy→quat 和 gyro |
| 线速度 / 位置 | 有（`qvel[:3]`）。MuJoCo 自由关节的线速度是**世界系**，代码却当作机体系使用【外部/待验证】 | **恒为 0**（`:231-236`） |
| 执行 | Python 里算 PD：`clip(Kp(q*−q) − Kd·q̇, ±effort_limit)`，每次推理跑 `decimation` 个物理步（`:221-245`） | 发布 `joint_ctrl`（`LowCmd`，`CMD_TYPE_SERIAL`），逐关节下发 `q/kp/kd`，由**电机端 PD** 执行（`:757-764`）。频率为 `policy_dt` |
| 指令输入 | 终端 stdin 输入 "vx vy vyaw" | GameSir 手柄（evdev）、Booster 遥控器（`/remote_controller_state`）或键盘 |
| 模型 | `mjcf_path`（K1 用 `K1_22dof.xml`，串联踝） | 真机踝关节是并联结构。README 要求按 `Kd = 2ζ·J_eq·(2π f_n)` 计算电机侧 Kd，不要照搬训练时的 Kd |

### 4.3 K1 配置（`booster_deploy/robots/k1.py`）

- `joint_names`（真机、SDK、MJCF 顺序，共 22 个）：`aahead_yaw, aahead_pitch, aaleft_shoulder_pitch, left_shoulder_roll, left_elbow_pitch, left_elbow_yaw, aaright_shoulder_pitch, right_shoulder_roll, right_elbow_pitch, right_elbow_yaw, left_hip_pitch, left_hip_roll, left_hip_yaw, left_knee_pitch, left_ankle_pitch, left_ankle_roll, right_…(同左)`，每个名字后缀 `_joint`。
- `sim_joint_names`：Isaac Lab 解析顺序（BFS），开头是 `aahead_yaw, aaleft_shoulder_pitch, aaright_shoulder_pitch, left_hip_pitch, right_hip_pitch, aahead_pitch, …`。
- `prepare_mode="walking"`；`prepare_state` 的 Kp：腿 350/180/250，手臂 20–50。
- `mjcf_path="{BOOSTER_ASSETS_DIR}/robots/K1/K1_22dof.xml"`。

### 4.4 已注册任务（`python scripts/deploy.py --list`）

| 任务 | 类型 | 模型 | 说明 |
|---|---|---|---|
| `k1_walk` | 速度跟踪行走 | `tasks/locomotion/robots/k1/models/k1_walk.pt` | vx ∈ [-0.3, 1.6]，vy ±0.3，vyaw ±1.8 |
| `k1_mj2` / `k1_fight` | BeyondMimic | `tasks/beyond_mimic/robots/k1/models/*.pt` + `motions/*.npz` | MuJoCo 中会显示参考动作"幽灵" |
| `t1_walk`、`t1_motion_tracking`、`t2_walk`、`t2_dance` | — | — | 其他机型 |

**`k1_walk` 策略规格**（`tasks/locomotion/locomotion.py:113-210`，并解析 `k1_walk.pt` 得到首层 690×512、末层 128×20，归一化器为恒等变换【已验证】）：
- 单帧观测 69 维：`[base_ang_vel(3), projected_gravity(3), cmd(3), dof_pos−default(20), dof_vel×0.1(20), last_action(20)]`。20 个关节是除头以外的全部关节，按 Isaac Lab 顺序排列（`policy_joint_names`）。
- 历史：10 帧，第一帧用 `repeat` 填充，展平后是 690 维。
- 输出 20 维：`target = default + 0.25·a`，再做 `action_filter=0.8` 的 lerp 平滑；`right_elbow_pitch` 固定减 0.2（`arm_action_fix`）。
- 没有步态相位输入。

### 4.5 接入自己的策略（最小步骤）

1. 新建 `tasks/my_k1_skill/__init__.py`。
2. 写 `class MyPolicy(Policy)`：
   - 在 `inference()` 里从 `self.controller.robot.data` 读状态，**按训练时的顺序和缩放**拼观测；
   - 用 `create_policy_runner(path, device)` 推理；
   - 返回**真机关节顺序**的绝对目标角。
3. 写 `@configclass class MyPolicyCfg(PolicyCfg): constructor = MyPolicy; checkpoint_path = "models/xxx.onnx"`，以及 `class MyCfg(ControllerCfg): robot = K1_CFG.replace(joint_stiffness=…, default_joint_pos=…); policy = MyPolicyCfg(); vel_command = VelocityCommandCfg(...)`。
4. 注册：`register_task("my_k1_skill", MyCfg())`；运行 `python scripts/deploy.py --list` 确认已出现。
5. 把 booster_gym 训出的策略搬过来时：需要照 `booster_gym/deploy/utils/policy.py` 自己写一个 Policy（47 维观测、gait 相位、腿部下标 10:22）。`LocomotionPolicy` **不能直接用**，因为它的观测顺序、历史帧和 action_scale 都不同。
6. Isaac Lab 训练的策略可以参考 `LocomotionPolicy` 和 `BeyondMimicPolicy` 的写法，用 `real2sim_joint_indexes` 做关节映射。

### 4.6 真机运行命令与安全流程

```bash
# 在开发机上先跑 sim2sim
python -m pip install -e <booster_assets>; python -m pip install -r requirements.txt
python scripts/deploy.py --task k1_walk --mujoco
# 把项目拷到机器人上，SSH 登录后执行
source .venv/bin/activate
source /opt/booster/BoosterRos2Interface/install/setup.bash
python scripts/deploy.py --task k1_walk [--exit-mode damping]
```

| 阶段 | 行为（`booster_robot_controller.py:394-680`） |
|---|---|
| 按 `X`（或键盘 `x`） | 1) 等到第一帧 `/low_state`。2) walking 准备模式下先检查姿态：`projected_gravity.z > -0.5` 时拒绝执行并切到 damping。3) 等到 `/joint_ctrl` 有订阅者后，下发一帧保持当前姿态的指令（用 `prepare_state` 的 kp/kd），再通过 RPC 切到 Custom。4) walking 模式立即运行 `k1_walk`，速度指令置零；standing 模式用约 1 s（500×2 ms）插值到 `prepare_state.joint_pos` |
| 按 `A`（或键盘 `r`） | 切换到 `--task` 指定的策略，并放开速度指令 |
| 运行中 | 行走策略在 `projected_gravity.z > -0.5` 时 stop（`locomotion.py:123-131`）；BeyondMimic 在姿态与参考偏差过大时 stop；推理进程异常退出也会 stop |
| 退出（Ctrl+C 或 stop） | 切到 `exit_mode`，默认 walking；发生安全中止时强制切 damping |

安全建议（`booster_docs/product-manual__k1__getting-started__safety-warnings.md`、`…__modes.md`）：
- Custom 模式下所有关节都由用户代码控制，全程要用吊架保护。
- Custom 只能从 PREP 或 DAMP 进入，手册写的是也只能切回这两个模式。

固件要求说法不一致：README 表格写 **≥ v1.7.2**，同一 README 正文写 ≥ v1.4，官方文档写 ≥ v1.4。`exit_mode="walking"` 从 Custom 直接切到 Walking 与手册描述冲突，是否支持取决于固件【待验证】。建议使用最新固件（changelog 已到 v1.8.0）。【fw1.7 #29】1.7.2 上 `exit_mode="walking"`（Custom→Walking）先在吊架上实测，默认用 `damping`；1.7 进入 Custom 不会自动保持站立。

---

## 5. booster_assets

### 5.1 K1 模型文件（HEAD `3c2dfa9`）

| 文件 | 内容 | 用途 |
|---|---|---|
| `robots/K1/K1_22dof.urdf` | 22 个 revolute 关节，外加 `head_realsense_rgb`、`head_booster_stereo_rgb` 两个 fixed 相机 link | Isaac Lab 训练（booster_train 需要旧版） |
| `robots/K1/K1_locomotion.urdf` | 头和手臂的 10 个关节为 fixed，只留腿部 12 个 revolute | 适合 booster_gym 式的腿部 RL |
| `robots/K1/K1_22dof.xml` | MJCF，timestep 0.001，22 个 `motor` actuator，site `imu`，传感器 `orientation`（framequat）、`angular-velocity`（gyro） | booster_deploy 的 MuJoCo sim2sim |
| `robots/K1/K1_22dof_parallel.xml` | 踝关节是真实的**并联连杆**：`*_ankle_drive_a/b_joint` 电机 + `equality connect` 闭链 | 更逼真的 sim2sim。deploy 的 `qpos[7:]` 索引需要改写后才能用【推断】 |
| `robots/K1/meshes/*.STL` | 网格文件 | — |
| USD | **无**。Isaac Lab 通过 `UrdfFileCfg` 在运行时转换 | — |

HEAD 版 URDF 的关节限位【已验证】：hip_pitch [-2.958, 2.226]、hip_roll L [-0.375, 1.536]、knee [0, 2.321]、ankle_pitch [-0.87, 0.345]、ankle_roll ±0.345。

### 5.2 关节命名与顺序（至少有 4 套命名）

| 来源 | 示例 | 顺序 |
|---|---|---|
| booster_assets HEAD 版 URDF/MJCF、booster_deploy | `aaleft_shoulder_pitch_joint`、`left_hip_pitch_joint` | 真机顺序：头 2 → 左臂 4 → 右臂 4 → 左腿 6 → 右腿 6 |
| booster_assets 旧版（`508cbee6ca`）、booster_train | `ALeft_Shoulder_Pitch`、`Left_Hip_Pitch`、link `Trunk` | 同上 |
| boosteros SDK（Agent 与仿真赛使用） | `AAHead_Yaw`、`Head_Pitch`、`ALeft_Shoulder_Pitch`（`sim-3v3-simple-framework/docs/BoosterOS 开发者接口文档 - V1.0.md` 中 list_joints 的输出示例） | 同上 |
| C++ SDK `JointIndexK1` | `kHeadYaw=0 … kCrankUpLeft=14, kCrankDownLeft=15 …` | 并联布局下 14/15 是踝部的两个曲柄电机，不是 pitch/roll（`booster_docs/developer-guide__cpp__low-level-topics.md`） |
| Isaac Lab 解析顺序 | 见 `booster_deploy/robots/k1.py: sim_joint_names` | BFS 顺序 |

名字前缀里的 `AA`/`A` 推测是为了控制仿真器解析时的排序【推断】。

### 5.3 motions 数据

- 格式（`booster_assets/README.md`）：每行一帧；前 7 列是 root `x, y, z, qx, qy, qz, qw`（**xyzw**），后面是 22 个关节角（rad），顺序见 `src/booster_assets/motions.py: K1_JOINT_NAMES`。当前文件是 50 Hz，HEAD 版带表头。
- 现有文件：`motions/K1/k1_fight_001.csv`（706 帧）、`k1_mj2_seg1.csv`（1261 帧）。
- 用途：BeyondMimic **动作跟踪（模仿学习 + RL）** 的参考轨迹。流程是 CSV → `booster_train/scripts/csv_to_npz.py`（在 Isaac Sim 里做 FK，补出 body 位姿和速度）→ 训练 → 部署时由 `booster_deploy/utils/motion_loader.py` 读取 NPZ。
- 仓库**不提供**动作重定向工具，只提供已经重定向好的数据。
- Python 辅助包：`pip install -e .` 之后 `from booster_assets import BOOSTER_ASSETS_DIR`。`setup.cfg` 声明了 console script `booster_assets.cli:main`，但仓库里没有 `cli.py`，调用 `booster-assets` 命令会失败【已验证文件缺失】。

---

## 6. sim-3v3-simple-framework 与 booster_champion_example

### 6.1 是什么，跑在什么平台上

- **赛事**：`champion.booster.tech` 的页面标题是 "Booster Champion 仿真赛第一季 · 3v3 足球锦标赛"（WebFetch），钛媒体 2026-07-10 发布了"Booster 冠军之夜 仿真赛第一季：3v3 足球锦标赛"招募文章。赛程、奖项、提交方式的细节在页面和文章正文里都读不到（正文是图片，飞书文档需要登录）【待验证】。
- **两仓库的关系**：`booster_champion_example` 是官方完整示例，README 称 "3v3 simulation soccer Agent example"。`sim-3v3-simple-framework` 是它的简化版，README 称 "Simplified Version of Booster Champion 3v3 Soccer Tournament agent"，并注明策略需要在仿真里充分调试后才能用于比赛。
- **平台**：两者都是 **Booster Agent**。它们运行在 **Booster Studio** 创建的虚拟机器人里（`booster_champion_example/README.md` 的 Runtime Environment 一节）。
  - `.booster-studio/project.json` 内容为 `{"sceneId":"football3v3","projectMode":"soccer-match"}`。
  - Booster Studio 支持 Windows 10/11、Ubuntu 20+、macOS Apple Silicon（`booster_docs/developer-guide__agent-development__intro.md`）。
  - 第三方项目 `Samge0/booster-match-runner` 的描述是：虚拟机器人跑在 Docker 容器里，Studio 点击 Run 时注入 `football3v3_runner`，比赛控制 HTTP 接口在 38383 端口【外部/待验证】。
  - 底层用的是哪种物理引擎，资料中没有说明【待验证】。
- **机型**：`agent.toml` 里 `models = ["Booster T1", "Booster K1"]`。场地是 14×9 m，与 M-Field 一致（`sim-3v3-simple-framework/src/framework/types.py: ADULT_FIELD_DIMENSIONS`）。

### 6.2 agent.toml / build.toml 字段含义

来源：`booster_docs/developer-guide__agent-development__quick-start.md` 与两仓库的实际文件。

| 文件.字段 | 仓库取值 | 含义 |
|---|---|---|
| `agent.toml: id` | `com.booster.champion_example` / `com.example.lqinternalmatch` | Agent 唯一 ID（推荐反向域名写法） |
| `version`、`name`、`logo`、`description` | `1.1.0`、…、`/res/logo.png` | 元数据；`version` 决定 `.agent` 包的文件名 |
| `entry` | `src/main.py:SoccerSimAgent` | 入口类，**直接基类必须是 `booster_agent_framework.AgentBase`**。simple 框架因此写成 `class SoccerSimAgent(SoccerAgentMixin, AgentBase)`（`src/framework/agent.py:1-12`） |
| `debuggable` | `true` | 以 debug 方式启动时会尝试开启 Python 调试服务器 |
| `[requirements] min_api_level` | `10700` | 最低系统 API level（对应固件 1.7） |
| `[requirements] models` | T1、K1 | 支持的机型 |
| `build.toml: [python.dependencies] common` | `["py_trees==2.4.0"]` | 所有平台都要安装的 pip 依赖；也可以按平台分别写 `sim_x86_64`、`real_jetson` 等 |
| `[python] pip_repos`、`obfuscation` | 注释掉 / `false` | pip 源；轻度源码混淆 |
| `[platform] supports` | `sim_x86_64, sim_aarch64, real_jetson` | 目标平台：x86 或 ARM 虚拟机器人、Jetson 真机（还可以选 `real_qcom`） |
| `[sign]` | 注释掉 | 签名 keystore，也可以通过环境变量 `AGENT_SIGN_KEYSTORE*` 提供 |

### 6.3 数据接口

来源：`booster_champion_example/docs/developer_protocol.md`、`sim-3v3-simple-framework/src/framework/ros_source.py`、`config.py`。

- 身份通过环境变量传入：
  - `SOCCER_TEAM_ID`：team1=1，team2=2；
  - `SOCCER_ROBOT_NAMES`：team1 是 `robot1,robot2,robot3`，team2 是 `robot4..6`；
  - simple 框架还额外读取 `SOCCER_OPPONENT_ROBOT_NAMES`、`SOCCER_CONTROL_HZ`（默认 30）、`SOCCER_GAME_CONTROLLER_TOPIC`；
  - 规则：不要把队号或机器人名写死在代码里。
- 真值话题（`geometry_msgs/Pose2D`，**已换算成本队视角坐标**：己方球门在 x=-7，进攻方向为 +x）：
  - `/team{N}/robot{1..6}/soccer/sim/ground_truth/robot_pose`
  - `/team{N}/soccer/sim/ground_truth/ball`（只用 x、y）
- 裁判机：`/soccer/game_controller`（`std_msgs/String`，内容是 GameController v19 格式的 JSON）。主要字段有 `state`、`stopped`、`setPlay`、`kickingTeam`（255 表示无）、`secondaryTime`、`teams[].players[].penalty`。超过 2 s 没收到新消息就停下机器人。

### 6.4 控制接口（boosteros 高层 SDK）

来源：`sim-3v3-simple-framework/src/framework/robot_backend.py`、`developer_protocol.md` 第 4 节。

| 调用 | 说明 |
|---|---|
| `BoosterRobot(virtual_robot_name=robot_name, enable_tf_listener=False, timeout=10.0)` | 每个球员创建一个实例 |
| `set_gait("soccer")` + `set_mode("walk")` | 进入足球步态（这是**固件内置步态**） |
| `set_velocity(vx, vy, vyaw)` | 底盘速度控制 |
| `SoccerKickManager(robot).start()` / `update_command(direction, power∈[1,10])` / `update_ball(x, y)` / `stop()` | 自动踢球，参数都是**机体坐标系**。与 `set_velocity` 共用底盘通道，两者互斥 |
| `get_mode()`、`get_fall_down_state()`、`get_up()` | 状态轮询；起身有约 1 s 节流 |

### 6.5 决策代码结构对比

| | sim-3v3-simple-framework | booster_champion_example |
|---|---|---|
| 主循环 | `SoccerRuntime` 以 30 Hz 调用 `SoccerSimAgent.play(context, players, store)`（`src/framework/runtime.py`） | `SoccerTeamRuntime` 驱动 `py_trees` 行为树（`src/runtime.py`） |
| 决策 | `src/main.py` 里的 `Phase` 状态机（NORMAL、OUR/OPP_KICKOFF、OUR/OPP_SET_PLAY、READY、STOPPED），各阶段对应一个 `_act_*` 函数：离球最近者 attack，离己方球门最近者 guard，其余 support | `src/play/playbook.py` 的 `Playbook.assign_roles`，加上 `src/play/default_roles.py` 里的 Chaser、Supporter、Defender、Goalkeeper 等 Role |
| 动作原语 | `src/player.py`：`walk_to`（A* 加局部避障）、`kick`、`attack`、`guard`、`support`、`ensure_ready` | `src/tactics/`：`motion`、`navigation`、`targeting`、`kick_hysteresis`、`ready_stance` |
| 调参 | `src/param.py`（踢球力度、增益、避障半径等） | `soccer_framework/config.py: SoccerStrategyTuning` |
| 可视化 | `framework/debugdraw.py`：发布 ROS MarkerArray | `telemetry.py`：输出 JSONL 结构化日志 |

### 6.6 本地运行与提交

步骤（`sim-3v3-simple-framework/README.md`）：
1. 下载 Booster Studio；
2. 在 Studio 中打开项目；
3. 等待环境准备完成；
4. 选择一个 Virtual Robot；
5. 点击 "Activate, build, deploy and run agent"。

构建产物在 `build/xxx.agent`，可以一键安装到虚拟机器人，也可以分发 `.agent` 文件（`agent-development__quick-start.md` Step 6）。比赛的正式提交通道和规则【待验证】，需要登录飞书文档 `booster.feishu.cn/wiki/RwYkw3004iV39hk6uJOcu2ctnah` 或查看 champion.booster.tech 页面正文。

### 6.7 能否作为真机策略的仿真测试平台？

- **不能用来测关节级 RL 策略**【推断】。框架只调用固件内置的 `soccer` 步态和 `SoccerKickManager`；输入是仿真**真值**，没有视觉感知和定位。
- boosteros 本身有 `set_mode("custom")` + `set_joints(...)` 接口（BoosterOS 文档 2.5 节）。理论上可以在虚拟机器人上下发关节指令，但频率、延迟和物理保真度都没有说明【待验证】。
- 它**适合**验证高层策略，比如角色分配、走位、定位球，而且和真机的高层 SDK 接口一致。
- 移植到真机时，要把 `RosContextSource`（真值）替换成真机的感知和定位来源（例如 `robocup_demo`，见 `booster_docs/developer-guide__open-source__robocup-demo.md`）【推断】。`build.toml` 已经声明了 `real_jetson` 平台。
- 固件 v1.7 默认不带 boosteros，需要 SSH 上去执行 `pip install boosteros`；v1.8 起内置（`agent-development__quick-start.md`）。【fw1.7 #30】本队固件 1.7：用前先 `pip install boosteros`；Demo 1.7 的 `start.sh` 会禁用 `booster-agent-manager`，Agent 与 Demo 不要同时跑。

### 6.8 "Agent 开发体系"与足球的关系

- Agent 是运行在机器人上的"技能包"，带 App UI 组件和手柄快捷键（`booster_docs/developer-guide__agent-development__intro.md`）。
- 官方内置了 **Soccer Agent**，手柄组合 `L2+R2+B` 进入，可以追球踢球（`product-manual__k1__basic-operations__agents.md`）。
- 仿真赛的参赛代码本身就是一个 Agent（`AgentBase` + `agent.toml`/`build.toml`），所以**Agent 体系正是足球仿真赛的提交载体**。
- Agent API 本身（UI、参数、存储、快捷键）与运动控制无关。运动控制走 boosteros。

---

## 7. 推荐开发路径：自研步态 / 踢球技能

### 路径 0（比赛最省事）：直接用固件内置能力

- 行走：`set_gait("soccer")` + `set_mode("walk")` + `set_velocity`。
- 踢球：`SoccerKickManager`。
- 把精力放在策略层（第 6 节）。C++ 侧对应的接口是 `booster_docs/developer-guide__booster-os-python-sdk__booster-robot-client-reference__automatic-soccer-kick-manager__*.md`。
-

### 路径 A：自研 RL 步态（速度跟踪）

| 步骤 | 做什么 | 命令 / 关键文件 |
|---|---|---|
| A1 环境 | Linux + NVIDIA GPU。选 Isaac Gym Preview 4（Python 3.8）或 Isaac Lab 2.2 / Isaac Sim 5.0 | `booster_gym/README.md`、`booster_train/README.md` |
| A2 训练（二选一） | **(a) 改造 booster_gym**：按 2.9 的清单新建 `envs/K1.yaml` 和 `envs/k1.py`，URDF 用 `K1_locomotion.urdf`。**(b) 在 booster_train 里新写 Isaac Lab velocity 任务**：机器人用 `BOOSTER_K1_CFG`（注意 3.5 的命名问题），任务结构可以参考 Isaac Lab 自带的 locomotion velocity 任务【外部】 | (a) `python train.py --task=K1 --headless`；(b) `python scripts/rsl_rl/train.py --task=<你的ID> --headless` |
| A3 设计原则 | actor 观测**不要放**线速度和全局位置；加历史帧或步态相位。PD 和力矩上限向真机部署值看齐（Kp 100/65、effort 30/20/15/35/24/15）。加执行器延迟和推扰 | 参考 `booster_deploy/tasks/locomotion/robots/k1/__init__.py` |
| A4 同仿真回放 | 在 Isaac 中回放 | `python play.py --task=K1 --checkpoint=-1` 或 `scripts/rsl_rl/play.py`（Isaac Lab 会同时导出 .pt/.onnx） |
| A5 导出 | booster_gym：`export_model.py` 只导出 jit。Isaac Lab：`exported/*.onnx` | — |
| A6 sim2sim | 在 booster_deploy 里写自己的 Policy 和 Cfg（4.5），把模型放进 `tasks/<t>/models/`，运行 `python scripts/deploy.py --task <t> --mujoco`。可以先对照 `k1_walk` 的表现当基线。进阶时换成 `K1_22dof_parallel.xml` 做并联踝测试 | `booster_deploy/controllers/mujoco_controller.py`，`MujocoControllerCfg.log_states` 可以记录状态轨迹 |
| A7 真机 | 吊架保护 + 最新固件。拷贝项目到机器人，`source /opt/booster/BoosterRos2Interface/install/setup.bash`，运行 `python scripts/deploy.py --task <t> --exit-mode damping`。按 X 进入准备（默认先跑 `k1_walk` 站稳），按 A 切到自己的策略 | 4.6 节 |

### 路径 B：踢球技能（资料内最直接的路线：动作跟踪）

| 步骤 | 做什么 | 命令 / 文件 |
|---|---|---|
| B1 参考动作 | 自备一段 K1 踢球参考动作 CSV（重定向工具需自己准备，仓库不提供），格式见 5.3 | 放到 `booster_assets/motions/K1/k1_kick.csv` |
| B2 CSV→NPZ | 用旧版资源（`508cbee6ca`）或修正命名后运行 | `python scripts/csv_to_npz.py --headless --input_file=… --input_fps=50 --output_name=…/k1_kick.npz` |
| B3 注册任务 | 复制 `…/beyond_mimic/robots/k1/mj_dance_002/` 为 `kick_001/`，改 `motion_file` 和 `gym.register` 的 id（`Booster-K1-Kick_001-v0`），`ppo_cfg.experiment_name` 也要改 | `…/robots/k1/kick_001/{__init__,env_cfg,ppo_cfg,tracking_env_cfg}.py` |
| B4 训练与导出 | — | `train.py --task=Booster-K1-Kick_001-v0 --headless`；`play.py --task=…-v0-Play --checkpoint=…` |
| B5 sim2sim / 真机 | 仿照 `tasks/beyond_mimic/robots/k1/__init__.py` 新建 `K1KickControllerCfg`（`motion_path`、`checkpoint_path`；`stop_at_motion_end=True`）并 `register_task` | `python scripts/deploy.py --task k1_kick --mujoco`，之后上真机 |
| B6（备选） | 固件侧执行：C++ `B1LocoClient::LoadCustomTrainedTraj` / `ActivateCustomTrainedTraj`，传入轨迹 ONNX + 控制模型 ONNX，关节顺序选 `JointOrder::kIsaacLab` 或 `kMuJoCo`。K1 需要固件 ≥ v1.5.0.9 | `booster_docs/developer-guide__cpp__rpc__motion.md` "Custom Trained Trajectories" 一节 |

注意：动作跟踪学的是"固定一段踢球动作"。**踢不同位置的球**需要自己设计目标条件任务（例如把球的相对位置加入观测，加上击球奖励）。仓库里没有现成实现【推断】。

---

## 8. 常见坑

| # | 坑 | 说明与对策 | 依据 |
|---|---|---|---|
| 1 | Isaac Gym 版本 | 只支持 Preview 4 + Python 3.8；需要把 `$CONDA_PREFIX/lib` 加进 `LD_LIBRARY_PATH`，否则找不到 `libpython3.8`。Isaac Gym 只能在 Linux + NVIDIA 上跑，且已停止维护【外部】 | `booster_gym/README.md` |
| 2 | Isaac Lab 版本 | booster_train 只在 **Isaac Lab 2.2 / Isaac Sim 5.0** 上测试过；`play.py` 兼容新旧 rsl_rl（`alg.policy` 与 `alg.actor_critic`）。Isaac Sim 5.0 需要 RTX 显卡，支持 Linux 和 Windows【外部/待验证】 | `booster_train/README.md`、`scripts/rsl_rl/play.py:150-153` |
| 3 | GPU 与规模 | 默认 `num_envs=4096`、`cuda:0`。显存不够时用 `--num_envs` 调小 | `booster_gym/envs/T1.yaml:11`、`tracking_env_cfg.py:299` |
| 4 | macOS 无法训练 | Mac 上能做的：(1) `booster_deploy --mujoco`，MuJoCo 路径不 import rclpy 或 evdev【已验证】，但 `requirements.txt` 里的 `evdev` 是 Linux 专用包，需要手动跳过【外部/待验证】；(2) `booster_gym/play_mujoco.py` 和 `export_model.py`，这两个不 import isaacgym【已验证】；(3) Booster Studio 虚拟机器人。macOS 上 `mujoco.viewer.launch_passive` 需要用 `mjpython` 启动【外部/待验证】。训练用云端 Linux GPU | 同左 |
| 5 | 观测顺序不一致 | booster_gym 是 `[gravity, ang_vel, cmd, cos, sin, q, dq×0.1, a]`；deploy 的行走策略是 `[ang_vel, gravity, cmd, q, dq×0.1, a]×10`；BeyondMimic 是 `[cmd(q_ref, dq_ref), ori6, ang_vel, q, dq, a]`。**部署时必须逐项对照训练代码**，包括缩放（dof_vel 在 T1 deploy 是 1.0，在 K1 是 0.1）和 clip | 2.2、4.4、3.3 节 |
| 6 | 真机没有线速度和位置 | `root_lin_vel_w` 和 `root_pos_w` 在真机上恒为 0。线速度只能放进 critic 的特权观测 | `booster_robot_controller.py:231-236`；`env_cfg.py` 的 `WoStateEstimation` |
| 7 | 关节顺序映射 | 真机、SDK、MJCF 是一种顺序，Isaac Lab 是 BFS 顺序，booster_gym 按 Isaac Gym 的 DOF 顺序。deploy 用 `sim_joint_names` 或 `policy_joint_names` 做映射。C++ 的 `CustomModel` 必须按**训练导出时的顺序**选 `kIsaacLab` 或 `kMuJoCo` | `booster_deploy/robots/k1.py`、`booster_docs/developer-guide__cpp__rpc__motion.md` |
| 8 | 关节命名漂移 | booster_assets 在 2026-08-28 统一改成小写，booster_train 仍然是旧名；boosteros 又是另一套名字（`AAHead_Yaw`）；官方文档停留在旧版。不同工具链要固定各自需要的 assets 版本 | 3.5、5.2 节 |
| 9 | 四元数约定 | Isaac Gym 和 booster_assets CSV 用 **xyzw**；MuJoCo `qpos`、传感器以及 Isaac Lab 用 **wxyz**；真机 IMU 给的是 rpy | `play_mujoco.py:67,102`、`csv_to_npz.py`（转换成 wxyz）、`booster_robot_controller.py` |
| 10 | 并联踝与 Kd | 真机的 K1、T1 踝关节是并联结构。booster_gym 的 T1 部署对踝关节走力矩通道；booster_deploy 要求按电机侧惯量重新计算 Kd。MuJoCo 默认模型是串联踝，会高估 sim2sim 的成功率 | `booster_gym/deploy/deploy.py:182-190`、`booster_deploy/README.md` |
| 11 | 力矩限幅差异 | K1 的 URDF effort（例如膝 112 Nm）远大于 `k1_walk` 部署时的限幅（膝 35 Nm）。训练时按 URDF 限幅，到真机容易力矩饱和 | `K1_22dof.urdf`、`tasks/locomotion/robots/k1/__init__.py` |
| 12 | 控制频率与滤波 | 训练是 50 Hz 策略频率；booster_gym 部署以 500 Hz 下发并带 0.8/0.2 低通；booster_deploy 以 50 Hz 下发、在电机端做 PD，K1 行走还有 `action_filter=0.8`。训练时最好把同样的滤波和延迟加进环境 | 各 deploy 代码 |
| 13 | booster_gym 的 T1 模型 ≠ booster_deploy 的 `t1_walk` | 两者观测不同，前者有 gait 相位、没有历史帧，所以不能互换 | 2.2、4.4 节 |
| 14 | 固件与模式切换 | Custom 只能从 PREP 或 DAMP 进入；固件版本要求在各资料里说法不一（≥1.4 / ≥1.7.2 / Agent 需要 ≥1.7）；v1.7 需要手动安装 boosteros | 4.6、6.7 节 |
| 15 | CSV 表头 | HEAD 版 CSV 带表头，`csv_to_npz.py` 的 `np.loadtxt` 不会跳过【推断】。用 `--frame_range 2 N` 或去掉表头 | `booster_assets/motions/K1/*.csv` 第 1 行 |
| 16 | 仿真赛坐标系 | `/teamN` 话题已经是本队视角，**不要再按 team_id 镜像一次** | `booster_champion_example/docs/developer_protocol.md` §2 |

---

## 9. 存疑 / 待验证清单

1. booster_train 配合 HEAD 版 booster_assets 能否运行（推断会报 joint/body 名不匹配）；固定在 `508cbee6ca` 后能否完整跑通。
2. `k1_walk.pt` 的训练框架和奖励设计没有公开。
3. booster_gym 的 Python SDK 在 K1 上用什么关节数常量（`B1JointCnt` 是 23）。
4. booster_deploy 的 `exit_mode="walking"`（从 Custom 直接切到 Walking）需要哪个固件版本。
5. Booster Studio 虚拟机器人用的物理引擎，以及能否通过 boosteros 的 `set_joints` 以足够高的频率做关节级控制。
6. Booster Champion 仿真赛的正式提交方式、规则、赛程（飞书文档需要登录，官网正文读不到）。
7. `evdev` 在 macOS 上能否安装；macOS 上 MuJoCo 被动 viewer 是否需要 `mjpython`。
8. MuJoCo controller 把世界系线速度当作机体系使用的影响（K1 行走和 BeyondMimic 的观测都不用线速度，影响应该有限）。
