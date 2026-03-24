#!/usr/bin/env bash
# =============================================================================
# kube-grade / ckad / grade-pvc-pod.sh
# Scenario: PVC mounted into a Pod
#
# Env overrides:
#   NS=default PVC_NAME=data-pvc POD_NAME=app-pod PVC_SIZE=1Gi \
#   PVC_ACCESS_MODE=ReadWriteOnce MOUNT_PATH=/data EXPECT_POD_READY=1 \
#   bash grade-pvc-pod.sh
# =============================================================================

LIB="$HOME/kube-grade/lib/grade-recipes.sh"
if [[ -f "$LIB" ]]; then
  # shellcheck source=/dev/null
  source "$LIB"
else
  # shellcheck source=/dev/null
  source <(curl -sL https://raw.githubusercontent.com/subhashsurana/kube-grade/main/lib/grade-recipes.sh)
fi

NS="${NS:-default}"
PVC_NAME="${PVC_NAME:-data-pvc}"
POD_NAME="${POD_NAME:-app-pod}"
PVC_SIZE="${PVC_SIZE:-1Gi}"
PVC_ACCESS_MODE="${PVC_ACCESS_MODE:-ReadWriteOnce}"
PVC_STORAGE_CLASS="${PVC_STORAGE_CLASS:-}"
MOUNT_PATH="${MOUNT_PATH:-/data}"
POD_VOLUME_NAME="${POD_VOLUME_NAME:-}"
IMAGE="${IMAGE:-}"
EXPECT_POD_READY="${EXPECT_POD_READY:-1}"

recipe_pvc_pod
grade_summary
