#!/usr/bin/env bash
# =============================================================================
# kube-grade installer
# curl -sL https://raw.githubusercontent.com/subhashsurana/kube-grade/main/install.sh | bash
# =============================================================================
set -euo pipefail

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/subhashsurana/kube-grade/main}"
INSTALL_DIR="$HOME/kube-grade"
BOLD='\033[1m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'; DIM='\033[2m'; RESET='\033[0m'

_dl() {
  local src="$REPO_RAW/$1" dst="$INSTALL_DIR/$1"
  local tmp
  mkdir -p "$(dirname "$dst")"
  tmp=$(mktemp)
  if command -v curl &>/dev/null; then
    curl -fsSL "$src" -o "$tmp"
  else
    wget -qO "$tmp" "$src"
  fi
  mv "$tmp" "$dst"
  echo -e "${DIM}  ↳ $1${RESET}"
}

echo -e "${CYAN}  Installing kube-grade...${RESET}"

# Core
_dl "lib/grade-lib.sh"
_dl "lib/grade-recipes.sh"
_dl "VERSION"
_dl "tasks/TEMPLATE.sh"

# Download scenario manifests for all exams
for exam in ckad cka cks; do
  if _dl "$exam/MANIFEST" 2>/dev/null; then
    while IFS= read -r f; do
      [[ -z "$f" || "$f" == \#* ]] && continue
      _dl "$exam/scenarios/$f"
    done < "$INSTALL_DIR/$exam/MANIFEST"
  fi
done

chmod +x "$INSTALL_DIR/lib/grade-lib.sh"
chmod +x "$INSTALL_DIR/lib/grade-recipes.sh"
find "$INSTALL_DIR" -name "*.sh" -exec chmod +x {} \;

# ── Shell aliases (idempotent) ─────────────────────────────────────────────────
sed -i '/# kube-grade:begin/,/# kube-grade:end/d' ~/.bashrc 2>/dev/null || true

cat >> ~/.bashrc << 'BLOCK'
# kube-grade:begin
export KUBE_GRADE="$HOME/kube-grade"
source "$KUBE_GRADE/lib/grade-lib.sh" 2>/dev/null || true
source "$KUBE_GRADE/lib/grade-recipes.sh" 2>/dev/null || true

# context + namespace helpers
alias kns='kubectl config set-context --current --namespace'
alias kctx='kubectl config use-context'

# kubectl shortcuts
alias k='kubectl'
alias kgp='kubectl get pods -o wide'
alias kgs='kubectl get svc'
alias kgd='kubectl get deployment'
alias kge='kubectl get events --sort-by=.metadata.creationTimestamp'
alias kdp='kubectl describe pod'
alias kaf='kubectl apply -f'
alias kdr='kubectl run --dry-run=client -o yaml'

# Generate a grading script for the current task
# Usage: new_task 5          → ~/kube-grade/tasks/task5-grade.sh
#        new_task 5 ckad     → ~/kube-grade/ckad/tasks/task5-grade.sh
new_task() {
  local n=${1:?Usage: new_task TASK_NUM [ckad|cka|cks]}
  local exam=${2:-}
  local dir="$KUBE_GRADE${exam:+/$exam}/tasks"
  local f="$dir/task${n}-grade.sh"
  mkdir -p "$dir"
  [[ -f "$f" ]] && { echo "Already exists: $f"; return; }

  # Fully inline — no curl, no network, never gets a 404
  cat > "$f" << TMPL
#!/usr/bin/env bash
# Task ${n} — kube-grade [${exam:-generic}]
# Run: bash $f
source "\$HOME/kube-grade/lib/grade-lib.sh"

# ── CONFIG — copy exact values from the task description ─────────────────────
CONTEXT="k8s-c1"
NAMESPACE="default"
DEPLOY_NAME="my-deploy"
POD_NAME="my-pod"
SVC_NAME="my-svc"
CM_NAME="my-cm"
SECRET_NAME="my-secret"
PVC_NAME="my-pvc"
SA_NAME="my-sa"
CRONJOB_NAME="my-cj"
IMAGE="nginx:1.21"
REPLICAS=1
LABEL_KEY="app"
LABEL_VAL="myapp"
OUTPUT_FILE="/opt/course/${n}/answer.txt"

# ── Context (always run first) ────────────────────────────────────────────────
_section "Context"
kubectl config use-context "\$CONTEXT" 2>/dev/null \
  && _pass "Context = \$CONTEXT" \
  || _warn "Context '\$CONTEXT' not found — using current"

_section "Namespace"
check_namespace "\$NAMESPACE"

# ── Uncomment every block that applies to this task ───────────────────────────

# -- Pod --
# check_exists      pod  "\$POD_NAME"  "\$NAMESPACE"
# check_pod_ready        "\$POD_NAME"  "\$NAMESPACE"
# check_image            "\$POD_NAME"  "\$NAMESPACE"  "\$IMAGE"
# check_label       pod  "\$POD_NAME"  "\$NAMESPACE"  "\$LABEL_KEY" "\$LABEL_VAL"

# -- Deployment --
# check_exists       deployment  "\$DEPLOY_NAME"  "\$NAMESPACE"
# check_deploy_image             "\$DEPLOY_NAME"  "\$NAMESPACE"  "\$IMAGE"
# check_replicas                 "\$DEPLOY_NAME"  "\$NAMESPACE"  "\$REPLICAS"
# check_label        deployment  "\$DEPLOY_NAME"  "\$NAMESPACE"  "\$LABEL_KEY" "\$LABEL_VAL"
# check_selector_label deployment "\$DEPLOY_NAME" "\$NAMESPACE"  "\$LABEL_KEY" "\$LABEL_VAL"

# -- Service --
# check_exists           service  "\$SVC_NAME"  "\$NAMESPACE"
# check_service_type               "\$SVC_NAME"  "\$NAMESPACE"  "ClusterIP"
# check_service_port               "\$SVC_NAME"  "\$NAMESPACE"  80  8080
# check_service_selector           "\$SVC_NAME"  "\$NAMESPACE"  "\$LABEL_KEY" "\$LABEL_VAL"
# check_service_endpoints          "\$SVC_NAME"  "\$NAMESPACE"

# -- ConfigMap + env --
# check_exists configmap "\$CM_NAME" "\$NAMESPACE"
# check_jsonpath configmap "\$CM_NAME" "\$NAMESPACE" '{.data.MY_KEY}' "my_value" "CM MY_KEY"
# check_env                "\$POD_NAME" "\$NAMESPACE" "MY_KEY" "my_value"
# check_env_from_configmap "\$POD_NAME" "\$NAMESPACE" 0 "MY_KEY" "\$CM_NAME" "MY_KEY"

# -- Secret --
# check_exists    secret         "\$SECRET_NAME"  "\$NAMESPACE"
# check_secret_key               "\$SECRET_NAME"  "\$NAMESPACE"  "password"  "s3cr3t"
# check_volume_mount "\$POD_NAME" "\$NAMESPACE"   "/etc/secret"  "\$SECRET_NAME"

# -- Resources + probes --
# check_resources "\$POD_NAME" "\$NAMESPACE" "100m" "128Mi" "200m" "256Mi"
# check_probe     "\$POD_NAME" "\$NAMESPACE" liveness  "/healthz" 8080 10
# check_probe     "\$POD_NAME" "\$NAMESPACE" readiness "/ready"   8080 5

# -- PVC --
# check_pvc          "\$PVC_NAME"  "\$NAMESPACE"  "1Gi"  "ReadWriteOnce"  "standard"
# check_volume_mount "\$POD_NAME"  "\$NAMESPACE"  "/data"  "\$PVC_NAME"

# -- RBAC --
# check_exists           serviceaccount  "\$SA_NAME"  "\$NAMESPACE"
# check_rolebinding_role   "my-rb"  "\$NAMESPACE"  "my-role"
# check_rolebinding_subject "my-rb" "\$NAMESPACE"  "\$SA_NAME"
# check_rbac  "\$SA_NAME" "\$NAMESPACE" "get"    "pods"  "yes"
# check_rbac  "\$SA_NAME" "\$NAMESPACE" "delete" "pods"  "no"

# -- CronJob --
# check_exists  cronjob "\$CRONJOB_NAME" "\$NAMESPACE"
# check_cronjob         "\$CRONJOB_NAME" "\$NAMESPACE" "*/5 * * * *" "\$IMAGE"

# -- Ingress --
# check_ingress "my-ingress" "\$NAMESPACE" "myapp.example.com" "/api" "api-svc" 80

# -- NetworkPolicy --
# check_netpol "my-netpol" "\$NAMESPACE" "app" "api"

# -- File output --
# EXPECTED=\$(kubectl get pod -n "\$NAMESPACE" -l "\$LABEL_KEY=\$LABEL_VAL" \
#   -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
# check_file_exists   "\$OUTPUT_FILE"
# check_file_contains "\$OUTPUT_FILE" "\$EXPECTED"

grade_summary
TMPL

  chmod +x "$f"
  echo "Created: $f"
  echo "Edit the CONFIG section, then: bash $f"
}

# Run a pre-built exam scenario grader
# Usage: kg ckad pod       → runs ~/kube-grade/ckad/scenarios/grade-pod.sh
#        kg cka  etcd      → runs ~/kube-grade/cka/scenarios/grade-etcd.sh
kg() {
  local exam=${1:?Usage: kg [ckad|cka|cks] SCENARIO} scenario=${2:?}
  local f="$KUBE_GRADE/$exam/scenarios/grade-${scenario}.sh"
  [[ -f "$f" ]] || { echo "Not found: $f"; ls "$KUBE_GRADE/$exam/scenarios/" 2>/dev/null; return 1; }
  bash "$f"
}

# Auto-discover cluster resources and build a grade script interactively
# Usage: kg-discover                  # scan + prompt, no file written
#        kg-discover 7 ckad           # scan + prompt + write task7-grade.sh
#        NAMESPACES="team-a" kg-discover 7 ckad   # limit to specific namespaces
kg-discover() {
  bash "$KUBE_GRADE/lib/kg-discover.sh" "$@"
}
# kube-grade:end
BLOCK

# Download kg-discover
_dl "lib/kg_discover.sh"
_dl "lib/kg-discover.sh"
chmod +x "$INSTALL_DIR/lib/kg_discover.sh"
chmod +x "$INSTALL_DIR/lib/kg-discover.sh"

# shellcheck disable=SC1090
source ~/.bashrc 2>/dev/null || true

ver=$(cat "$INSTALL_DIR/VERSION" 2>/dev/null || echo "?")
echo ""
echo -e "${BOLD}${GREEN}  ✔ kube-grade v${ver} installed → $INSTALL_DIR${RESET}"
echo ""
echo -e "  ${BOLD}Quick start:${RESET}"
echo -e "  ${CYAN}kg-discover 3 ckad${RESET}       # scan cluster → interactive prompts → generate task3-grade.sh"
echo -e "  ${CYAN}new_task 3 ckad${RESET}           # blank template if you prefer manual"
echo -e "  ${CYAN}kg ckad pod${RESET}               # run a pre-built scenario grader"
echo ""
