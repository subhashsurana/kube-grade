#!/usr/bin/env bash
# =============================================================================
# Task TASK_NUM — kube-grade self-grading script  [EXAM_TAG]
#
# WORKFLOW:
#   1. Read the task — translate every bullet point into a check_ call below
#   2. Run this script BEFORE hitting the Killercoda check button
#   3. Fix until 100%, then submit with confidence
#
# Run: bash tasks/taskTASK_NUM-grade.sh
# =============================================================================

# ── Load library ──────────────────────────────────────────────────────────────
LIB="$HOME/kube-grade/lib/grade-lib.sh"
if [[ -f "$LIB" ]]; then
  # shellcheck source=/dev/null
  source "$LIB"
else
  # shellcheck source=/dev/null
  source <(curl -sL https://raw.githubusercontent.com/subhashsurana/kube-grade/main/lib/grade-lib.sh)
fi

# =============================================================================
# CONFIG — copy exact names from the task description (case-sensitive)
# =============================================================================
CONTEXT="k8s-c1"       # the kubectl config use-context line at the top of the task
NAMESPACE="default"

DEPLOY_NAME="my-deploy"
POD_NAME="my-pod"
SVC_NAME="my-svc"
CM_NAME="my-cm"
SECRET_NAME="my-secret"
PVC_NAME="my-pvc"
SA_NAME="my-sa"
ROLE_NAME="my-role"
RB_NAME="my-rb"
CRONJOB_NAME="my-cj"
INGRESS_NAME="my-ingress"

IMAGE="nginx:1.21"
REPLICAS=1
LABEL_KEY="app"
LABEL_VAL="myapp"
OUTPUT_FILE="/opt/course/TASK_NUM/answer.txt"

# Keep placeholder config variables "used" for shellcheck while preserving
# the template structure for manual editing.
: "${DEPLOY_NAME}${POD_NAME}${SVC_NAME}${CM_NAME}${SECRET_NAME}${PVC_NAME}"
: "${SA_NAME}${ROLE_NAME}${RB_NAME}${CRONJOB_NAME}${INGRESS_NAME}"
: "${IMAGE}${REPLICAS}${LABEL_KEY}${LABEL_VAL}${OUTPUT_FILE}"

# =============================================================================
# GRADING
# =============================================================================

# ── Context (always first) ────────────────────────────────────────────────────
_section "Context"
_info "kubectl config use-context $CONTEXT"
kubectl config use-context "$CONTEXT" 2>/dev/null \
  && _pass "Context = $CONTEXT" \
  || _warn "Context '$CONTEXT' not found — using current context"

# ── Namespace ─────────────────────────────────────────────────────────────────
_section "Namespace"
check_namespace "$NAMESPACE"

# =============================================================================
# Uncomment and fill in the blocks that apply to this task
# =============================================================================

# ── Pod ───────────────────────────────────────────────────────────────────────
# _section "Pod"
# check_exists      pod  "$POD_NAME"  "$NAMESPACE"
# check_pod_ready        "$POD_NAME"  "$NAMESPACE"
# check_image            "$POD_NAME"  "$NAMESPACE"  "$IMAGE"
# check_label       pod  "$POD_NAME"  "$NAMESPACE"  "$LABEL_KEY" "$LABEL_VAL"

# ── Deployment ────────────────────────────────────────────────────────────────
# _section "Deployment"
# check_exists       deployment  "$DEPLOY_NAME"  "$NAMESPACE"
# check_deploy_image             "$DEPLOY_NAME"  "$NAMESPACE"  "$IMAGE"
# check_replicas                 "$DEPLOY_NAME"  "$NAMESPACE"  "$REPLICAS"
# check_label        deployment  "$DEPLOY_NAME"  "$NAMESPACE"  "$LABEL_KEY" "$LABEL_VAL"
# check_selector_label deployment "$DEPLOY_NAME" "$NAMESPACE"  "$LABEL_KEY" "$LABEL_VAL"

# ── Service ───────────────────────────────────────────────────────────────────
# _section "Service"
# check_exists           service  "$SVC_NAME"  "$NAMESPACE"
# check_service_type               "$SVC_NAME"  "$NAMESPACE"  "ClusterIP"
# check_service_port               "$SVC_NAME"  "$NAMESPACE"  80  8080
# check_service_selector           "$SVC_NAME"  "$NAMESPACE"  "$LABEL_KEY" "$LABEL_VAL"
# check_service_endpoints          "$SVC_NAME"  "$NAMESPACE"

# ── ConfigMap + env ───────────────────────────────────────────────────────────
# _section "ConfigMap"
# check_exists configmap "$CM_NAME" "$NAMESPACE"
# check_jsonpath configmap "$CM_NAME" "$NAMESPACE" '{.data.MY_KEY}' "my_value" "CM data.MY_KEY"
# _section "Env var"
# check_env                "$POD_NAME" "$NAMESPACE" "MY_KEY" "my_value"
# check_env_from_configmap "$POD_NAME" "$NAMESPACE" 0 "MY_KEY" "$CM_NAME" "MY_KEY"

# ── Secret + volume mount ─────────────────────────────────────────────────────
# _section "Secret"
# check_exists    secret         "$SECRET_NAME"  "$NAMESPACE"
# check_secret_key               "$SECRET_NAME"  "$NAMESPACE"  "password"  "s3cr3t"
# check_volume_mount "$POD_NAME" "$NAMESPACE"    "/etc/secret"  "$SECRET_NAME"

# ── Resources + probes ───────────────────────────────────────────────────────
# _section "Resources"
# check_resources "$POD_NAME" "$NAMESPACE" "100m" "128Mi" "200m" "256Mi"
# _section "Liveness probe"
# check_probe     "$POD_NAME" "$NAMESPACE" liveness  "/healthz" 8080 10
# _section "Readiness probe"
# check_probe     "$POD_NAME" "$NAMESPACE" readiness "/ready"   8080 5

# ── PVC + storage ─────────────────────────────────────────────────────────────
# _section "PVC"
# check_pvc          "$PVC_NAME"  "$NAMESPACE"  "1Gi"  "ReadWriteOnce"  "standard"
# check_volume_mount "$POD_NAME"  "$NAMESPACE"  "/data"  "$PVC_NAME"

# ── RBAC ──────────────────────────────────────────────────────────────────────
# _section "RBAC"
# check_exists           serviceaccount  "$SA_NAME"    "$NAMESPACE"
# check_exists           role            "$ROLE_NAME"  "$NAMESPACE"
# check_exists           rolebinding     "$RB_NAME"    "$NAMESPACE"
# check_rolebinding_role                 "$RB_NAME"    "$NAMESPACE"  "$ROLE_NAME"
# check_rolebinding_subject              "$RB_NAME"    "$NAMESPACE"  "$SA_NAME"
# check_rbac             "$SA_NAME"      "$NAMESPACE"  "get"    "pods"  "yes"
# check_rbac             "$SA_NAME"      "$NAMESPACE"  "delete" "pods"  "no"

# ── CronJob ───────────────────────────────────────────────────────────────────
# _section "CronJob"
# check_cronjob "$CRONJOB_NAME" "$NAMESPACE" "*/5 * * * *" "busybox:1.28"

# ── Ingress ───────────────────────────────────────────────────────────────────
# _section "Ingress"
# check_ingress "$INGRESS_NAME" "$NAMESPACE" "myapp.example.com" "/api" "api-svc" 80

# ── NetworkPolicy ─────────────────────────────────────────────────────────────
# _section "NetworkPolicy"
# check_netpol "my-netpol" "$NAMESPACE" "app" "api"

# ── File output ───────────────────────────────────────────────────────────────
# _section "File output"
# EXPECTED=$(kubectl get pod -n "$NAMESPACE" -l "$LABEL_KEY=$LABEL_VAL" \
#              -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
# check_file_exists   "$OUTPUT_FILE"
# check_file_contains "$OUTPUT_FILE" "$EXPECTED"

# =============================================================================
grade_summary
