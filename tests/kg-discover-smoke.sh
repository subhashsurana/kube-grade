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

run_discover() {
  local input=$1
  local output=$2

  set +e
  printf '%s' "$input" | bash "$ROOT_DIR/lib/kg-discover.sh" 7 ckad >"$output" 2>&1
  local status=$?
  set -e

  return "$status"
}

export HOME="$TMP_DIR/home"
export PATH="$ROOT_DIR/tests/fixtures:$PATH"

mkdir -p "$HOME/kube-grade/lib" "$HOME/kube-grade/ckad/tasks"
cp "$ROOT_DIR/lib/grade-lib.sh" "$HOME/kube-grade/lib/grade-lib.sh"
cp "$ROOT_DIR/VERSION" "$HOME/kube-grade/VERSION"

QUIT_OUTPUT="$TMP_DIR/quit.out"
if ! run_discover $'q\n' "$QUIT_OUTPUT"; then
  echo "Expected kg-discover quit flow to exit successfully" >&2
  exit 1
fi
assert_contains "$QUIT_OUTPUT" "Aborted."

INVALID_OUTPUT="$TMP_DIR/invalid.out"
if run_discover $'999\n' "$INVALID_OUTPUT"; then
  echo "Expected kg-discover invalid selection to fail" >&2
  exit 1
fi
assert_contains "$INVALID_OUTPUT" "No valid selections. Exiting."

ANSWER_FILE="$TMP_DIR/answer.txt"
printf '%s\n' "nightly-123" >"$ANSWER_FILE"

DISCOVER_INPUT=$(
  printf '%s\n' \
    '0,1,2,3,4,5,6,8,9,10,11,12' \
    '' \
    '' \
    '' \
    'app=web' \
    '' \
    '' \
    'app=web' \
    '' \
    '' \
    '8080' \
    'MODE' \
    'prod' \
    'password' \
    's3cr3t' \
    '' \
    '' \
    'get pods' \
    'workload-reader' \
    '' \
    '' \
    '' \
    '/api' \
    'web-svc' \
    'app=web' \
    'y' \
    "$ANSWER_FILE"
)
DISCOVER_INPUT="${DISCOVER_INPUT}"$'\n'

DISCOVER_OUTPUT="$TMP_DIR/discover.out"
if ! run_discover "$DISCOVER_INPUT" "$DISCOVER_OUTPUT"; then
  echo "Expected kg-discover happy path to succeed" >&2
  exit 1
fi

for resource_name in \
  app-pod web-deploy web-svc app-config app-secret data-pvc build-bot workload-reader \
  workload-reader-bind nightly batch-once web-ing allow-web db-sts log-agent web-rs
do
  assert_contains "$DISCOVER_OUTPUT" "$resource_name"
done

for selected_name in \
  app-pod web-deploy web-svc app-config app-secret data-pvc build-bot \
  workload-reader-bind nightly batch-once web-ing allow-web
do
  assert_contains "$DISCOVER_OUTPUT" "$selected_name"
done

OUTFILE="$HOME/kube-grade/ckad/tasks/task7-grade.sh"
[[ -x "$OUTFILE" ]] || {
  echo "Expected generated file $OUTFILE to be executable" >&2
  exit 1
}

assert_contains "$OUTFILE" 'check_exists pod "app-pod" "$NAMESPACE"'
assert_contains "$OUTFILE" 'check_pod_ready "app-pod" "$NAMESPACE"'
assert_contains "$OUTFILE" 'check_label pod "app-pod" "$NAMESPACE" "app" "web"'
assert_contains "$OUTFILE" 'check_deploy_image "web-deploy" "$NAMESPACE" "nginx:1.27"'
assert_contains "$OUTFILE" 'check_replicas "web-deploy" "$NAMESPACE" 3'
assert_contains "$OUTFILE" 'check_service_type "web-svc" "$NAMESPACE" "ClusterIP"'
assert_contains "$OUTFILE" 'check_service_port "web-svc" "$NAMESPACE" 80 8080'
assert_contains "$OUTFILE" 'check_jsonpath configmap "app-config" "$NAMESPACE" '\''{.data.MODE}'\'' "prod" "CM MODE"'
assert_contains "$OUTFILE" 'check_secret_key "app-secret" "$NAMESPACE" "password" "s3cr3t"'
assert_contains "$OUTFILE" 'check_pvc "data-pvc" "$NAMESPACE" "1Gi" "ReadWriteOnce"'
assert_contains "$OUTFILE" 'check_rbac "build-bot" "$NAMESPACE" "get" "pods" "yes"'
assert_contains "$OUTFILE" 'check_rolebinding_role "workload-reader-bind" "$NAMESPACE" "workload-reader"'
assert_contains "$OUTFILE" 'check_cronjob "nightly" "$NAMESPACE" "*/5 * * * *" "busybox:1.36"'
assert_contains "$OUTFILE" 'check_ingress "web-ing" "$NAMESPACE" "app.example.com" "/api" "web-svc" ""'
assert_contains "$OUTFILE" 'check_netpol "allow-web" "$NAMESPACE" "app" "web"'
assert_contains "$OUTFILE" 'check_file_exists "'"$ANSWER_FILE"'"'
assert_contains "$OUTFILE" "Job 'batch-once' pod Succeeded"

GRADE_OUTPUT="$TMP_DIR/grade.out"
bash "$OUTFILE" >"$GRADE_OUTPUT" 2>&1

assert_contains "$GRADE_OUTPUT" "Context = team-a-context"
assert_contains "$GRADE_OUTPUT" "Namespace 'team-a' exists"
assert_contains "$GRADE_OUTPUT" "CronJob 'nightly' schedule = '*/5 * * * *'"
assert_contains "$GRADE_OUTPUT" "Job 'batch-once' pod Succeeded"
assert_contains "$GRADE_OUTPUT" "File '$ANSWER_FILE' exists"
assert_contains "$GRADE_OUTPUT" "100%)"
assert_not_contains "$GRADE_OUTPUT" "FAIL"
