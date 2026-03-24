#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export HOME="$TMP_DIR/home"
mkdir -p "$HOME"

REPO_RAW="file://$ROOT_DIR" bash "$ROOT_DIR/install.sh" >"$TMP_DIR/install.out" 2>&1

[[ -f "$HOME/kube-grade/lib/grade-lib.sh" ]]
[[ -f "$HOME/kube-grade/lib/grade-recipes.sh" ]]
[[ -f "$HOME/kube-grade/ckad/scenarios/grade-cronjob-advanced.sh" ]]
[[ -f "$HOME/kube-grade/ckad/scenarios/grade-pvc-pod.sh" ]]
[[ -f "$HOME/kube-grade/ckad/scenarios/grade-rbac-namespace.sh" ]]

bash -lc "
  export HOME='$HOME'
  source '$HOME/.bashrc'
  declare -F new_task kg recipe_cronjob_advanced >/dev/null
  type kg-discover >/dev/null 2>&1
  new_task 42 ckad
  [[ -f '$HOME/kube-grade/ckad/tasks/task42-grade.sh' ]]
" >/dev/null 2>&1
