#!/usr/bin/env bash
# =============================================================================
# kube-grade installer
# curl -sL https://raw.githubusercontent.com/kube-grade/kube-grade/main/install.sh | bash
# =============================================================================
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/kube-grade/kube-grade/main"
INSTALL_DIR="$HOME/kube-grade"
BOLD='\033[1m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'; DIM='\033[2m'; RESET='\033[0m'

_dl() {
  local src="$REPO_RAW/$1" dst="$INSTALL_DIR/$1"
  mkdir -p "$(dirname "$dst")"
  if command -v curl &>/dev/null; then curl -sL "$src" -o "$dst"
  else wget -qO "$dst" "$src"; fi
  echo -e "${DIM}  ↳ $1${RESET}"
}

echo -e "${CYAN}  Installing kube-grade...${RESET}"

# Core
_dl "lib/grade-lib.sh"
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
find "$INSTALL_DIR" -name "*.sh" -exec chmod +x {} \;

# ── Shell aliases (idempotent) ─────────────────────────────────────────────────
sed -i '/# kube-grade:begin/,/# kube-grade:end/d' ~/.bashrc 2>/dev/null || true

cat >> ~/.bashrc << 'BLOCK'
# kube-grade:begin
export KUBE_GRADE="$HOME/kube-grade"
source "$KUBE_GRADE/lib/grade-lib.sh" 2>/dev/null || true

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
  curl -sL https://raw.githubusercontent.com/kube-grade/kube-grade/main/tasks/TEMPLATE.sh \
    | sed "s/TASK_NUM/$n/g; s/EXAM_TAG/${exam:-generic}/g" > "$f"
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
# kube-grade:end
BLOCK

# shellcheck disable=SC1090
source ~/.bashrc 2>/dev/null || true

ver=$(cat "$INSTALL_DIR/VERSION" 2>/dev/null || echo "?")
echo ""
echo -e "${BOLD}${GREEN}  ✔ kube-grade v${ver} installed → $INSTALL_DIR${RESET}"
echo ""
echo -e "  ${BOLD}Quick start:${RESET}"
echo -e "  ${CYAN}source ~/kube-grade/lib/grade-lib.sh${RESET}     # load in current shell"
echo -e "  ${CYAN}new_task 3 ckad${RESET}                          # generate task3 grader for CKAD"
echo -e "  ${CYAN}kg ckad pod${RESET}                              # run pre-built pod scenario grader"
echo ""
