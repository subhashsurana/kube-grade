#!/usr/bin/env bash
# =============================================================================
# kube-grade / ckad / grade-rbac-namespace.sh
# Scenario: Namespace-scoped ServiceAccount + Role + RoleBinding RBAC
#
# Env overrides:
#   NS=default SA_NAME=task-sa ROLE_NAME=pod-reader RB_NAME=pod-reader-bind \
#   RBAC_VERB=get RBAC_RESOURCE=pods RBAC_EXPECTED=yes \
#   bash grade-rbac-namespace.sh
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
SA_NAME="${SA_NAME:-task-sa}"
ROLE_NAME="${ROLE_NAME:-pod-reader}"
RB_NAME="${RB_NAME:-pod-reader-bind}"
RBAC_VERB="${RBAC_VERB:-get}"
RBAC_RESOURCE="${RBAC_RESOURCE:-pods}"
RBAC_EXPECTED="${RBAC_EXPECTED:-yes}"

recipe_rbac_namespace
grade_summary
