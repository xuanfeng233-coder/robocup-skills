#!/usr/bin/env bash
# Re-create refs/: clone (or pull) all official Booster repos and re-dump docs.booster.tech.
# Usage: bootstrap_refs.sh [ROOT]   (ROOT defaults to ROBOCUP_ROOT, then the current directory)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${1:-${ROBOCUP_ROOT:-$PWD}}" && pwd)"
REFS="$ROOT/refs"; mkdir -p "$REFS"
REPOS="booster_robotics_sdk robocup_demo booster_deploy booster_assets sim-3v3-simple-framework
booster_champion_example booster_robotics_sdk_ros2 booster_train booster_gym"
for r in $REPOS; do
  if [ -d "$REFS/$r/.git" ]; then git -C "$REFS/$r" pull -q --ff-only || echo "pull failed: $r"
  else git clone -q --depth 1 "https://github.com/BoosterRobotics/$r.git" "$REFS/$r" & fi
done; wait
# New repos published since this list was written:
curl -s "https://api.github.com/users/BoosterRobotics/repos?per_page=100" | python3 -c '
import json,sys; known=set(sys.argv[1].split())
for r in json.load(sys.stdin):
    if r["name"] not in known: print("NEW REPO (not cloned):", r["name"], "-", r.get("description"))
' "$REPOS" || true
# RoboCup Humanoid Soccer League (rules, GameController, inspection tool)
mkdir -p "$REFS/robocup_league"
for r in GameController HSL-Rules RobotInspection; do
  if [ -d "$REFS/robocup_league/$r/.git" ]; then git -C "$REFS/robocup_league/$r" pull -q --ff-only || true
  else git clone -q --depth 1 "https://github.com/RoboCup-HumanoidSoccerLeague/$r.git" "$REFS/robocup_league/$r"; fi
done
# HSL GameController pinned to the version the organizer ships (game_controller-7.0.0-rc.3-4-*.zip, struct v20)
git -C "$REFS/robocup_league/GameController" fetch -q --depth 1 origin tag v7.0.0-rc.3 2>/dev/null || true
[ -d "$REFS/robocup_league/GameController@v7.0.0-rc.3" ] || git -C "$REFS/robocup_league/GameController" worktree add -q --detach \
  "$REFS/robocup_league/GameController@v7.0.0-rc.3" v7.0.0-rc.3
# Legacy Humanoid League GameController (HL struct v12; only for reading old code / the abandoned v1.6 stack)
[ -d "$REFS/robocup_league/GameController-HL-2025/.git" ] || git clone -q --depth 1 -b v2025.1.1 \
  https://github.com/RoboCup-Humanoid-TC/GameController.git "$REFS/robocup_league/GameController-HL-2025"
# robocup_demo feature branches (2026 GameController, auto-calibration, K1 fw 1.6.0.4+ ...)
git -C "$REFS/robocup_demo" fetch -q --unshallow 2>/dev/null || true
git -C "$REFS/robocup_demo" fetch -q origin '+refs/heads/*:refs/remotes/origin/*'
# Team stack = organizer's Demo 1.7 / firmware >= 1.7. SDK: sdk_release.zip == public commit d5d8f7a
# ("update for 1.7.0 firmware", byte-identical). fw1.6 worktree kept only for diffing old code.
git -C "$REFS/booster_robotics_sdk" fetch -q --unshallow 2>/dev/null || true
[ -d "$REFS/booster_robotics_sdk@fw1.7" ] || git -C "$REFS/booster_robotics_sdk" worktree add -q --detach "$REFS/booster_robotics_sdk@fw1.7" d5d8f7a
[ -d "$REFS/booster_robotics_sdk@fw1.6" ] || git -C "$REFS/booster_robotics_sdk" worktree add -q --detach "$REFS/booster_robotics_sdk@fw1.6" 324946e
[ -d "$REFS/robocup_demo@v1.6.0.4" ] || git -C "$REFS/robocup_demo" worktree add -q --detach "$REFS/robocup_demo@v1.6.0.4" "origin/sandbox/support_k1_v1.6.0.4+"
# Organizer packages are not on GitHub: unzip them from the project root if present.
[ -d "$REFS/K1_5v5_demo_1.7" ] || { [ -f "$ROOT/K1_5v5_demo_1.7.zip" ] && unzip -q "$ROOT/K1_5v5_demo_1.7.zip" -d "$REFS"; } \
  || echo "MISSING: K1_5v5_demo_1.7.zip (organizer package) not found in $ROOT"
python3 "$HERE/dump_docs.py" "$REFS/booster_docs"
