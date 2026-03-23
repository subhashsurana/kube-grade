# Contributing to kube-grade

Every scenario file or check function you add directly helps someone pass their CKA, CKAD, or CKS exam. Contributions are welcome — here's the fastest path.

---

## Adding a scenario (most common)

Scenarios live in `<exam>/scenarios/grade-<slug>.sh`.

**1. Create the file** following this pattern:

```bash
#!/usr/bin/env bash
# =============================================================================
# kube-grade / ckad / grade-deployment.sh
# Scenario: Deployment with image, replicas, labels, rolling update
# Killercoda: https://killercoda.com/killer-shell-ckad/scenario/...
#
# Env overrides:
#   DEPLOY_NAME=web NS=prod IMAGE=nginx:1.21 REPLICAS=3 bash grade-deployment.sh
# =============================================================================

LIB="$HOME/kube-grade/lib/grade-lib.sh"
source "${LIB}" 2>/dev/null || \
  source <(curl -sL https://raw.githubusercontent.com/kube-grade/kube-grade/main/lib/grade-lib.sh)

DEPLOY_NAME="${DEPLOY_NAME:-web-deploy}"
NS="${NS:-default}"
IMAGE="${IMAGE:-nginx:1.21}"
REPLICAS="${REPLICAS:-3}"

_section "Deployment"
check_exists       deployment "$DEPLOY_NAME" "$NS"
check_deploy_image             "$DEPLOY_NAME" "$NS" "$IMAGE"
check_replicas                 "$DEPLOY_NAME" "$NS" "$REPLICAS"

grade_summary
```

**2. Add the filename to the exam's MANIFEST:**

```
# ckad/MANIFEST
grade-pod.sh
grade-deployment.sh     ← add here
```

**3. Open a PR.** CI will shellcheck your file and verify it's in the MANIFEST.

---

## Adding a check_ function to the core library

Edit `lib/grade-lib.sh`. Rules to follow:

| Rule | Why |
|---|---|
| Print the kubectl command with `_info "kubectl ..."` | Transparency — user sees exactly what is checked |
| Use `_kget KIND NAME NS JSONPATH` for reads | DRY — one consistent helper |
| Use `_keq ACTUAL EXPECTED DESCRIPTION` for comparisons | Consistent PASS/FAIL output |
| Accept namespace as a parameter (default `default`) | Works across all exam contexts |
| Guard against double-source with the header guard | Library is often sourced in a loop |
| Must pass `shellcheck -S warning` | CI enforces this |

---

## Commit messages

```
feat(ckad): add grade-deployment scenario
feat(lib): add check_init_container function
fix(lib): check_probe handles tcpSocket probes
fix(cka): grade-etcd-backup checks correct file path
docs: improve CONTRIBUTING examples
chore: bump VERSION to 1.2.0
```

Bump `VERSION` (semver) in the same commit as your change:
- **patch** — bug fix, doc update
- **minor** — new scenario or new `check_` function
- **major** — breaking change to a function signature

---

## Testing locally

```bash
# Lint
shellcheck -S warning lib/grade-lib.sh
shellcheck -S warning ckad/scenarios/grade-deployment.sh

# Source test
bash -c 'source lib/grade-lib.sh && echo OK'

# Against a local cluster (kind / minikube / Killercoda)
source lib/grade-lib.sh
check_exists pod nonexistent default   # should FAIL cleanly, not error
```
