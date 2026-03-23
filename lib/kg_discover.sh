#!/usr/bin/env bash
# =============================================================================
# kg-discover — Auto-discovery + interactive grade script builder
# https://github.com/subhashsurana/kube-grade
#
# Usage:
#   kg-discover                    # scan all non-kube-system namespaces
#   kg-discover 7 ckad             # scan then write task7-grade.sh
#   NAMESPACES="app-team ci" kg-discover 7 ckad   # limit to specific namespaces
#   SKIP_NS="kube-system monitoring" kg-discover   # custom skip list
# =============================================================================

set -euo pipefail

# ── Load grading lib ──────────────────────────────────────────────────────────
LIB="$HOME/kube-grade/lib/grade-lib.sh"
if [[ -f "$LIB" ]]; then
  # shellcheck source=/dev/null
  source "$LIB"
else
  # shellcheck source=/dev/null
  source <(curl -sL https://raw.githubusercontent.com/subhashsurana/kube-grade/main/lib/grade-lib.sh)
fi

# ── Colours (lib may not be sourced yet in edge cases) ────────────────────────
BOLD='\033[1m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; DIM='\033[2m'; RESET='\033[0m'
RED='\033[0;31m'

# ── Args ──────────────────────────────────────────────────────────────────────
TASK_NUM="${1:-}"
EXAM="${2:-ckad}"

# ── Config (overridable via env) ──────────────────────────────────────────────
SKIP_NS="${SKIP_NS:-kube-system kube-public kube-node-lease}"
NAMESPACES="${NAMESPACES:-}"      # if set, only scan these namespaces

# =============================================================================
# PHASE 1 — DISCOVER
# =============================================================================

echo -e "\n${BOLD}${CYAN}━━━  kube-grade discovery  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"

# Current context
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "unknown")
echo -e "  Context   : ${BOLD}${CURRENT_CONTEXT}${RESET}"

# Resolve namespace list
if [[ -n "$NAMESPACES" ]]; then
  read -r -a NS_LIST <<< "$NAMESPACES"
else
  # All namespaces minus skip list
  ALL_NS=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
  NS_LIST=()
  for ns in $ALL_NS; do
    skip=0
    for s in $SKIP_NS; do [[ "$ns" == "$s" ]] && skip=1 && break; done
    [[ $skip -eq 0 ]] && NS_LIST+=("$ns")
  done
fi

echo -e "  Namespaces: ${BOLD}${NS_LIST[*]}${RESET}"
echo -e "  Skipping  : ${DIM}${SKIP_NS}${RESET}\n"

# ── Resource type definitions ─────────────────────────────────────────────────
# FORMAT: "singular|plural|short"
RESOURCE_TYPES=(
  "pod|pods|po"
  "deployment|deployments|deploy"
  "service|services|svc"
  "configmap|configmaps|cm"
  "secret|secrets|secret"
  "persistentvolumeclaim|persistentvolumeclaims|pvc"
  "serviceaccount|serviceaccounts|sa"
  "role|roles|role"
  "rolebinding|rolebindings|rb"
  "cronjob|cronjobs|cj"
  "job|jobs|job"
  "ingress|ingresses|ing"
  "networkpolicy|networkpolicies|netpol"
  "statefulset|statefulsets|sts"
  "daemonset|daemonsets|ds"
  "replicaset|replicasets|rs"
)

# ── Scan cluster ──────────────────────────────────────────────────────────────
echo -e "${BOLD}  Scanning cluster...${RESET}"

declare -A FOUND          # FOUND[kind:ns:name] = extra info
declare -A NS_HAS         # NS_HAS[ns:kind] = count

for ns in "${NS_LIST[@]}"; do
  for rt in "${RESOURCE_TYPES[@]}"; do
    kind="${rt%%|*}"
    plural="${rt#*|}"
    plural="${plural%%|*}"

    # Get all names in this namespace for this resource type
    names=$(kubectl get "$plural" -n "$ns" \
      -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)

    [[ -z "$names" ]] && continue

    count=0
    while IFS= read -r name; do
      [[ -z "$name" ]] && continue
      ((count += 1))

      # Gather extra info per resource type
      extra=""
      case "$kind" in
        pod)
          phase=$(kubectl get pod "$name" -n "$ns" \
            -o jsonpath='{.status.phase}' 2>/dev/null)
          image=$(kubectl get pod "$name" -n "$ns" \
            -o jsonpath='{.spec.containers[0].image}' 2>/dev/null)
          extra="phase=${phase} image=${image}"
          ;;
        deployment)
          replicas=$(kubectl get deployment "$name" -n "$ns" \
            -o jsonpath='{.spec.replicas}' 2>/dev/null)
          image=$(kubectl get deployment "$name" -n "$ns" \
            -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
          extra="replicas=${replicas} image=${image}"
          ;;
        service)
          svc_type=$(kubectl get svc "$name" -n "$ns" \
            -o jsonpath='{.spec.type}' 2>/dev/null)
          port=$(kubectl get svc "$name" -n "$ns" \
            -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
          extra="type=${svc_type} port=${port}"
          ;;
        configmap)
          keys=$(kubectl get configmap "$name" -n "$ns" \
            -o jsonpath='{range .data}{@..key}{end}' 2>/dev/null \
            | tr ' ' ',')
          # fallback key extraction
          keys=$(kubectl get configmap "$name" -n "$ns" \
            -o jsonpath='{.data}' 2>/dev/null | grep -o '"[^"]*":' \
            | tr -d '":' | tr '\n' ',' | sed 's/,$//')
          extra="keys=${keys:-<empty>}"
          ;;
        secret)
          stype=$(kubectl get secret "$name" -n "$ns" \
            -o jsonpath='{.type}' 2>/dev/null)
          extra="type=${stype}"
          ;;
        persistentvolumeclaim)
          status=$(kubectl get pvc "$name" -n "$ns" \
            -o jsonpath='{.status.phase}' 2>/dev/null)
          size=$(kubectl get pvc "$name" -n "$ns" \
            -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null)
          extra="status=${status} size=${size}"
          ;;
        cronjob)
          schedule=$(kubectl get cronjob "$name" -n "$ns" \
            -o jsonpath='{.spec.schedule}' 2>/dev/null)
          image=$(kubectl get cronjob "$name" -n "$ns" \
            -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}' 2>/dev/null)
          extra="schedule='${schedule}' image=${image}"
          ;;
        ingress)
          host=$(kubectl get ingress "$name" -n "$ns" \
            -o jsonpath='{.spec.rules[0].host}' 2>/dev/null)
          extra="host=${host}"
          ;;
        statefulset)
          replicas=$(kubectl get statefulset "$name" -n "$ns" \
            -o jsonpath='{.spec.replicas}' 2>/dev/null)
          image=$(kubectl get statefulset "$name" -n "$ns" \
            -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
          extra="replicas=${replicas} image=${image}"
          ;;
        *)
          extra=""
          ;;
      esac

      FOUND["${kind}:${ns}:${name}"]="$extra"
    done <<< "$names"

    if [[ $count -gt 0 ]]; then
      NS_HAS["${ns}:${kind}"]=$count
    fi
  done
done

# ── Display discovery results ─────────────────────────────────────────────────
if [[ ${#FOUND[@]} -eq 0 ]]; then
  echo -e "  ${YELLOW}No resources found in scanned namespaces.${RESET}"
  exit 0
fi

echo -e "\n${BOLD}  Discovered resources:${RESET}\n"

# Print indexed table for selection
IDX=0
declare -a ITEM_KEYS

# Group by namespace then kind for readable output
for ns in "${NS_LIST[@]}"; do
  NS_PRINTED=0
  for rt in "${RESOURCE_TYPES[@]}"; do
    kind="${rt%%|*}"
    [[ -z "${NS_HAS[${ns}:${kind}]:-}" ]] && continue

    if [[ $NS_PRINTED -eq 0 ]]; then
      echo -e "  ${BOLD}${CYAN}namespace: ${ns}${RESET}"
      NS_PRINTED=1
    fi

    echo -e "    ${BOLD}${kind}${RESET}"
    for key in "${!FOUND[@]}"; do
      IFS=: read -r k n name <<< "$key"
      [[ "$k" != "$kind" || "$n" != "$ns" ]] && continue
      extra="${FOUND[$key]}"
      printf "      ${GREEN}[%2d]${RESET}  %-36s ${DIM}%s${RESET}\n" \
        "$IDX" "$name" "$extra"
      ITEM_KEYS[$IDX]="$key"
      ((IDX += 1))
    done
  done
done

# =============================================================================
# PHASE 2 — SELECT
# =============================================================================

echo -e "\n${BOLD}━━━  Select resources for this task  ━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "  Enter comma-separated index numbers, or ${BOLD}a${RESET} for all, or ${BOLD}q${RESET} to quit."
echo -e "  Example: ${DIM}0,2,5${RESET}\n"

read -r -p "  Your selection: " SELECTION

[[ "$SELECTION" == "q" ]] && echo "Aborted." && exit 0

SELECTED_KEYS=()
if [[ "$SELECTION" == "a" ]]; then
  SELECTED_KEYS=("${ITEM_KEYS[@]}")
else
  IFS=',' read -ra IDXS <<< "$SELECTION"
  for i in "${IDXS[@]}"; do
    i=$(echo "$i" | tr -d ' ')
    [[ -n "${ITEM_KEYS[$i]:-}" ]] && SELECTED_KEYS+=("${ITEM_KEYS[$i]}")
  done
fi

if [[ ${#SELECTED_KEYS[@]} -eq 0 ]]; then
  echo -e "  ${RED}No valid selections. Exiting.${RESET}"
  exit 1
fi

echo -e "\n  ${GREEN}Selected:${RESET}"
for k in "${SELECTED_KEYS[@]}"; do
  IFS=: read -r kind ns name <<< "$k"
  echo -e "    ${BOLD}${kind}${RESET}/${name} in ${CYAN}${ns}${RESET}"
done

# =============================================================================
# PHASE 3 — INTERACTIVE PROMPTS FOR TASK-SPECIFIC VALUES
# =============================================================================

echo -e "\n${BOLD}━━━  Task configuration  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"

# Context
read -r -p "  kubectl context (default: ${CURRENT_CONTEXT}): " INPUT_CONTEXT
TASK_CONTEXT="${INPUT_CONTEXT:-$CURRENT_CONTEXT}"

# Task number (if not passed as arg)
if [[ -z "$TASK_NUM" ]]; then
  read -r -p "  Task number (e.g. 6): " TASK_NUM
  TASK_NUM="${TASK_NUM:-1}"
fi

# Exam type
if [[ -z "${2:-}" ]]; then
  read -r -p "  Exam [ckad/cka/cks] (default: ckad): " INPUT_EXAM
  EXAM="${INPUT_EXAM:-ckad}"
fi

# Derive primary namespace from selections (most common one)
declare -A NS_COUNT
for k in "${SELECTED_KEYS[@]}"; do
  IFS=: read -r kind ns name <<< "$k"
  NS_COUNT[$ns]=$(( ${NS_COUNT[$ns]:-0} + 1 ))
done
PRIMARY_NS=$(for ns in "${!NS_COUNT[@]}"; do echo "${NS_COUNT[$ns]} $ns"; done \
  | sort -rn | head -1 | awk '{print $2}')

echo -e "  Primary namespace detected: ${BOLD}${PRIMARY_NS}${RESET}"
read -r -p "  Override namespace? (leave blank to keep '${PRIMARY_NS}'): " INPUT_NS
TASK_NS="${INPUT_NS:-$PRIMARY_NS}"

# Per-resource type extra prompts
declare -A EXTRA_VALS   # EXTRA_VALS[kind:name:field] = value

for k in "${SELECTED_KEYS[@]}"; do
  IFS=: read -r kind ns name <<< "$k"
  extra="${FOUND[$k]}"
  echo -e "\n  ${BOLD}${kind}/${name}${RESET}  ${DIM}${extra}${RESET}"

  case "$kind" in
    pod|deployment|statefulset|daemonset)
      # Extract image from discovered extra
      disc_image=$(echo "$extra" | grep -o 'image=[^ ]*' | cut -d= -f2)
      read -r -p "    Expected image [${disc_image}]: " v
      EXTRA_VALS["${kind}:${name}:image"]="${v:-$disc_image}"

      if [[ "$kind" == "deployment" || "$kind" == "statefulset" ]]; then
        disc_rep=$(echo "$extra" | grep -o 'replicas=[^ ]*' | cut -d= -f2)
        read -r -p "    Expected replicas [${disc_rep:-1}]: " v
        EXTRA_VALS["${kind}:${name}:replicas"]="${v:-${disc_rep:-1}}"
      fi

      read -r -p "    Label key=value to verify (e.g. app=web, blank to skip): " v
      if [[ -n "$v" ]]; then
        lkey="${v%%=*}"; lval="${v#*=}"
        EXTRA_VALS["${kind}:${name}:label_key"]="$lkey"
        EXTRA_VALS["${kind}:${name}:label_val"]="$lval"
      fi
      ;;

    service)
      disc_type=$(echo "$extra" | grep -o 'type=[^ ]*' | cut -d= -f2)
      disc_port=$(echo "$extra" | grep -o 'port=[^ ]*' | cut -d= -f2)
      read -r -p "    Expected type [${disc_type:-ClusterIP}]: " v
      EXTRA_VALS["${kind}:${name}:type"]="${v:-${disc_type:-ClusterIP}}"
      read -r -p "    Expected port [${disc_port:-80}]: " v
      EXTRA_VALS["${kind}:${name}:port"]="${v:-${disc_port:-80}}"
      read -r -p "    Expected targetPort (blank to skip): " v
      EXTRA_VALS["${kind}:${name}:targetport"]="$v"
      ;;

    configmap)
      read -r -p "    Key to verify (blank to skip): " v
      EXTRA_VALS["${kind}:${name}:cm_key"]="$v"
      if [[ -n "$v" ]]; then
        read -r -p "    Expected value for '${v}': " val
        EXTRA_VALS["${kind}:${name}:cm_val"]="$val"
      fi
      ;;

    secret)
      read -r -p "    Key to verify decoded value (blank to skip): " v
      EXTRA_VALS["${kind}:${name}:sec_key"]="$v"
      if [[ -n "$v" ]]; then
        read -r -p "    Expected decoded value for '${v}': " val
        EXTRA_VALS["${kind}:${name}:sec_val"]="$val"
      fi
      ;;

    persistentvolumeclaim)
      disc_size=$(echo "$extra" | grep -o 'size=[^ ]*' | cut -d= -f2)
      read -r -p "    Expected storage size [${disc_size:-1Gi}]: " v
      EXTRA_VALS["${kind}:${name}:size"]="${v:-${disc_size:-1Gi}}"
      read -r -p "    Expected accessMode [ReadWriteOnce]: " v
      EXTRA_VALS["${kind}:${name}:access"]="${v:-ReadWriteOnce}"
      ;;

    cronjob)
      disc_sched=$(echo "$extra" | grep -o "schedule='[^']*'" | cut -d= -f2 | tr -d "'")
      disc_image=$(echo "$extra" | grep -o 'image=[^ ]*' | cut -d= -f2)
      read -r -p "    Expected schedule [${disc_sched}]: " v
      EXTRA_VALS["${kind}:${name}:schedule"]="${v:-$disc_sched}"
      read -r -p "    Expected image [${disc_image}]: " v
      EXTRA_VALS["${kind}:${name}:image"]="${v:-$disc_image}"
      ;;

    serviceaccount)
      read -r -p "    Verify RBAC can-i? verb resource (e.g. get pods, blank to skip): " v
      EXTRA_VALS["${kind}:${name}:rbac"]="$v"
      ;;

    ingress)
      disc_host=$(echo "$extra" | grep -o 'host=[^ ]*' | cut -d= -f2)
      read -r -p "    Expected host [${disc_host}]: " v
      EXTRA_VALS["${kind}:${name}:host"]="${v:-$disc_host}"
      read -r -p "    Expected path (e.g. /api, blank to skip): " v
      EXTRA_VALS["${kind}:${name}:path"]="$v"
      read -r -p "    Expected backend service name (blank to skip): " v
      EXTRA_VALS["${kind}:${name}:backend"]="$v"
      ;;

    networkpolicy)
      read -r -p "    Pod selector key=value (e.g. app=api, blank to skip): " v
      if [[ -n "$v" ]]; then
        EXTRA_VALS["${kind}:${name}:sel_key"]="${v%%=*}"
        EXTRA_VALS["${kind}:${name}:sel_val"]="${v#*=}"
      fi
      ;;

    rolebinding)
      read -r -p "    Expected roleRef name (blank to skip): " v
      EXTRA_VALS["${kind}:${name}:roleref"]="$v"
      ;;

    *)
      ;;
  esac
done

# File output task?
echo ""
read -r -p "  Does this task write output to a file? [y/N]: " HAS_OUTPUT
HAS_OUTPUT="${HAS_OUTPUT:-n}"
OUTPUT_FILE=""
if [[ "${HAS_OUTPUT,,}" == "y" ]]; then
  read -r -p "  Output file path (e.g. /opt/course/${TASK_NUM}/answer.txt): " OUTPUT_FILE
  OUTPUT_FILE="${OUTPUT_FILE:-/opt/course/${TASK_NUM}/answer.txt}"
fi

# =============================================================================
# PHASE 4 — GENERATE GRADE SCRIPT
# =============================================================================

OUTDIR="$HOME/kube-grade${EXAM:+/$EXAM}/tasks"
mkdir -p "$OUTDIR"
OUTFILE="$OUTDIR/task${TASK_NUM}-grade.sh"

echo -e "\n${BOLD}━━━  Generating grade script  ━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

{
cat << HEADER
#!/usr/bin/env bash
# =============================================================================
# Task ${TASK_NUM} — auto-generated by kg-discover [${EXAM}]
# Context : ${TASK_CONTEXT}
# NS      : ${TASK_NS}
# Resources: $(for k in "${SELECTED_KEYS[@]}"; do IFS=: read -r ki ns na <<< "$k"; printf "%s/%s " "$ki" "$na"; done)
# Run: bash ${OUTFILE}
# =============================================================================
source "\$HOME/kube-grade/lib/grade-lib.sh"

CONTEXT="${TASK_CONTEXT}"
NAMESPACE="${TASK_NS}"

_section "Context"
kubectl config use-context "\$CONTEXT" 2>/dev/null \\
  && _pass "Context = \$CONTEXT" \\
  || _warn "Context '\$CONTEXT' not found — using current"

_section "Namespace"
check_namespace "\$NAMESPACE"

HEADER

# ── Emit checks for each selected resource ────────────────────────────────────
for k in "${SELECTED_KEYS[@]}"; do
  IFS=: read -r kind ns name <<< "$k"

  echo ""
  echo "_section \"${kind^}: ${name}\""
  echo "check_exists ${kind} \"${name}\" \"\$NAMESPACE\""

  case "$kind" in
    pod)
      echo "check_pod_ready \"${name}\" \"\$NAMESPACE\""
      img="${EXTRA_VALS[${kind}:${name}:image]:-}"
      [[ -n "$img" ]] && echo "check_image \"${name}\" \"\$NAMESPACE\" \"${img}\""
      lk="${EXTRA_VALS[${kind}:${name}:label_key]:-}"
      lv="${EXTRA_VALS[${kind}:${name}:label_val]:-}"
      [[ -n "$lk" ]] && echo "check_label pod \"${name}\" \"\$NAMESPACE\" \"${lk}\" \"${lv}\""
      ;;

    deployment)
      echo "check_deploy_image \"${name}\" \"\$NAMESPACE\" \"${EXTRA_VALS[${kind}:${name}:image]:-}\""
      rep="${EXTRA_VALS[${kind}:${name}:replicas]:-}"
      [[ -n "$rep" ]] && echo "check_replicas \"${name}\" \"\$NAMESPACE\" ${rep}"
      lk="${EXTRA_VALS[${kind}:${name}:label_key]:-}"
      lv="${EXTRA_VALS[${kind}:${name}:label_val]:-}"
      [[ -n "$lk" ]] && {
        echo "check_label deployment \"${name}\" \"\$NAMESPACE\" \"${lk}\" \"${lv}\""
        echo "check_selector_label deployment \"${name}\" \"\$NAMESPACE\" \"${lk}\" \"${lv}\""
      }
      ;;

    statefulset)
      echo "check_jsonpath statefulset \"${name}\" \"\$NAMESPACE\" '{.spec.template.spec.containers[0].image}' \"${EXTRA_VALS[${kind}:${name}:image]:-}\" \"StatefulSet '${name}' image\""
      rep="${EXTRA_VALS[${kind}:${name}:replicas]:-}"
      [[ -n "$rep" ]] && echo "check_jsonpath statefulset \"${name}\" \"\$NAMESPACE\" '{.spec.replicas}' \"${rep}\" \"StatefulSet '${name}' replicas\""
      lk="${EXTRA_VALS[${kind}:${name}:label_key]:-}"
      lv="${EXTRA_VALS[${kind}:${name}:label_val]:-}"
      [[ -n "$lk" ]] && {
        echo "check_label statefulset \"${name}\" \"\$NAMESPACE\" \"${lk}\" \"${lv}\""
        echo "check_selector_label statefulset \"${name}\" \"\$NAMESPACE\" \"${lk}\" \"${lv}\""
      }
      ;;

    daemonset)
      img="${EXTRA_VALS[${kind}:${name}:image]:-}"
      [[ -n "$img" ]] && echo "check_jsonpath daemonset \"${name}\" \"\$NAMESPACE\" '{.spec.template.spec.containers[0].image}' \"${img}\" \"DaemonSet '${name}' image\""
      lk="${EXTRA_VALS[${kind}:${name}:label_key]:-}"
      lv="${EXTRA_VALS[${kind}:${name}:label_val]:-}"
      [[ -n "$lk" ]] && {
        echo "check_label daemonset \"${name}\" \"\$NAMESPACE\" \"${lk}\" \"${lv}\""
        echo "check_selector_label daemonset \"${name}\" \"\$NAMESPACE\" \"${lk}\" \"${lv}\""
      }
      ;;

    service)
      stype="${EXTRA_VALS[${kind}:${name}:type]:-ClusterIP}"
      port="${EXTRA_VALS[${kind}:${name}:port]:-80}"
      tp="${EXTRA_VALS[${kind}:${name}:targetport]:-}"
      echo "check_service_type \"${name}\" \"\$NAMESPACE\" \"${stype}\""
      echo "check_service_port \"${name}\" \"\$NAMESPACE\" ${port}${tp:+ ${tp}}"
      echo "check_service_endpoints \"${name}\" \"\$NAMESPACE\""
      ;;

    configmap)
      ck="${EXTRA_VALS[${kind}:${name}:cm_key]:-}"
      cv="${EXTRA_VALS[${kind}:${name}:cm_val]:-}"
      [[ -n "$ck" ]] && \
        echo "check_jsonpath configmap \"${name}\" \"\$NAMESPACE\" '{.data.${ck}}' \"${cv}\" \"CM ${ck}\""
      ;;

    secret)
      sk="${EXTRA_VALS[${kind}:${name}:sec_key]:-}"
      sv="${EXTRA_VALS[${kind}:${name}:sec_val]:-}"
      [[ -n "$sk" ]] && \
        echo "check_secret_key \"${name}\" \"\$NAMESPACE\" \"${sk}\" \"${sv}\""
      ;;

    persistentvolumeclaim)
      sz="${EXTRA_VALS[${kind}:${name}:size]:-}"
      ac="${EXTRA_VALS[${kind}:${name}:access]:-}"
      echo "check_pvc \"${name}\" \"\$NAMESPACE\" \"${sz}\" \"${ac}\""
      ;;

    cronjob)
      sched="${EXTRA_VALS[${kind}:${name}:schedule]:-}"
      img="${EXTRA_VALS[${kind}:${name}:image]:-}"
      echo "check_cronjob \"${name}\" \"\$NAMESPACE\" \"${sched}\" \"${img}\""
      echo ""
      echo "# Verify a Job has been spawned (wait 1-2 mins after creation)"
      cat << 'CJBLOCK'
_info "kubectl get jobs -n $NAMESPACE"
JOB=$(kubectl get jobs -n "$NAMESPACE" \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -n "$JOB" ]]; then
  _pass "Job '$JOB' spawned by CronJob"
  POD=$(kubectl get pod -n "$NAMESPACE" -l "job-name=$JOB" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [[ -n "$POD" ]]; then
    PHASE=$(kubectl get pod "$POD" -n "$NAMESPACE" \
      -o jsonpath='{.status.phase}' 2>/dev/null)
    [[ "$PHASE" == "Succeeded" ]] \
      && _pass "CronJob pod '$POD' Succeeded" \
      || _warn "CronJob pod '$POD' phase='$PHASE' (re-run in 1 min if Pending)"
  fi
else
  _warn "No Jobs yet — CronJob may not have triggered. Re-run in 1-2 minutes."
fi
CJBLOCK
      ;;

    serviceaccount)
      rbac="${EXTRA_VALS[${kind}:${name}:rbac]:-}"
      if [[ -n "$rbac" ]]; then
        verb="${rbac%% *}"
        resource="${rbac##* }"
        echo "check_rbac \"${name}\" \"\$NAMESPACE\" \"${verb}\" \"${resource}\" \"yes\""
      fi
      ;;

    role)
      ;;

    rolebinding)
      roleref="${EXTRA_VALS[${kind}:${name}:roleref]:-}"
      [[ -n "$roleref" ]] && \
        echo "check_rolebinding_role \"${name}\" \"\$NAMESPACE\" \"${roleref}\""
      ;;

    ingress)
      host="${EXTRA_VALS[${kind}:${name}:host]:-}"
      path="${EXTRA_VALS[${kind}:${name}:path]:-}"
      backend="${EXTRA_VALS[${kind}:${name}:backend]:-}"
      echo "check_ingress \"${name}\" \"\$NAMESPACE\" \"${host}\" \"${path}\" \"${backend}\" \"\""
      ;;

    networkpolicy)
      sk="${EXTRA_VALS[${kind}:${name}:sel_key]:-}"
      sv="${EXTRA_VALS[${kind}:${name}:sel_val]:-}"
      echo "check_netpol \"${name}\" \"\$NAMESPACE\" \"${sk}\" \"${sv}\""
      ;;

    job)
      echo ""
      echo "_info \"kubectl get pod -n \$NAMESPACE -l job-name=${name}\""
      cat << JOBBLOCK
POD=\$(kubectl get pod -n "\$NAMESPACE" -l "job-name=${name}" \\
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -n "\$POD" ]]; then
  PHASE=\$(kubectl get pod "\$POD" -n "\$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "\$PHASE" == "Succeeded" ]] \\
    && _pass "Job '${name}' pod Succeeded" \\
    || _fail "Job '${name}' pod phase='\$PHASE' (expected Succeeded)"
else
  _fail "No pod found for Job '${name}'"
fi
JOBBLOCK
      ;;
  esac
done

# ── File output block ──────────────────────────────────────────────────────────
if [[ -n "$OUTPUT_FILE" ]]; then
  cat << FILEBLOCK

_section "File output"
check_file_exists "${OUTPUT_FILE}"
# Update EXPECTED below to match what the task expects in the file:
# EXPECTED=\$(kubectl get pod -n "\$NAMESPACE" -l "app=myapp" \\
#   -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
# check_file_contains "${OUTPUT_FILE}" "\$EXPECTED"
FILEBLOCK
fi

echo ""
echo "grade_summary"

} > "$OUTFILE"

chmod +x "$OUTFILE"

# =============================================================================
# DONE
# =============================================================================
echo -e "\n  ${GREEN}✔ Created:${RESET} ${BOLD}${OUTFILE}${RESET}"
echo -e "  ${DIM}Review and run: bash ${OUTFILE}${RESET}\n"
