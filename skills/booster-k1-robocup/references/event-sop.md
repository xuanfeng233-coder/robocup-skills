# 本赛事官方流程：部署 → 上场 → 裁判机（主办方 3v3 技术分享 + 代码核对）

> 赛事：**2026 全球数字贸易创新大赛（具身智能机器人挑战赛）足球赛项 3v3**。
> 来源：主办方讲义 `2026 全球数字贸易创新大赛（具身智能机器人挑战赛）足球赛项 3v3 技术分享.pdf`（仓库根目录，33 页，2026-09 发放，下称 `PDF`，`PDF p.N` 为页码）。讲义自己声明：**IP、队伍编号、文件名都是示例，正式操作以现场发放的软件包、裁判机地址、队伍编号和场地要求为准**。
> 代码核对对象：`D17` = `refs/K1_5v5_demo_1.7`（`K1_5v5_demo_1.7.zip` 解压，无 .git）；`GC7` = `refs/robocup_league/GameController@v7.0.0-rc.3`（HSL GameController tag `v7.0.0-rc.3`，`a6bb00a`，2026-06-23）。核对日期 2026-09-24。
> 标注：【PDF】= 讲义原文；【已核实】= 读 D17/GC7 代码确认；⚠ = 讲义与代码不一致或讲义没写，以本文为准并尽快现场确认。
> 固件、SDK、Demo 与公开代码的版本关系见 `fw1.7-demo-v1.7.md`；规则基线见 `robocup-rules.md`（HSL 2026，GC7 的参数与之一致）。

## 0. 结论速览（先读这一节）

1. **技术栈**【PDF p.2】：固件 **≥ 1.7**（1.8 也可以）；Demo = `K1_5v5_demo_1.7.zip`；SDK = `sdk_release.zip`（= 公开 SDK `d5d8f7a`，见 `fw1.7-demo-v1.7.md`）；裁判机 = **HSL GameController 7.0.0-rc.3**（`game_controller-7.0.0-rc.3-4-x86_64-unknown-linux-gnu`）；比赛形式 3v3。
2. **协议匹配**【已核实】：GC7 发 struct **v20**（158 B）。D17 的 `game_controller_node` **按包长同时接受 HL v12（688 B）和 v20（158 B）**（`src/game_controller/src/game_controller_node.cpp:110-145`），回包按收到的版本自动切换：v20 时发 `RGrt` **v4**（32 B，`fallen` 取 0/1，带位姿和球）（`src/brain/src/brain_communication.cpp:65-114`）。旧结论「2026 分支只收 v19/v20、GC 1.0.1 发 v12」只适用于 v1.6 栈。
3. ⚠ **队内通信会耗尽 GC 的消息额度，导致本场比分清零**【已核实】。D17 每台机器人每 **100 ms** 广播一条队内消息（`src/brain/include/brain_communication.h:65`），3 台就是约 30 条/s。GC7 给每队的额度是 **12000 条/场**（`config/*/params.yaml` 的 `messagesPerTeam`），只在 READY/SET/PLAYING 计数（`game_controller_core/src/actions/team_message.rs:27-33`）。额度用完后再收到一条，GC 就把 `illegal_communication` 置位并**把本队比分设为 0，之后进球也不再加分**（同文件 `:18-20`；`actions/goal.rs:19-26`）。按 30 条/s 算，约 400 s（不到 7 分钟）就会用完。**上场前必须降频**：把间隔改到 ≥ 400 ms（3 台 × 2.5 Hz × 约 1400 s ≈ 10500 条），或者按 GC 包里的 `message_budget` 动态限速；另一种做法是 `enable_com: False`，但会失去协同。讲义没有提这件事（`issues.md` T10）。
4. ⚠ **`/opt/booster/vision.yaml` 在运行时不会被读取**【已核实】。`scripts/start.sh:33` 启动 vision 时没有传 `vision_config_path`，vision 和 brain 都读包内安装目录 `install/vision/share/vision/config/vision.yaml`（`src/vision/launch/launch.py:9-20`、`src/brain/launch/launch.py:13-30`）。讲义 p.18「`/opt/booster/vision.yaml` 优先于 Demo 目录配置」的说法是错的，p.20「1.7 正常启动不会自动读取」才是对的。**改视觉参数 = 改 `src/vision/config/vision.yaml`（或 `vision_local.yaml`）→ `./scripts/build.sh` → 重启**。
5. ⚠ **每队的 `team_id` 必须不同，而且要和裁判机里选的队号一致**。D17 默认 `team_id: 70`，这个队号在 GC7 队伍表里是 `B-Team`（讲义截图用的就是它）。如果两支队都用 70，GC 里没法选出两支不同的队，队内通信端口（10000+队号）也会串包。队号和 GC 队伍表的对应关系要问主办方（`issues.md` C11）。
6. ⚠ **GC 组别决定每队人数**【已核实】：`Large/Middle - Foundation` 的 `playersPerTeam` 是 **3**，`Large/Middle - Advanced` 是 **5**（`config/*/params.yaml:3`）。讲义截图选的是 `Large - Advanced`（每队 5 人），讲义只说「按本次要求选择」。GC 默认 **1 号是守门员**（`game_controller_core/src/lib.rs:62`），D17 在通信不完整时沿用 GC 的守门员（`config.yaml:106` `goalie_fallback_use_gc_goalie`）→ **守门员配成 `player_id: 1`**。
7. ⚠ **开球后 10 s 的「假 SET」**【已核实】：GC7 的 `delayAfterPlaying` 为 10 s。进入 PLAYING 后的最多 10 s 内，发给机器人的仍是之前的 SET 状态（GC7 `README.md` Network Communication 一节）。D17 没有哨声检测，所以每次开球机器人都会原地多站最多 10 s。裁判机启动页 `Testing → No Delay` 可以关掉这个延迟，要问主办方是否勾选（`issues.md` C12）。
8. ⚠ **`scripts/start.sh` 的副作用**【已核实】：`sudo pkill -9 python3`（杀掉**所有** python3 进程）；`sudo systemctl disable --now booster-agent-manager.service`（**永久禁用**固件的 Agent 管理服务）；mask 掉 apt 自动更新；`jetson_clocks`；`systemctl --user disable robocup_game_assist.service`（`start.sh:9-19`）。自己的 Python 程序不要和 Demo 同时跑。赛后如果要用 App 或 Agent，要手动 `sudo systemctl enable --now booster-agent-manager.service`。
9. ⚠ **讲义里有两处路径写错**：p.18 `~/Workspace/K1_5v5_Demo_1.7/...`（大写 D）和 p.18 `~/Workspace/K1-5v5_Demo/...`。解压后的实际目录是 **`~/Workspace/K1_5v5_demo_1.7`**（小写 d、下划线）。Linux 区分大小写，照抄会报「没有那个文件」。
10. **裁判机 IP 要改两处，而且两处都必须和裁判机实际广播用的网卡 IP 一致**：`src/brain/config/config.yaml:193` 的 `game_control_ip`（回包目的地址），和 `src/game_controller/launch/launch.py:21-26` 的白名单。D17 默认白名单是**开启**的，名单里只有 `172.169.80.24`；不改的话，所有 GC 包都会被丢弃，日志里会出现 `not in ip white list, ignore it`。改完都要重新 `build.sh`。

## 1. 版本基线【PDF p.2】

| 项目 | 本次基线 | 说明 |
|---|---|---|
| 机器人固件 | 1.7 及以上（讲义明确 1.8 也可以） | 低于 1.7 时先升级（手机 App 连机器人可以升级，也可以用发放的 `.run` 包，见 §5） |
| Demo | `K1_5v5_demo_1.7.zip`（目录 `K1_5v5_demo_1.7/`） | 包名是 5v5，**本次按 3v3 配置**，只启用 3 台 |
| SDK | `sdk_release.zip` | 只在新机器人、刷机后 SDK 缺失，或编译报 SDK 版本错误时安装 |
| 裁判机 | 2026 版 GameController 7.0.0-rc.3 | 在 Ubuntu x86_64 电脑上运行 |
| 比赛形式 | 3v3 | 每队 3 台，角色和站位按比赛规则与策略设置 |

## 2. 全流程与放行标准【PDF p.2, p.21】

1. 确认场地安全，准备机器人、电脑（最好是 Linux）、网线（或带网口的扩展坞）、路由器、足球和软件包（放在同一目录，**先核对文件名，别用旧版 Demo 或旧裁判机包**）。
2. 连接机器人：电脑配有线静态 IP，再给机器人接入比赛局域网（§4）。
3. 检查或安装固件与 SDK（§5）。
4. 上传 Demo，逐台配置 3 台机器人（§6）。
5. 编译、启动 Demo，看日志确认各节点正常（§6.6）。
6. 把机器人放到场边：进入足球模式并完成定位后，再启动比赛策略（§7）。
7. 裁判机控制比赛状态；比赛结束后停止程序、下场、关机或换电（§8、§9）。

**放行标准**【PDF p.21】：三个日志都符合预期、3 台机器人参数互不冲突、裁判机地址一致、电量充足。**任何一项不满足，都不进入上场步骤。**

## 3. 模式、按键与安全【PDF p.2-3, p.22】

### 3.1 安全规则
- 进入 WALK 前先进入 PREP，并在平地上站稳。**机器人运动时，以及处于 WALK 的任何时候，都不能把它抬起来**。
- 运动范围内不能有人、线缆或障碍物。
- 升级、重启、换电、换网时，机器人可能失去支撑力，必须先放倒或挂上可靠的支撑。
- 摔倒、动作异常或无法接管时：**先保证人员安全**，再进入阻尼并停止程序。
- 搬运、换电或处理异常的顺序：**先停止比赛策略 → 扶稳机器人 → 再按 F1 进入 DAMP**。不要在没人扶的时候直接进 DAMP。

### 3.2 模式与本体按键

| 模式 | 作用 | 现场要求 |
|---|---|---|
| DAMP 阻尼 | 关节有阻力，但不主动保持站姿 | 关机、搬运、处理异常时用，需要支撑 |
| PREP 准备 | 进入并保持站立姿态 | 进入 WALK 前必须先在 PREP 下站稳 |
| WALK 行走 | 可以行走、转向、转头 | 上场操作和足球模式的前置状态 |

| 本体按键（肩背部） | 作用 | 用法 |
|---|---|---|
| 电源键 | 开机/关机 | 长按约 3 s。开机后保持机器人静止，等启动提示音；关机前先退出策略、进入安全状态 |
| STAND | 进入 PREP | 启动 Demo 前、把机器人从地上扶起后、进入 WALK 前使用 |
| WALK | 进入 WALK | 在 PREP 下站稳后再按 |
| F1 | 默认进入 DAMP | 机器人会软下来，必须先扶稳或放倒 |

### 3.3 手柄（Xbox 键名；Booster 手柄上 LT=L2、RT=R2）

| 功能 | 按键 | 前置条件 | 代码中的实际行为（D17） |
|---|---|---|---|
| 进入阻尼 | LT+Back | 机器人处于可以安全切换的状态 | 固件处理 |
| 进入准备 | LT+Start | 有支撑，或者可以安全站立 | 固件处理 |
| 进入行走 | RT+A | 已进入 PREP | 固件处理 |
| 进入足球模式并定位 | **LT+A** | Demo 已启动，机器人处于 WALK | `control_state=2`，并清除 `odom_calibrated`（`src/brain/src/brain.cpp` `joystickCallback`）；BT 分支里 `RunOnce<RobocupWalk>` 调 `ChangeMode(kSoccer)` + `VisualKick(false)`（`behavior_trees/game.xml:26-33`，`src/brain/src/robot_client.cpp:159-167`），然后扫场、跟球、入场定位 |
| 启动自动比赛策略 | **LT+B** | 已经按过 LT+A 并定位成功 | `control_state=3`，之后按 GC 状态行动 |
| 退出 AI 控制（人工接管） | **LT+X** | 需要人工接管时 | `control_state=1`，速度清零、头回正；退出后机器人**可能继续执行 AI 的最后一条运动指令，轻推摇杆可以打断** |
| （讲义未列）切换角色 | LT+Y | — | striker ↔ goal_keeper 互换，**比赛中不要误按** |
| （讲义未列）在线调参 | LT+方向键 上/下、左/右 | — | `vxFactor` ±0.01、`yawOffset` ±0.01（只在内存里改，重启后失效） |
| （讲义未列）人工覆盖 | 任一摇杆 > 0.1 | — | `go_manual=true`，AI 暂停 |
| （讲义未列）辅助追球/踢球 | LB / RB | — | `assist_chase` / `assist_kick` |

- ⚠ D17 的 `game.xml:15` 在启动时就执行 `control_state=3`（即 LT+B 状态）。这时还没有切到 kSoccer（只有 LT+A 分支会切）。没收到 GC 包时 `gc_game_state` 为空，机器人不会动。**讲义要求的「先 LT+A、再 LT+B」不能省**：跳过 LT+A 就是在 WALK 模式下踢比赛。
- 如果机器人一直在转头、没法稳定跟球，说明视觉或定位还没准备好，要退出并回到 §6 检查【PDF p.22】。

## 4. 网络【PDF p.4-11】

| 步骤 | 做法 | 要点 |
|---|---|---|
| 电脑有线静态 IP | Windows：设置 → 网络和 Internet → 以太网 → IP 分配「编辑」→ 手动 + IPv4 开；Ubuntu：设置 → 网络 → 有线齿轮 → IPv4 → 手动 | 地址 `192.168.10.x`（x ≠ 102，例如 `.123`/`.110`），掩码 `255.255.255.0`，网关留空。改完后有线口不能上网，连完机器人可以改回自动 |
| SSH | `ssh booster@192.168.10.102`（密码 `<机器人当前密码，请向队内获取>`） | 机器人有线 IP 固定为 `192.168.10.102` |
| 连比赛 Wi-Fi | `sudo nmtui` → Activate a connection → 在 **Wi-Fi** 栏选**和裁判机同一个** SSID → 输密码 | **极客版联网界面不同，一定要选 `Wi-Fi (wlan0)`** |
| 记录无线 IP | 退出 nmtui 后运行 `ifconfig`，记下 wlan0 的 IP | 之后启动、配置、看日志优先走无线 SSH，避免机器人运动时网线干扰 |

比赛网络关系（`PDF p.11` 图 2）：操作电脑（SSH 上传、配置、看日志）、裁判机电脑（广播比赛状态）、3 台 K1（接收裁判机信息）都接在**同一台比赛路由器的同一局域网**。**机器人配置里的裁判机 IP 必须是裁判机实际用于比赛广播的那块网卡的 IPv4**（可能是有线，也可能是无线）。裁判机换电脑或换网卡后，3 台机器人都要同步更新。

- D17 的 `configs/fastdds.xml` 把 interfaceWhiteList 写死为 `127.0.0.1/192.168.10.101/192.168.10.102`，但 `start.sh` 用的是 `/opt/booster/BoosterRos2/fastdds_profile_udp_only.xml`（`start.sh:23`），只有 `start_brain.sh`/`start_game_controller.sh`/`assist.sh`/`chase.sh`/`calibrate.sh` 会引用 `configs/fastdds.xml`。用这些脚本时要改白名单，否则机器人走无线 IP 时 DDS 不通。GC 包和队内通信走原生 UDP socket，不受 DDS 白名单影响。

## 5. 固件与 SDK【PDF p.11-13】

```bash
# 每台都要检查，结果必须是 1.7 及以上；低于 1.7 时先升级，再部署 Demo
cat /opt/booster/version.txt

# 升级（开发机上执行）：固件包 3.26 GB
scp 1.7.2.0-dev-yunlong-1-7-2026-06-01-hM193-00464-2026-08-18.22.04.aarch64.single.run booster@192.168.10.102:~/Workspace/
# 以下在机器人上执行
cd ~/Workspace
chmod +x 1.7.2.0-dev-yunlong-*.single.run        # ls 时文件名显示为绿色即可
sudo ./1.7.2.0-dev-yunlong-*.single.run          # 需要联网；升级期间运控会关闭，机器人必须有可靠支撑
cat /opt/booster/version.txt                      # 升级后再核对一次
```

- 固件包是 **dev 构建**（文件名里有 `dev-yunlong`，2026-08-18 构建，版本 1.7.2.0），Makeself 格式。升级前后必须知道的几点（详见 `fw1.7-demo-v1.7.md` §2.1）：
  - **必须联网**（安装脚本会 `apt update` 和 `pip install`，失败直接退出）；解压需要 `/tmp` 有约 6 GB 空间；可以先 `sh <包>.run --check` 只做 MD5 校验。
  - 电量 > 50%，机器人处于 DAMP/PREP 并上支架或平放；运控停止后关节不出力。
  - 会**覆盖 `/opt/booster/Gait/configs`（含 F1 键配置）且不备份**；覆盖 `/opt/booster/configs/*`（有备份）；**清空蓝牙配对**（手柄要重新配对）；禁用 hostapd/dnsmasq；更新内核，**大概率自动重启**。升级前备份 `/opt/booster/vision.yaml`、`~/Workspace` 和改过的配置。
  - `/opt/booster/version.txt` 是追加写入的，核对时看最后一段：`tail -n 5 /opt/booster/version.txt`。
  - 升级包**不含 C++ SDK**，所以新机器或刷机后还要装 `sdk_release`。App OTA 会装最新正式版（1.8.0.9），**全队必须同一个版本**。

```bash
# SDK：只在新机器人、刷机后 SDK 缺失，或编译报 SDK 版本错误时安装
scp sdk_release.zip booster@192.168.10.102:~/Workspace/
cd ~/Workspace && unzip sdk_release.zip && cd sdk_release   # 讲义写的是 cd sdk_release.zip（笔误）
sudo ./install.sh        # 成功时输出 "Booster Robotics SDK installed successfully!" 和 "Third Party Libraries installed successfully!"
mkdir build && cd build && cmake .. && make -j4           # 编译 SDK 示例，cmake 无报错、make 无 error 即成功
```

- ⚠ 讲义 p.12 写的是 `chmod +x sdk_release.zip` + `cd sdk_release.zip`。zip 解压出来的目录是 `sdk_release/`，`chmod` 那一步没有必要。
- `sdk_release` 与公开仓库提交 `d5d8f7a`（"update for 1.7.0 firmware"）**逐字节相同**（`diff -rq` 已核实），本地对应 `refs/booster_robotics_sdk@fw1.7`。D17 的 brain 还 include 了内部头文件 `booster_internal/robot/b1/b1_loco_internal_api.hpp`：它**不在任何公开 SDK 里**（`sdk_release` 也没有），**1.7.2 升级包也不安装它**（包内只有运控库里的枚举定义，值 `kEnableRobocupWalkMode = 100008`）。它只被从未调用的 `RobotClient::walkMode()` 使用（`robot_client.cpp:105-113`；include 在 `robot_client.h:10`、`robot_client.cpp:3`）。编译报找不到这个头文件时：删掉这两行 include 和 `walkMode()`，或把枚举换成常量 `100008`（`issues.md` V6）。

## 6. Demo 部署配置【PDF p.13-21】

### 6.1 上传与解压
```bash
scp K1_5v5_demo_1.7.zip booster@192.168.10.102:~/Workspace/
cd ~/Workspace && unzip K1_5v5_demo_1.7.zip && cd K1_5v5_demo_1.7
sudo chmod +x ./scripts/*
```
建议解压后马上 `git init && git add -A && git commit -m "organizer K1_5v5_demo_1.7"`，方便跟踪自己的改动。开发机上的对照副本在 `refs/K1_5v5_demo_1.7`。

### 6.2 3v3 参数（每台机器人各改一次 `src/brain/config/config.yaml`）

| 参数 | 讲义要求 | D17 默认值（行号） | 检查重点 |
|---|---|---|---|
| `game.team_id` | 与裁判机里选的队号一致 | `70`（:4） | 3 台相同；**和对手不同**（§0 #5） |
| `game.player_id` | 同队唯一 | `1`（:5） | 用 1、2、3，不能重复；**守门员用 1**（§0 #6） |
| `game.player_role` | 按 3v3 策略配置 | `goal_keeper`（:7） | 3 台的角色和实际站位一致（例如 1 号 goal_keeper，2、3 号 striker） |
| `game.number_of_players` | 3 | **`5`**（:10） | 必须改成 3 |
| `game.field_type` | 按比赛场地设置，以赛事要求和发布包为准 | `robo_league`（:6） | 可选 `kid_size`（9×6）、`adult_size`（14.16×9.22）、`robo_league`（22.0×14.1）（`src/brain/include/types.h:32-37`）；场地尺寸问主办方（`issues.md` C3） |
| `game_control_ip` | 裁判机 IP（讲义表里写作 `gamecontroller_ip`，实际键名是 `game_control_ip`） | `172.169.80.24`（:193） | 3 台填同一个地址 |
| ⚠`game.player_start_pos` | 讲义未提 | `right`（:8） | 从本方球门看向对方球门，从左手边线入场填 `left`，右手边线填 `right`（`src/brain/src/brain_tree.cpp:2722-2742`）。`SelfLocateEnterField` 两侧都会尝试（:2852-2855），`enter_field` 模式只用配置的那一侧 |
| ⚠`enable_com` | 讲义未提 | `True`（:154） | 开着就必须先处理 §0 #3 的消息额度问题 |
| `recovery.get_up_version` | 可选 kV1/kV2，以现场验证后的发布配置为准 | `kV2`（:166） | 发送 `GetUp` 时 body 为 `{"version":0|1}`（`robot_client.cpp:64-89`）；kV2 需要固件 ≥ 1.7.1（`fw1.7-demo-v1.7.md`） |
| `RLVisionKick.visual_kick_version` | 讲义未提 | `kV2`（:147） | body 为 `{"start":b,"version":0|1}`（`robot_client.cpp:126-149`） |
| `vision.cam_pixel_*`、`cam_fov_*` | 按相机类型改（§6.4） | realsense：1280×720、90°×60°（:173-176） | ⚠ 见 §6.4 |

同一台机器人还要改 `src/game_controller/launch/launch.py`：`enable_ip_white_list: True`，`ip_white_list` 里填同一个裁判机 IPv4（:21-26）。**参数、裁判机 IP 或白名单改完后，都要 `./scripts/stop.sh` → `./scripts/build.sh` → 再启动**。`build.sh` 不带 `--symlink-install`（`scripts/build.sh:9`），运行时读的是 `install/` 里的副本。

### 6.3 Demo 1.7 的关键配置【PDF p.14】
- 起身版本在 brain 配置里（`recovery.get_up_version`）。想用新版起身就设 `kV2`；比赛用 kV1 还是 kV2，以现场验证后的发布配置为准。改完要重新编译再启动。
- 讲义说「直接使用本次提供的 1.7 代码和 2026 版 GameController」：D17 已经适配新版起身接口和 v20 协议（§0 #2）。

### 6.4 相机与视觉配置
- 两种相机：**d-robotics**（双目，自研相机）和 **realsense**（长条状）。先确认机器人装的是哪一种【PDF p.15】。
- 包内有两份模板：`src/vision/config/vision.yaml`（realsense，模型 `k1_realsense_0120.engine`，`use_depth: false`）和 `src/vision/config/vision_d.yaml`（d-robotics，模型 `best_digua_1223_10.3.engine`，`use_depth: true`）。**运行时只读 `vision.yaml`**。d-robotics 机器人要把 `vision_d.yaml` 的内容拷进 `vision.yaml`（或者把相机段写进 `vision_local.yaml`），再 build。
- 模型路径是相对路径 `./src/vision/model/...`，所以 vision 必须从 Demo 根目录启动（`start.sh` 已经 `cd` 到根目录）。
- 讲义给出的两组内外参（p.16-18）：realsense `fx 642.414673, fy 641.951172, cx 639.024414, cy 353.080536`；d-robotics `fx=fy 209.996292, cx 245.417328, cy 235.617691`，外参平移 `(0.0601, -0.0351, -0.09277)`。⚠ 包内 `vision_d.yaml` 的 d-robotics 内参是 `fx=fy 213.079803, cx 277.677612, cy 231.789886`，外参平移是 `(0.0601, +0.0351, +0.09277)`，**后两项符号与讲义相反**。这两组都只是出厂名义值，**以本机手眼标定结果为准**（§6.5）。
- brain 的相机参数（`config.yaml` `vision.*`）：`image_topic: /boostercamera/head/rgb`、`depth_image_topic: /boostercamera/head/depth`（统一命名，不要改）。像素与视场角按相机类型选：

| 相机 | `cam_pixel_width × height` | `cam_fov_x × y`：讲义 p.18 | 包内注释（`config.yaml:171-178`） | 由内参计算 `2·atan(W/2fx)` |
|---|---|---|---|---|
| realsense | 1280 × 720 | 90 × 60（注释掉的那组） | 90 × 60（启用中） | 89.8 × 58.6 |
| d-robotics | 544 × 448 | **69.4 × 42.5** | 105 × 94（标注「debug」） | **104.7 × 93.7** |

  ⚠ 讲义给的 d-robotics 视场角和它自己给的内参对不上，包内的 105×94 与内参一致。`cam_fov_*` 会参与头部追球的增益（`brain_tree.cpp:389-390`）和视野范围判断（`brain.cpp:3684-3685`）。**推荐用内参计算值**，并在实机上用「球在画面边缘时头部是否过冲」来验证（`issues.md` D2）。

### 6.5 手眼标定（只在测距误差大、看球异常、踢球偏差明显、换过相机或长期没标定时做）【PDF p.19-20】
1. 机器人放在安全平整的地方，进入 PREP 站稳；标定板放在机器人正前方约 0.8–1 m；机器人进入 WALK，**整个过程只转头，不动底盘**。
2. 从开发机 `ssh -X booster@<IP>`，然后在 Demo 根目录执行：`source install/setup.bash && ros2 run vision calibration_node handeye src/vision/config/vision.yaml`（也可以用 `./scripts/start_calibration.sh`，它会在结束后把 `/tmp/vision.yaml` 拷到 `/opt/booster/`）。
3. 选中标定窗口，按 `s` 采集，标定板区域变绿，左上角计数增加；用手柄转头，让标定板出现在画面的不同位置，多采几张（窗口提示 `0/8 frames collected`）；按 `c` 开始计算，等 10–30 s，期间不要关终端、不要动机器人。
4. 终端问「overwrite input config with new config? y/n」时输入 `y`：**直接改写命令行给的输入文件**，也就是 `src/vision/config/vision.yaml`，旧文件会备份（`src/vision/src/calibration/calibration_node.cpp:364-378`）。问「save calibration result to /opt/booster/vision.yaml? y/n」时再输入 `y`；没有写权限时会退而写到 `/tmp/vision.yaml`（:384-411），这时手动 `sudo cp /tmp/vision.yaml /opt/booster/vision.yaml`。
5. **然后必须 `./scripts/build.sh` → `source install/setup.bash` → 重启 Demo**，再看 `vision.log`、找球和测距表现，确认新参数已经生效。`/opt/booster/vision.yaml` 只是系统侧的备份（§0 #4）。

### 6.6 编译、启动、日志【PDF p.20-21】
```bash
cd ~/Workspace/K1_5v5_demo_1.7
./scripts/build.sh      # 首次编译要几分钟；显示 finished、没有 error 才能启动
./scripts/start.sh      # 后台启动 vision / brain / game_controller，日志写在 Demo 根目录
tail -f brain.log       # 策略、定位、比赛状态：持续刷新，没有反复出现的异常状态
tail -f vision.log      # 相机、模型、目标检测：持续刷新，模型初始化完成
tail -f game_controller.log  # 裁判机通信：能稳定收到比赛状态
```
- `game_controller.log` 正常时每个包打一行：`handled GameController packet ip=<裁判机IP>, version=20, packet_number=N`（`game_controller_node.cpp:149-151`）。常见异常：`not in ip white list, ignore it`（白名单没改）、`unsupported length`（裁判机版本不对）、没有任何输出（不在同一网段，或者裁判机选错了网卡）。
- brain 收到的包里如果没有本队队号，会打印 `received invalid game controller message team0 %d, team1 %d, teamId %d`（`brain.cpp` `gameControlCallback`），说明 `team_id` 和裁判机选的队不一致。
- 改配置文件、裁判机地址或视觉配置后，都要重新编译再重启。

## 7. 上场【PDF p.21-22】

**上场前检查**：电池电量足够，机械状态正常，没有松动或明显损伤；遥控器连接正常，现场人员知道 DAMP、PREP、WALK 和人工接管的按键；Demo 已启动，§6 的软件检查已完成；场内没有无关人员、线缆和障碍物，机器人前方留出运动空间；3 台机器人的 `player_id`、角色和站位一一对应。

**摆放**：机器人先进入 PREP，由现场人员扶起，放到**本方半场的场外边线附近**的指定位置，不能踩白线（讲义图示：双方 3 台机器人都站在同一条边线外，守门员离本方球门最近，两名前锋靠中线一侧；具体角色和初始站位以本次比赛规则和策略为准）。

| 顺序 | 操作 | 判断标准 |
|---|---|---|
| 1 | 按背部 STAND，或进入 PREP | 机器人稳定站立 |
| 2 | 放到指定的初始位置 | 在场外，没有踩线 |
| 3 | 进入 WALK | 机器人具备行走条件 |
| 4 | LT+A | 进入足球模式，开始定位和找球 |
| 5 | 观察头部 | 找到球后持续注视，移动球时头部跟随 |
| 6 | LT+B | 进入 AI 比赛策略，等待裁判机状态 |

**人工接管**：LT+X。退出后机器人可能继续执行 AI 的最后一条运动指令，轻推摇杆可以打断。发生危险时先让人员离开运动范围，再按现场安全流程进入 PREP 或 DAMP，并停止 Demo。

## 8. 结束与换电【PDF p.22-24】

1. 退出自动比赛策略（LT+X），确认机器人不再执行 AI 指令。
2. `cd ~/Workspace/K1_5v5_demo_1.7 && ./scripts/stop.sh`（`killall -9` vision/brain/sound/game_controller），继续观察机器人姿态。
3. 进入 PREP，把机器人带离场地；需要搬运或关机时进入 DAMP，并让机器人得到可靠支撑。
4. **换电**：低电量报警后及时换，避免断电瘫倒。先移到宽敞处，进入稳定姿态后放倒或放到支撑设备上，再取电池；装满电的电池并确认卡扣到位（讲义图 6 为电池安装方向）→ 开机，等提示音 → 进入 PREP → 确认相机、网络、时间戳正常后重启 Demo → 重看三个日志，再走上场流程。

## 9. 裁判机（HSL GameController 7.0.0-rc.3）【PDF p.24-33】

### 9.1 启动
```bash
tar -xjf game_controller-7.0.0-rc.3-4-x86_64-unknown-linux-gnu.zip   # 讲义原文如此：扩展名是 .zip，却用 tar -xjf；解不开就试 unzip
cd game_controller-7.0.0-rc.3-4-x86_64-unknown-linux-gnu && ./game_controller
```
裁判机电脑必须和 3 台机器人在同一局域网。上游 README 说明该程序依赖 Tauri（Linux 上需要 webkit2gtk）。

| 启动页编号 | 界面项 | 用法 |
|---|---|---|
| 1 | 队伍名称与编号 | 分别选双方队伍。**这里的队号必须和 3 台机器人的 `team_id` 完全一致**，否则机器人收不到本队的比赛信息 |
| 2 | Competition（比赛组别） | 例如 Large 或 Middle，按本次要求选。⚠ Foundation 每队 3 人，Advanced 每队 5 人（§0 #6） |
| 3 | 开球方 | 开局首先开球的队伍，由主裁判抛硬币等方式决定。**进入主界面后不能再改开球方和场地方向** |
| 4 | Interface（广播接口） | 选 GC 发送比赛信息的网卡，按现场网络选有线或无线；本地回环 `lo` 只用于本机测试，正式比赛不要选 |
| 5 | Start | 完成 1–4 和球衣颜色后点击；点之前再核对一遍队号 |
| 6 | Field Player Color | 除守门员外的场上球员颜色，要和双方实际一致 |
| 7 | Goalkeeper Color | 守门员颜色，要和实际一致 |
| — | Mirror / Testing / Broadcast / Multicast | Mirror：主队从右侧开始；Testing → **No Delay**：取消进入 PLAYING 后 10 s 的状态延迟（§0 #7）；Broadcast：发到 255.255.255.255；**Multicast 只用于仿真** |

选好接口后，在裁判机上用 `ifconfig` 确认这块网卡的 IPv4，并核对 3 台机器人里配置的裁判机 IP。选错网卡时，机器人收不到稳定的比赛状态。

### 9.2 主界面（编号 1–20）

| # | 界面项 | 含义与用法 |
|---|---|---|
| 1 | 队伍名称 | 启动页选的队伍，用来确认当前操作的是哪一队 |
| 2 | 比分 | 由技术裁判用 #4 的 Goal 加分 |
| 3 | 开球方标记 | 当前拥有开球权的队伍；进球后或重新开始比赛时要核对 |
| 4 | Goal | **主裁判确认进球有效后**，点进球队伍一侧的 Goal；不要自行加分 |
| 5 | 上/下半场 | 切换半场前确认上一半场已结束 |
| 6 | 队员状态 | 绿色对号表示机器人在线（GC 收到了回包），红叉表示没上线；没上线时依次查网络、程序和 `team_id` |
| 7 | 剩余时间 | 本半场剩余比赛时间（半场 600 s） |
| 8 | Substitute | 替补或换人：按主裁判指令选队伍和机器人，确认后再让机器人进场 |
| 9 | Timeout | 球队申请暂停（每队每场 1 次，300 s） |
| 10 | Pick-up | 机器人故障、摔倒或干扰比赛时用。先点 Pick-up，再选机器人编号，然后现场人员把机器人抬离 |
| 11 | 比赛状态 | Initial 初始化 → Ready（机器人执行上场逻辑，45 s）→ Set（**必须完全静止**）→ Playing → Finish。必须听主裁判口令按顺序切换 |
| 12 | Direct Free Kick | 直接任意球：防守方犯规后使用，主罚队可以直接射门得分 |
| 13 | Indirect Free Kick | 间接任意球：不能直接射门得分，球至少再被另一名球员触碰一次后，进球才有效 |
| 14 | Penalty Kick | 点球：由主裁判判定后，选获得点球的一方 |
| 15 | Throw-in | 边线出界：球权给最后触球方的对手 |
| 16 | Goal Kick | 球门球：球越过球门线，最后由进攻方触球时，判给防守方 |
| 17 | Corner Kick | 角球：球越过球门线，最后由防守方触球时，判给进攻方 |
| 18 | Messages / Penalties | 本队剩余可用的通信包数（初始 12000）和已受罚次数。**比赛中盯住 Messages**（§0 #3） |
| 19 | Stop Play | 紧急停止：主裁判因安全原因要求停止时点击，所有机器人应立即停止运动，行为同 Set（发 `stopped=1`） |
| 20 | Referee Timeout | 裁判技术暂停，处理非战术性的突发情况（场地、系统问题）；不要和球队 Timeout 混用 |

定位球（#12–17）在 v20 里的流程：GC 设 `setPlay` 且 `stopped=1`（摆球）→ 裁判恢复（`stopped=0`）→ 45 s 内完成，否则 Ball Free。D17 的处理：我方定位球恢复后走普通进攻树；对方定位球恢复后只找球和防守站位，等到 `set_play` 回到 0（Ball Free）才允许踢（`brain.cpp` `gameControlCallback` 与 `:1289-1325`）。

### 9.3 判罚（编号 21–33；时长取自 GC7 `config/large_advanced/params.yaml`，Foundation 相同）

| # | 按键 | 何时用（讲义） | GC7 罚时 |
|---|---|---|---|
| 21 | Pushing | 不同队机器人之间发生使对方失去平衡的接触，或轻微推挤持续超过 5 s | 45 s，递增 |
| 22 | Incapable Robot | 机器人停止活动达 10 s，或者宕机 | 45 s |
| 23 | Leaving the Field | 机器人离开比赛区域 | 45 s，递增 |
| 24 | Motion in Set | Set 阶段移动腿部或做其它运动（Set 阶段必须保持静止） | 15 s，原地 |
| 25 | Illegal Position | 非法站位：Set 时站在对方半场、无开球权时进入中圈、任意球或点球时侵入避让区等 | 45 s |
| 26 | Ball Holding | 持球超时：守门员至少一只脚在本方罚球区内时最多持球 10 s，其它情况最多 5 s | 45 s，递增 |
| 27 | Local Game Stuck | 机器人接近球，但球在 10 s 内没有明显移动时，罚最近的机器人 | 45 s |
| 28 | Arms / Hands | 场上球员，或离开本方罚球区的守门员，主动用手臂或手触球；摔倒和起身过程中的接触另按规则处理 | 45 s，递增 |
| 29 | Warning | 口头警告：同一球员一场累计两次警告升级为黄牌 | — |
| 30 | Yellow Card | 黄牌（正式警告）：同一球员一场累计两张黄牌则红牌罚出 | 45 s，递增（`cautioned`） |
| 31 | Red Card | 红牌：球员立即离开比赛区域和技术区，不得继续参赛 | 本场罚出 |
| 32 | Ball Free | 自由球：恢复后双方都可以抢球；点击前由主裁判确认时机 | — |
| 33 | Global Game Stuck | 全局卡住：30 s 内没有机器人进入球 1 m 范围时使用，按规则恢复比赛 | — |

- 递增 = 本队每多受一次罚，时长 +10 s（`penaltyDurationIncrement`）。受罚的机器人在 GC 包里 `penalty != 0`；D17 会停下、重新定位，罚时结束后自主从场边入场（`game.xml:43-48`）。
- 判罚一般**先选判罚类型，再选队伍和机器人编号**。点击前必须听清主裁判口令，**不要用界面上的队员排列位置代替机器人编号判断**。
- **Undo**：界面底部每个区域下方都有 Undo。点错时先告知主裁判并确认，**只撤销最近一次错误操作**，避免连续回退导致比分、状态或判罚记录不一致。

### 9.4 一场比赛的流程
1. 启动页选双方队伍、组别、开球方、颜色和正确的广播网卡 → Start → 确认初始状态为 Initial。
2. 双方机器人启动 Demo，完成 LT+A 定位和 LT+B 比赛策略启动。
3. 主裁判发出 Ready，机器人执行上场逻辑（READY 最长 45 s，到时自动转 SET）。
4. 进入 Set 后机器人必须站定，裁判把球放到指定位置。
5. 进入 Playing 后比赛开始（⚠ 除非勾了 No Delay，机器人最多 10 s 后才会看到 PLAYING）。技术裁判根据场上情况执行得分、定位球、处罚和人工处理。
6. 倒计时结束或裁判宣布结束后进入 Finish，现场人员按 §8 让机器人安全下场。

**常用操作**：Pickup（机器人摔倒、故障或干扰比赛；先点 Pickup 再选编号，处理完后按界面流程恢复）；Substitute（换人，遵从现场裁判指令）；Stop Play（安全原因紧急停止，行为同 Set）；Referee Timeout（处理非战术性技术问题）；Penalty Kick / Throw-in / Goal Kick / Corner Kick（见 §9.2）。

**Pickup 处理顺序**：① 现场人员向主裁判申请，说清队伍颜色和机器人编号 → ② 技术裁判点 Pickup，再选对应机器人 → ③ 现场人员把机器人移出场地并排除问题 → ④ 机器人重新准备好后，向主裁判说明状态，技术裁判按界面流程解除处罚、恢复比赛。**D17 的对应操作**（`game.xml:26` 分支名的注释）：被 pickup 的机器人先走到（或被放到）入场位置 → 按 LT+A 重新定位 → 等几秒 → 按 LT+B 继续比赛。

## 10. 讲义与代码的出入汇总

| # | 讲义说法（页） | 实际（出处） | 处理 |
|---|---|---|---|
| E1 | `/opt/booster/vision.yaml` 优先于 Demo 目录的 `vision.yaml`（p.18） | 运行时不读 `/opt/booster/vision.yaml`（`start.sh:33`、`vision/launch/launch.py:9-20`） | 改 `src/vision/config/vision.yaml` 后 build |
| E2 | `sudo cp /opt/booster/vision.yaml ~/Workspace/K1_5v5_Demo_1.7/...`（p.18） | 目录是 `K1_5v5_demo_1.7` | 路径改小写 d |
| E3 | `sudo vim ~/Workspace/K1-5v5_Demo/src/brain/config/config.yaml`（p.18） | 同上 | 同上 |
| E4 | d-robotics `cam_fov_x/y = 69.4/42.5`（p.18） | 与内参不自洽，内参对应约 104.7/93.7 | 用计算值并实机验证 |
| E5 | d-robotics 外参平移 `(0.0601,-0.0351,-0.09277)`（p.17-18） | 包内 `vision_d.yaml` 为 `(0.0601,+0.0351,+0.09277)` | 以本机标定为准 |
| E6 | 参数名 `gamecontroller_ip`（p.14 表） | 键名是 `game_control_ip`（`config.yaml:193`） | — |
| E7 | `chmod +x sdk_release.zip`、`cd sdk_release.zip`（p.12） | 解压目录是 `sdk_release/` | — |
| E8 | 裁判机包 `tar -xjf ….zip`（p.24） | 扩展名与命令不符 | 按实际格式解压 |
| E9 | 参数表只列 6 项（p.14） | 还有 `player_start_pos`、`enable_com`（消息额度）、白名单开关 | 见 §6.2 |
| E10 | 未提队内通信额度 | 默认 10 Hz × 3 台，约 7 分钟耗尽 12000 条，比分清零（§0 #3） | 上场前必须降频 |
| E11 | 未提 10 s 状态延迟 | GC7 `delayAfterPlaying` 10 s，D17 无哨声检测（§0 #7） | 问主办方是否勾 No Delay |
| E12 | 截图用 `Large - Advanced`（每队 5 人） | 3v3 对应 Foundation（3 人） | 问主办方用哪个组别 |
