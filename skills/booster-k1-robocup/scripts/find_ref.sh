#!/usr/bin/env bash
# Grep the local reference corpus (refs/) skipping meshes, vendored libs, binaries.
# Usage: find_ref.sh PATTERN [subdir]   e.g. find_ref.sh kTopicJointCtrl   find_ref.sh "kick" robocup_demo
set -eu
if [ "$#" -lt 1 ]; then
  echo 'Usage: find_ref.sh PATTERN [subdir] (set ROBOCUP_ROOT or run from the project root)' >&2
  exit 2
fi
ROOT="$(cd "${ROBOCUP_ROOT:-$PWD}" && pwd)"
if [ ! -d "$ROOT/refs/${2:-}" ]; then
  echo "Reference directory missing: $ROOT/refs/${2:-}. Run bootstrap_refs.sh first." >&2
  exit 1
fi
cd "$ROOT"
grep -rnIE --color=never \
  --exclude-dir=.git --exclude-dir=meshes --exclude-dir=third_party --exclude-dir=third_party_aarch64 \
  --exclude-dir=booster_fastdds --exclude-dir=nlohmann_json --exclude-dir=thirdparty \
  --exclude='*.stl' --exclude='*.STL' --exclude='*.npz' --exclude='*.so*' --exclude='*.onnx' \
  -- "$1" "refs/${2:-}" | cut -c1-240 | head -n "${MAX:-80}"
