#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

assert_contains() {
  local file=$1
  local text=$2

  if ! grep -F -- "$text" "$file" >/dev/null; then
    echo "Expected to find '$text' in $file" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file=$1
  local text=$2

  if grep -F -- "$text" "$file" >/dev/null; then
    echo "Did not expect to find '$text' in $file" >&2
    exit 1
  fi
}

run_wrapper() {
  local script=$1
  local output=$2
  shift 2

  (
    export HOME="$TMP_DIR/home"
    export PATH="$ROOT_DIR/tests/fixtures:$PATH"
    export NS="team-a"
    "$@" bash "$script"
  ) >"$output" 2>&1
}

export HOME="$TMP_DIR/home"
mkdir -p "$HOME/kube-grade/lib" "$HOME/kube-grade/ckad/scenarios"
cp "$ROOT_DIR/lib/grade-lib.sh" "$HOME/kube-grade/lib/grade-lib.sh"
cp "$ROOT_DIR/lib/grade-recipes.sh" "$HOME/kube-grade/lib/grade-recipes.sh"
cp "$ROOT_DIR/VERSION" "$HOME/kube-grade/VERSION"
cp "$ROOT_DIR/ckad/scenarios/grade-cronjob-advanced.sh" "$HOME/kube-grade/ckad/scenarios/grade-cronjob-advanced.sh"
cp "$ROOT_DIR/ckad/scenarios/grade-pvc-pod.sh" "$HOME/kube-grade/ckad/scenarios/grade-pvc-pod.sh"
cp "$ROOT_DIR/ckad/scenarios/grade-rbac-namespace.sh" "$HOME/kube-grade/ckad/scenarios/grade-rbac-namespace.sh"

CRON_OUT="$TMP_DIR/cron.out"
run_wrapper \
  "$HOME/kube-grade/ckad/scenarios/grade-cronjob-advanced.sh" \
  "$CRON_OUT" \
  env \
    CRONJOB_NAME=nightly \
    SCHEDULE='*/5 * * * *' \
    IMAGE='busybox:1.36' \
    COMMAND_0='/bin/sh' \
    COMMAND_1='-c' \
    COMMAND_2='echo Processing && sleep 30' \
    JOB_ACTIVE_DEADLINE_SECONDS=40 \
    JOB_BACKOFF_LIMIT=2 \
    JOB_COMPLETIONS=4 \
    JOB_PARALLELISM=2 \
    JOB_TTL_SECONDS_AFTER_FINISHED=120
assert_contains "$CRON_OUT" "CronJob 'nightly' schedule = '*/5 * * * *'"
assert_contains "$CRON_OUT" "CronJob 'nightly' ttlSecondsAfterFinished = '120'"
assert_contains "$CRON_OUT" "100%)"
assert_not_contains "$CRON_OUT" "FAIL"

PVC_OUT="$TMP_DIR/pvc.out"
run_wrapper \
  "$HOME/kube-grade/ckad/scenarios/grade-pvc-pod.sh" \
  "$PVC_OUT" \
  env \
    PVC_NAME=data-pvc \
    POD_NAME=app-pod \
    PVC_SIZE=1Gi \
    PVC_ACCESS_MODE=ReadWriteOnce \
    MOUNT_PATH=/data \
    POD_VOLUME_NAME=data-pvc \
    IMAGE='nginx:1.27' \
    EXPECT_POD_READY=1
assert_contains "$PVC_OUT" "PVC 'data-pvc' storage = '1Gi'"
assert_contains "$PVC_OUT" "Pod 'app-pod' mounts '/data' from volume 'data-pvc'"
assert_contains "$PVC_OUT" "100%)"
assert_not_contains "$PVC_OUT" "FAIL"

RBAC_OUT="$TMP_DIR/rbac.out"
run_wrapper \
  "$HOME/kube-grade/ckad/scenarios/grade-rbac-namespace.sh" \
  "$RBAC_OUT" \
  env \
    SA_NAME=build-bot \
    ROLE_NAME=workload-reader \
    RB_NAME=workload-reader-bind \
    RBAC_VERB=get \
    RBAC_RESOURCE=pods \
    RBAC_EXPECTED=yes
assert_contains "$RBAC_OUT" "RoleBinding 'workload-reader-bind' roleRef = 'workload-reader'"
assert_contains "$RBAC_OUT" "SA 'build-bot' can-i get pods = 'yes'"
assert_contains "$RBAC_OUT" "100%)"
assert_not_contains "$RBAC_OUT" "FAIL"
