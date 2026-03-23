#!/usr/bin/env bash
# =============================================================================
# kube-grade — Core Grading Library
# https://github.com/kube-grade/kube-grade
#
# Source in any grading script:
#   source <(curl -sL https://raw.githubusercontent.com/kube-grade/kube-grade/main/lib/grade-lib.sh)
#   source ~/kube-grade/lib/grade-lib.sh
# =============================================================================

[[ -n "${_KUBE_GRADE_LIB_LOADED:-}" ]] && return 0
_KUBE_GRADE_LIB_LOADED=1

_LIB_VERSION=$(cat "$(dirname "${BASH_SOURCE[0]}")/../VERSION" 2>/dev/null || echo "dev")

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

# ── Score tracking ─────────────────────────────────────────────────────────────
_KG_TOTAL=0; _KG_PASSED=0; _KG_FAILED=0; _KG_FAIL_REASONS=()

_pass()    { ((_KG_TOTAL+=1)); ((_KG_PASSED+=1)); echo -e "  ${GREEN}✔ PASS${RESET}  $1"; }
_fail()    { ((_KG_TOTAL+=1)); ((_KG_FAILED+=1)); echo -e "  ${RED}✘ FAIL${RESET}  $1"; _KG_FAIL_REASONS+=("$1"); }
_info()    { echo -e "  ${DIM}↳ $1${RESET}"; }
_warn()    { echo -e "  ${YELLOW}⚠ WARN${RESET}  $1"; }
_section() { echo -e "\n${BOLD}${CYAN}▶ $1${RESET}"; }

grade_reset() {
  _KG_TOTAL=0; _KG_PASSED=0; _KG_FAILED=0; _KG_FAIL_REASONS=()
}

grade_summary() {
  local pct=0
  [[ $_KG_TOTAL -gt 0 ]] && pct=$(( _KG_PASSED * 100 / _KG_TOTAL ))
  local color=$RED
  [[ $pct -ge 66  ]] && color=$YELLOW
  [[ $pct -eq 100 ]] && color=$GREEN
  echo -e "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${BOLD}  Score: ${color}${_KG_PASSED}/${_KG_TOTAL} (${pct}%)${RESET}"
  if [[ ${#_KG_FAIL_REASONS[@]} -gt 0 ]]; then
    echo -e "${YELLOW}  Failed:${RESET}"
    for r in "${_KG_FAIL_REASONS[@]}"; do
      echo -e "    ${RED}• $r${RESET}"
    done
  fi
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
  [[ $_KG_FAILED -eq 0 ]]
}

# =============================================================================
# PRIVATE HELPERS
# =============================================================================
_kget() { kubectl get "$1" "$2" ${3:+-n "$3"} -o jsonpath="$4" 2>/dev/null; }
_keq()  {
  if [[ "$1" == "$2" ]]; then _pass "$3 = '$2'"
  else _fail "$3 = '$1' (expected '$2')"; fi
}

# =============================================================================
# CHECK FUNCTIONS — every function prints the kubectl command it runs
# =============================================================================

# ── Existence ──────────────────────────────────────────────────────────────────
check_exists() {
  local kind=$1 name=$2 ns=${3:-}
  _info "kubectl get $kind $name${ns:+ -n $ns} --no-headers"
  kubectl get "$kind" "$name" ${ns:+-n "$ns"} --no-headers &>/dev/null \
    && _pass "$kind '$name'${ns:+ (ns: $ns)} exists" \
    || _fail "$kind '$name'${ns:+ (ns: $ns)} NOT FOUND"
}

check_namespace() {
  _info "kubectl get namespace $1"
  kubectl get namespace "$1" &>/dev/null \
    && _pass "Namespace '$1' exists" \
    || _fail "Namespace '$1' NOT FOUND"
}

# ── Pod readiness ─────────────────────────────────────────────────────────────
check_pod_ready() {
  local name=$1 ns=${2:-default}
  _info "kubectl get pod $name -n $ns -o jsonpath='{.status.phase} {.status.containerStatuses[*].ready}'"
  local phase ready
  phase=$(_kget pod "$name" "$ns" '{.status.phase}')
  ready=$(_kget pod "$name" "$ns" '{.status.containerStatuses[*].ready}')
  if [[ "$phase" == "Running" ]] && ! echo "$ready" | grep -q "false"; then
    _pass "Pod '$name' Running and all containers Ready"
  else
    _fail "Pod '$name' phase='$phase' ready='$ready'"
  fi
}

check_status() {
  local kind=$1 name=$2 ns=${3:-default} expected=$4
  local jp='{.status.phase}'
  [[ "$kind" == "deployment" ]] && jp='{.status.conditions[?(@.type=="Available")].status}'
  [[ "$kind" == "job"        ]] && jp='{.status.conditions[?(@.type=="Complete")].status}'
  _info "kubectl get $kind $name -n $ns -o jsonpath='$jp'"
  _keq "$(_kget "$kind" "$name" "$ns" "$jp")" "$expected" "$kind '$name' status"
}

# ── Image ──────────────────────────────────────────────────────────────────────
check_image() {
  local name=$1 ns=${2:-default} expected=$3 idx=${4:-0}
  _info "kubectl get pod $name -n $ns -o jsonpath='{.spec.containers[$idx].image}'"
  _keq "$(_kget pod "$name" "$ns" "{.spec.containers[$idx].image}")" "$expected" "Pod '$name' image"
}

check_deploy_image() {
  local name=$1 ns=${2:-default} expected=$3 idx=${4:-0}
  _info "kubectl get deployment $name -n $ns -o jsonpath='{.spec.template.spec.containers[$idx].image}'"
  _keq "$(_kget deployment "$name" "$ns" "{.spec.template.spec.containers[$idx].image}")" "$expected" "Deployment '$name' image"
}

# ── Labels / selectors ────────────────────────────────────────────────────────
check_label() {
  local kind=$1 name=$2 ns=${3:-default} key=$4 val=$5
  _info "kubectl get $kind $name -n $ns -o jsonpath='{.metadata.labels.$key}'"
  _keq "$(_kget "$kind" "$name" "$ns" "{.metadata.labels.$key}")" "$val" "$kind '$name' label $key"
}

check_selector_label() {
  local kind=$1 name=$2 ns=${3:-default} key=$4 val=$5
  _info "kubectl get $kind $name -n $ns -o jsonpath='{.spec.selector.matchLabels.$key}'"
  _keq "$(_kget "$kind" "$name" "$ns" "{.spec.selector.matchLabels.$key}")" "$val" "$kind '$name' selector.$key"
}

# ── Replicas ──────────────────────────────────────────────────────────────────
check_replicas() {
  local name=$1 ns=${2:-default} expected=$3
  _info "kubectl get deployment $name -n $ns -o jsonpath='{.spec.replicas}'"
  _keq "$(_kget deployment "$name" "$ns" '{.spec.replicas}')" "$expected" "Deployment '$name' replicas"
}

# ── Environment variables ─────────────────────────────────────────────────────
check_env() {
  local pod=$1 ns=${2:-default} key=$3 expected=$4
  _info "kubectl exec $pod -n $ns -- env | grep ^$key="
  local actual
  actual=$(kubectl exec "$pod" -n "$ns" -- env 2>/dev/null | grep "^${key}=" | cut -d= -f2-)
  _keq "$actual" "$expected" "Pod '$pod' env $key"
}

check_env_from_configmap() {
  local pod=$1 ns=${2:-default} idx=${3:-0} key=$4 cm=$5 cm_key=$6
  local jp="{.spec.containers[$idx].env[?(@.name=='$key')].valueFrom.configMapKeyRef}"
  _info "kubectl get pod $pod -n $ns -o jsonpath='$jp'"
  local actual; actual=$(_kget pod "$pod" "$ns" "$jp")
  if echo "$actual" | grep -q "\"name\":\"$cm\"" && echo "$actual" | grep -q "\"key\":\"$cm_key\""; then
    _pass "Pod '$pod' env '$key' sourced from ConfigMap '$cm'[$cm_key]"
  else
    _fail "Pod '$pod' env '$key' ConfigMap ref mismatch. Got: $actual"
  fi
}

check_env_from_secret() {
  local pod=$1 ns=${2:-default} idx=${3:-0} key=$4 sec=$5 sec_key=$6
  local jp="{.spec.containers[$idx].env[?(@.name=='$key')].valueFrom.secretKeyRef}"
  _info "kubectl get pod $pod -n $ns -o jsonpath='$jp'"
  local actual; actual=$(_kget pod "$pod" "$ns" "$jp")
  if echo "$actual" | grep -q "\"name\":\"$sec\"" && echo "$actual" | grep -q "\"key\":\"$sec_key\""; then
    _pass "Pod '$pod' env '$key' sourced from Secret '$sec'[$sec_key]"
  else
    _fail "Pod '$pod' env '$key' Secret ref mismatch. Got: $actual"
  fi
}

# ── Volume mounts ─────────────────────────────────────────────────────────────
check_volume_mount() {
  local pod=$1 ns=${2:-default} path=$3 vol=${4:-}
  _info "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].volumeMounts}'"
  local mounts; mounts=$(_kget pod "$pod" "$ns" '{.spec.containers[0].volumeMounts}')
  if ! echo "$mounts" | grep -q "$path"; then
    _fail "Pod '$pod' has no volumeMount at '$path'"; return
  fi
  if [[ -n "$vol" ]]; then
    echo "$mounts" | grep -q "$vol" \
      && _pass "Pod '$pod' mounts '$path' from volume '$vol'" \
      || _fail "Pod '$pod' mounts '$path' but volume '$vol' not found"
  else
    _pass "Pod '$pod' has volumeMount at '$path'"
  fi
}

# ── Secrets ───────────────────────────────────────────────────────────────────
check_secret_key() {
  local name=$1 ns=${2:-default} key=$3 expected=$4
  _info "kubectl get secret $name -n $ns -o jsonpath='{.data.$key}' | base64 -d"
  local actual; actual=$(echo "$(_kget secret "$name" "$ns" "{.data.$key}")" | base64 -d 2>/dev/null)
  _keq "$actual" "$expected" "Secret '$name'[$key] decoded"
}

# ── Services ──────────────────────────────────────────────────────────────────
check_service_type() {
  local svc=$1 ns=${2:-default} expected=$3
  _info "kubectl get svc $svc -n $ns -o jsonpath='{.spec.type}'"
  _keq "$(_kget service "$svc" "$ns" '{.spec.type}')" "$expected" "Service '$svc' type"
}

check_service_port() {
  local svc=$1 ns=${2:-default} port=$3 tp=${4:-}
  _info "kubectl get svc $svc -n $ns -o jsonpath='{.spec.ports[0].port}'"
  _keq "$(_kget service "$svc" "$ns" '{.spec.ports[0].port}')" "$port" "Service '$svc' port"
  if [[ -n "$tp" ]]; then
    _info "kubectl get svc $svc -n $ns -o jsonpath='{.spec.ports[0].targetPort}'"
    _keq "$(_kget service "$svc" "$ns" '{.spec.ports[0].targetPort}')" "$tp" "Service '$svc' targetPort"
  fi
}

check_service_selector() {
  local svc=$1 ns=${2:-default} key=$3 val=$4
  _info "kubectl get svc $svc -n $ns -o jsonpath='{.spec.selector.$key}'"
  _keq "$(_kget service "$svc" "$ns" "{.spec.selector.$key}")" "$val" "Service '$svc' selector.$key"
}

check_service_endpoints() {
  local svc=$1 ns=${2:-default}
  _info "kubectl get endpoints $svc -n $ns -o jsonpath='{.subsets[0].addresses[0].ip}'"
  local ep; ep=$(kubectl get endpoints "$svc" -n "$ns" -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null)
  [[ -n "$ep" ]] \
    && _pass "Service '$svc' has active endpoint: $ep" \
    || _fail "Service '$svc' has NO endpoints — selector may not match pod labels"
}

# ── Resource requests / limits ────────────────────────────────────────────────
check_resources() {
  local pod=$1 ns=${2:-default} cpu_req=${3:-} mem_req=${4:-} cpu_lim=${5:-} mem_lim=${6:-}
  local r=".spec.containers[0].resources"
  [[ -n "$cpu_req" ]] && {
    _info "kubectl get pod $pod -n $ns -o jsonpath='{$r.requests.cpu}'"
    _keq "$(_kget pod "$pod" "$ns" "{$r.requests.cpu}")" "$cpu_req" "CPU request"
  }
  [[ -n "$mem_req" ]] && {
    _info "kubectl get pod $pod -n $ns -o jsonpath='{$r.requests.memory}'"
    _keq "$(_kget pod "$pod" "$ns" "{$r.requests.memory}")" "$mem_req" "Memory request"
  }
  [[ -n "$cpu_lim" ]] && {
    _info "kubectl get pod $pod -n $ns -o jsonpath='{$r.limits.cpu}'"
    _keq "$(_kget pod "$pod" "$ns" "{$r.limits.cpu}")" "$cpu_lim" "CPU limit"
  }
  [[ -n "$mem_lim" ]] && {
    _info "kubectl get pod $pod -n $ns -o jsonpath='{$r.limits.memory}'"
    _keq "$(_kget pod "$pod" "$ns" "{$r.limits.memory}")" "$mem_lim" "Memory limit"
  }
}

# ── Probes ────────────────────────────────────────────────────────────────────
check_probe() {
  local pod=$1 ns=${2:-default} type=$3 path=${4:-} port=${5:-} delay=${6:-}
  local jp="{.spec.containers[0].${type}Probe}"
  _info "kubectl get pod $pod -n $ns -o jsonpath='$jp'"
  local actual; actual=$(_kget pod "$pod" "$ns" "$jp")
  if [[ -z "$actual" ]]; then _fail "Pod '$pod' has NO ${type}Probe"; return; fi
  _pass "Pod '$pod' ${type}Probe configured"
  [[ -n "$path"  ]] && { echo "$actual" | grep -q "\"path\":\"$path\""  && _pass "${type}Probe path=$path"  || _fail "${type}Probe path mismatch (expected $path). Got: $actual"; }
  [[ -n "$port"  ]] && { echo "$actual" | grep -qE "\"port\":$port|\"port\":\"$port\"" && _pass "${type}Probe port=$port" || _fail "${type}Probe port mismatch (expected $port)"; }
  [[ -n "$delay" ]] && {
    _info "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].${type}Probe.initialDelaySeconds}'"
    _keq "$(_kget pod "$pod" "$ns" "{.spec.containers[0].${type}Probe.initialDelaySeconds}")" "$delay" "${type}Probe initialDelaySeconds"
  }
}

# ── PVC ───────────────────────────────────────────────────────────────────────
check_pvc() {
  local name=$1 ns=${2:-default} size=${3:-} access=${4:-} sc=${5:-}
  check_exists pvc "$name" "$ns"
  check_status pvc "$name" "$ns" Bound
  [[ -n "$size"   ]] && { _info "kubectl get pvc $name -n $ns -o jsonpath='{.spec.resources.requests.storage}'"; _keq "$(_kget pvc "$name" "$ns" '{.spec.resources.requests.storage}')" "$size" "PVC '$name' storage"; }
  [[ -n "$access" ]] && { _info "kubectl get pvc $name -n $ns -o jsonpath='{.spec.accessModes[0]}'"; _keq "$(_kget pvc "$name" "$ns" '{.spec.accessModes[0]}')" "$access" "PVC '$name' accessMode"; }
  [[ -n "$sc"     ]] && { _info "kubectl get pvc $name -n $ns -o jsonpath='{.spec.storageClassName}'"; _keq "$(_kget pvc "$name" "$ns" '{.spec.storageClassName}')" "$sc" "PVC '$name' storageClass"; }
}

# ── RBAC ──────────────────────────────────────────────────────────────────────
check_rbac() {
  local sa=$1 ns=${2:-default} verb=$3 resource=$4 expected=${5:-yes}
  _info "kubectl auth can-i $verb $resource --as=system:serviceaccount:$ns:$sa -n $ns"
  _keq "$(kubectl auth can-i "$verb" "$resource" --as="system:serviceaccount:$ns:$sa" -n "$ns" 2>/dev/null)" "$expected" "SA '$sa' can-i $verb $resource"
}

check_rolebinding_role() {
  local rb=$1 ns=${2:-default} role=$3
  _info "kubectl get rolebinding $rb -n $ns -o jsonpath='{.roleRef.name}'"
  _keq "$(_kget rolebinding "$rb" "$ns" '{.roleRef.name}')" "$role" "RoleBinding '$rb' roleRef"
}

check_rolebinding_subject() {
  local rb=$1 ns=${2:-default} sa=$3
  _info "kubectl get rolebinding $rb -n $ns -o jsonpath='{.subjects[0].name}'"
  _keq "$(_kget rolebinding "$rb" "$ns" '{.subjects[0].name}')" "$sa" "RoleBinding '$rb' subject"
}

# ── CronJob ───────────────────────────────────────────────────────────────────
check_cronjob() {
  local name=$1 ns=${2:-default} schedule=${3:-} image=${4:-}
  check_exists cronjob "$name" "$ns"
  [[ -n "$schedule" ]] && { _info "kubectl get cronjob $name -n $ns -o jsonpath='{.spec.schedule}'"; _keq "$(_kget cronjob "$name" "$ns" '{.spec.schedule}')" "$schedule" "CronJob '$name' schedule"; }
  [[ -n "$image"    ]] && { _info "kubectl get cronjob $name -n $ns -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}'"; _keq "$(_kget cronjob "$name" "$ns" '{.spec.jobTemplate.spec.template.spec.containers[0].image}')" "$image" "CronJob '$name' image"; }
}

# ── Ingress ───────────────────────────────────────────────────────────────────
check_ingress() {
  local name=$1 ns=${2:-default} host=${3:-} path=${4:-} svc=${5:-} port=${6:-}
  check_exists ingress "$name" "$ns"
  [[ -n "$host" ]] && { _info "kubectl get ingress $name -n $ns -o jsonpath='{.spec.rules[0].host}'"; _keq "$(_kget ingress "$name" "$ns" '{.spec.rules[0].host}')" "$host" "Ingress '$name' host"; }
  [[ -n "$path" ]] && { _info "kubectl get ingress $name -n $ns -o jsonpath='{.spec.rules[0].http.paths[0].path}'"; _keq "$(_kget ingress "$name" "$ns" '{.spec.rules[0].http.paths[0].path}')" "$path" "Ingress '$name' path"; }
  [[ -n "$svc"  ]] && { _info "kubectl get ingress $name -n $ns -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}'"; _keq "$(_kget ingress "$name" "$ns" '{.spec.rules[0].http.paths[0].backend.service.name}')" "$svc" "Ingress '$name' backend svc"; }
}

# ── NetworkPolicy ─────────────────────────────────────────────────────────────
check_netpol() {
  local name=$1 ns=${2:-default} sel_key=${3:-} sel_val=${4:-}
  check_exists networkpolicy "$name" "$ns"
  if [[ -n "$sel_key" && -n "$sel_val" ]]; then
    _info "kubectl get networkpolicy $name -n $ns -o jsonpath='{.spec.podSelector.matchLabels}'"
    local sel; sel=$(_kget networkpolicy "$name" "$ns" '{.spec.podSelector.matchLabels}')
    echo "$sel" | grep -q "\"$sel_key\":\"$sel_val\"" \
      && _pass "NetworkPolicy '$name' selects $sel_key=$sel_val" \
      || _fail "NetworkPolicy '$name' podSelector mismatch. Got: $sel"
  fi
}

# ── File output ───────────────────────────────────────────────────────────────
check_file_exists() {
  _info "ls $1"
  [[ -f "$1" ]] && _pass "File '$1' exists" || _fail "File '$1' does NOT exist"
}

check_file_contains() {
  local path=$1 expected=$2
  _info "cat $path"
  [[ ! -f "$path" ]] && { _fail "Cannot check: '$path' does not exist"; return; }
  grep -qF "$expected" "$path" \
    && _pass "File '$path' contains '$expected'" \
    || _fail "File '$path' = '$(cat "$path")' (expected to contain '$expected')"
}

check_file_exact() {
  local path=$1 expected=$2
  _info "cat $path"
  [[ ! -f "$path" ]] && { _fail "Cannot check: '$path' does not exist"; return; }
  _keq "$(tr -d '\n' < "$path")" "$(echo -n "$expected" | tr -d '\n')" "File '$path' content"
}

# ── Generic jsonpath ──────────────────────────────────────────────────────────
check_jsonpath() {
  local kind=$1 name=$2 ns=${3:-default} jp=$4 expected=$5
  local desc=${6:-$jp}
  _info "kubectl get $kind $name -n $ns -o jsonpath='$jp'"
  _keq "$(_kget "$kind" "$name" "$ns" "$jp")" "$expected" "$desc"
}

echo -e "${DIM}  kube-grade v${_LIB_VERSION} loaded — $(declare -F | grep -c ' check_') check functions available${RESET}"
