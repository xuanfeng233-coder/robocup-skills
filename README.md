# RoboCup Agent Skills

面向本队 Booster K1 3v3 足球项目的 Agent Skills。支持 Claude Code、Codex、Cursor 等工具。

## 一条命令安装

先安装 [Node.js](https://nodejs.org/)（Skills CLI 当前要求 Node.js ≥ 22.20.0）和 Git，在项目目录运行：

```bash
npx --yes skills@latest add xuanfeng233-coder/robocup-skills
```

按提示选择自己的 agent 和安装范围。无需克隆本仓库，也无需本仓库单独发布 npm 包；安装使用 [Vercel Skills CLI](https://github.com/vercel-labs/skills)。

指定 agent、无需交互：

```bash
# Claude Code：安装到当前项目
npx --yes skills@latest add xuanfeng233-coder/robocup-skills --skill booster-k1-robocup -a claude-code -y

# Codex：安装到当前项目
npx --yes skills@latest add xuanfeng233-coder/robocup-skills --skill booster-k1-robocup -a codex -y

# Cursor：安装到当前项目
npx --yes skills@latest add xuanfeng233-coder/robocup-skills --skill booster-k1-robocup -a cursor -y

# Claude Code + Codex：全局安装，跨项目可用
npx --yes skills@latest add xuanfeng233-coder/robocup-skills --skill booster-k1-robocup -a claude-code codex -g -y
```

如果 agent 未立即识别新 skill，请重新开启会话。可以对 agent 说：

> 使用 booster-k1-robocup skill，检查本队固件 1.7 的 Demo 1.7 上场配置，并列出尚待验证的项目。

## 包含什么

`skills/booster-k1-robocup/` 包含开发索引、11 份参考文档、官方源码下载与文档抓取脚本。内容涉及 SDK、底层控制、硬件、Demo、RL、赛事规则与现场操作。

这些文档整理于 **2026-09-24**，本队比赛基线是主办方 Demo 1.7 / 固件 ≥ 1.7。原文中的已确认结论和待实机验证标记均保留；本次发布只调整安装和路径兼容性，没有重新验证机器人技术结论。回答技术问题时应按 skill 的要求核对对应版本的原始源码。

## 源码语料库（需要查源码时再准备）

Skill 安装已包含参考文档；`refs/` 语料库按需另行准备。在自己的 RoboCup 项目根目录，让 agent 执行：

> 找到当前加载的 booster-k1-robocup skill 目录，运行其中的 scripts/bootstrap_refs.sh，把本项目的绝对路径作为参数。

也可手动运行（将 `/path/to/...` 替换为实际路径）：

```bash
bash /path/to/booster-k1-robocup/scripts/bootstrap_refs.sh /path/to/RoboCup
ROBOCUP_ROOT=/path/to/RoboCup bash /path/to/booster-k1-robocup/scripts/find_ref.sh 'MoveCommand' booster_robotics_sdk@fw1.7
```

Bootstrap 需要 Bash、Git、Python 3、curl、unzip 和网络，会在指定项目中克隆/更新官方仓库、建立固定版本 worktree、抓取官方文档，可能下载较多数据。Windows 请使用 WSL。它不会部署到机器人或安装固件。

**队内另外分发的资料**：赛事 PDF、`K1_5v5_demo_1.7.zip`、`sdk_release.zip` 和固件 `.run`。将它们放在自己的项目根目录；bootstrap 在 Demo zip 存在时解压到 `refs/`。这些资料不包含在本仓库或安装命令中。公开 Demo main 分支不能替代主办方 Demo 1.7。

## 更新

```bash
npx --yes skills@latest check
npx --yes skills@latest update
```

上述命令检查或更新 Skills CLI 管理的 skills。只重新安装本 skill 时，重跑自己的安装命令。更新可能覆盖本地对已安装 skill 的修改；团队共用结论请维护在本仓库中。

## 维护

直接编辑 `skills/booster-k1-robocup/` 并提交到 GitHub。新增 skill 时，在 `skills/` 下创建同名目录和包含 `name`、`description` frontmatter 的 `SKILL.md`。

本仓库分发参考索引和辅助脚本。引用的官方源码、文档和主办方材料的权利仍归各自权利人；下载的源码遵循各自仓库的许可。
