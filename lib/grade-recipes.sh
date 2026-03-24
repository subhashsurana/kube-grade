#!/usr/bin/env bash
# =============================================================================
# kube-grade — Reusable Grading Recipes
# Source in scenario wrappers or one-off task scripts.
# =============================================================================

[[ -n "${_KUBE_GRADE_RECIPES_LOADED:-}" ]] && return 0
_KUBE_GRADE_RECIPES_LOADED=1

if [[ -z "${_KUBE_GRADE_LIB_LOADED:-}" ]]; then
  RECIPES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  LIB="$RECIPES_DIR/grade-lib.sh"
  if [[ -f "$LIB" ]]; then
    # shellcheck source=/dev/null
    source "$LIB"
  else
    # shellcheck source=/dev/null
    source <(curl -sL https://raw.githubusercontent.com/subhashsurana/kube-grade/main/lib/grade-lib.sh)
  fi
fi

_kg_first_set() {
  local value
  for value in "$@"; do
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      break
    fi
  done
  return 0
}

_kg_ns() {
  printf '%s' "${NS:-${NAMESPACE:-default}}"
}

_kg_truthy() {
  case "${1:-}" in
    1|true|TRUE|True|yes|YES|Yes|y|Y|on|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

_kg_check_jsonpath_if_set() {
  local kind=$1 name=$2 ns=$3 jp=$4 expected=$5 desc=$6
  [[ -n "$name" && -n "$expected" ]] && check_jsonpath "$kind" "$name" "$ns" "$jp" "$expected" "$desc"
}

recipe_deployment_service() {
  local ns deploy_name svc_name image replicas label_key label_val svc_type svc_port svc_target_port

  ns=$(_kg_ns)
  deploy_name=$(_kg_first_set "${DEPLOY_NAME:-}" "${DEPLOYMENT_NAME:-}")
  svc_name=$(_kg_first_set "${SVC_NAME:-}" "${SERVICE_NAME:-}")
  image="${IMAGE:-}"
  replicas="${REPLICAS:-}"
  label_key="${LABEL_KEY:-}"
  label_val="${LABEL_VAL:-}"
  svc_type="${SVC_TYPE:-}"
  svc_port="${SVC_PORT:-}"
  svc_target_port="${SVC_TARGET_PORT:-}"

  if [[ -n "$deploy_name" ]]; then
    _section "Deployment"
    check_exists deployment "$deploy_name" "$ns"
    [[ -n "$image" ]] && check_deploy_image "$deploy_name" "$ns" "$image"
    [[ -n "$replicas" ]] && check_replicas "$deploy_name" "$ns" "$replicas"
    if [[ -n "$label_key" && -n "$label_val" ]]; then
      check_label deployment "$deploy_name" "$ns" "$label_key" "$label_val"
      check_selector_label deployment "$deploy_name" "$ns" "$label_key" "$label_val"
    fi
  fi

  if [[ -n "$svc_name" ]]; then
    _section "Service"
    check_exists service "$svc_name" "$ns"
    [[ -n "$svc_type" ]] && check_service_type "$svc_name" "$ns" "$svc_type"
    [[ -n "$svc_port" ]] && check_service_port "$svc_name" "$ns" "$svc_port" "$svc_target_port"
    if [[ -n "$label_key" && -n "$label_val" ]]; then
      check_service_selector "$svc_name" "$ns" "$label_key" "$label_val"
    fi
    _kg_truthy "${EXPECT_SERVICE_ENDPOINTS:-}" && check_service_endpoints "$svc_name" "$ns"
  fi
}

recipe_deployment_service_ingress() {
  local ns ingress_name ingress_host ingress_path ingress_backend ingress_port

  ns=$(_kg_ns)
  recipe_deployment_service

  ingress_name=$(_kg_first_set "${INGRESS_NAME:-}" "${ING_NAME:-}")
  ingress_host="${INGRESS_HOST:-}"
  ingress_path="${INGRESS_PATH:-}"
  ingress_backend=$(_kg_first_set "${INGRESS_BACKEND_SVC:-}" "${INGRESS_SERVICE_NAME:-}" "${SVC_NAME:-}" "${SERVICE_NAME:-}")
  ingress_port=$(_kg_first_set "${INGRESS_BACKEND_PORT:-}" "${INGRESS_PORT:-}" "${SVC_PORT:-}")

  if [[ -n "$ingress_name" ]]; then
    _section "Ingress"
    check_ingress "$ingress_name" "$ns" "$ingress_host" "$ingress_path" "$ingress_backend" "$ingress_port"
  fi
}

recipe_configmap_secret_env() {
  local ns pod_name cm_name cm_key cm_val secret_name secret_key secret_val env_idx env_key env_val
  local cm_env_key cm_ref_key secret_env_key secret_ref_key secret_mount_path

  ns=$(_kg_ns)
  pod_name="${POD_NAME:-}"
  cm_name=$(_kg_first_set "${CM_NAME:-}" "${CONFIGMAP_NAME:-}")
  cm_key="${CM_KEY:-}"
  cm_val=$(_kg_first_set "${CM_VAL:-}" "${CM_VALUE:-}")
  secret_name="${SECRET_NAME:-}"
  secret_key="${SECRET_KEY:-}"
  secret_val=$(_kg_first_set "${SECRET_VAL:-}" "${SECRET_VALUE:-}")
  env_idx="${ENV_CONTAINER_IDX:-${CONTAINER_IDX:-0}}"
  env_key="${ENV_KEY:-}"
  env_val=$(_kg_first_set "${ENV_VAL:-}" "${ENV_VALUE:-}")
  cm_env_key=$(_kg_first_set "${CM_ENV_KEY:-}" "${ENV_FROM_CONFIGMAP_KEY:-}" "${ENV_KEY:-}")
  cm_ref_key=$(_kg_first_set "${CM_ENV_SOURCE_KEY:-}" "${CM_KEY:-}")
  secret_env_key=$(_kg_first_set "${SECRET_ENV_KEY:-}" "${ENV_FROM_SECRET_KEY:-}" "${ENV_KEY:-}")
  secret_ref_key=$(_kg_first_set "${SECRET_ENV_SOURCE_KEY:-}" "${SECRET_KEY:-}")
  secret_mount_path="${SECRET_MOUNT_PATH:-}"

  if [[ -n "$cm_name" ]]; then
    _section "ConfigMap"
    check_exists configmap "$cm_name" "$ns"
    if [[ -n "$cm_key" && -n "$cm_val" ]]; then
      check_jsonpath configmap "$cm_name" "$ns" "{.data.${cm_key}}" "$cm_val" "ConfigMap '$cm_name' data.${cm_key}"
    fi
  fi

  if [[ -n "$secret_name" ]]; then
    _section "Secret"
    check_exists secret "$secret_name" "$ns"
    [[ -n "$secret_key" && -n "$secret_val" ]] && check_secret_key "$secret_name" "$ns" "$secret_key" "$secret_val"
  fi

  if [[ -n "$pod_name" ]]; then
    _section "Pod Env"
    check_exists pod "$pod_name" "$ns"
    [[ -n "$env_key" && -n "$env_val" ]] && check_env "$pod_name" "$ns" "$env_key" "$env_val"
    [[ -n "$cm_name" && -n "$cm_env_key" && -n "$cm_ref_key" ]] && check_env_from_configmap "$pod_name" "$ns" "$env_idx" "$cm_env_key" "$cm_name" "$cm_ref_key"
    [[ -n "$secret_name" && -n "$secret_env_key" && -n "$secret_ref_key" ]] && check_env_from_secret "$pod_name" "$ns" "$env_idx" "$secret_env_key" "$secret_name" "$secret_ref_key"
    [[ -n "$secret_mount_path" && -n "$secret_name" ]] && check_volume_mount "$pod_name" "$ns" "$secret_mount_path"
  fi
}

recipe_pvc_pod() {
  local ns pvc_name pvc_size pvc_access pvc_storage_class pod_name image mount_path volume_name

  ns=$(_kg_ns)
  pvc_name=$(_kg_first_set "${PVC_NAME:-}" "${CLAIM_NAME:-}")
  pvc_size="${PVC_SIZE:-}"
  pvc_access=$(_kg_first_set "${PVC_ACCESS_MODE:-}" "${PVC_ACCESS:-}")
  pvc_storage_class=$(_kg_first_set "${PVC_STORAGE_CLASS:-}" "${STORAGECLASS_NAME:-}" "${STORAGECLASS:-}")
  pod_name="${POD_NAME:-}"
  image="${IMAGE:-}"
  mount_path=$(_kg_first_set "${MOUNT_PATH:-}" "${PVC_MOUNT_PATH:-}")
  volume_name="${POD_VOLUME_NAME:-}"

  if [[ -n "$pvc_name" ]]; then
    _section "PVC"
    check_pvc "$pvc_name" "$ns" "$pvc_size" "$pvc_access" "$pvc_storage_class"
  fi

  if [[ -n "$pod_name" ]]; then
    _section "Pod"
    check_exists pod "$pod_name" "$ns"
    _kg_truthy "${EXPECT_POD_READY:-}" && check_pod_ready "$pod_name" "$ns"
    [[ -n "$image" ]] && check_image "$pod_name" "$ns" "$image"
    [[ -n "$mount_path" ]] && check_volume_mount "$pod_name" "$ns" "$mount_path" "$volume_name"
  fi
}

recipe_storageclass_pvc() {
  local ns storageclass_name provisioner default_class binding_mode reclaim_policy pvc_name pvc_size pvc_access

  ns=$(_kg_ns)
  storageclass_name=$(_kg_first_set "${STORAGECLASS_NAME:-}" "${STORAGECLASS:-}")
  provisioner="${STORAGECLASS_PROVISIONER:-}"
  default_class="${STORAGECLASS_DEFAULT:-}"
  binding_mode="${STORAGECLASS_BINDING_MODE:-}"
  reclaim_policy="${STORAGECLASS_RECLAIM_POLICY:-}"
  pvc_name=$(_kg_first_set "${PVC_NAME:-}" "${CLAIM_NAME:-}")
  pvc_size="${PVC_SIZE:-}"
  pvc_access=$(_kg_first_set "${PVC_ACCESS_MODE:-}" "${PVC_ACCESS:-}")

  if [[ -n "$storageclass_name" ]]; then
    _section "StorageClass"
    check_storageclass "$storageclass_name" "$provisioner" "$default_class" "$binding_mode" "$reclaim_policy"
  fi

  if [[ -n "$pvc_name" ]]; then
    _section "PVC"
    check_pvc "$pvc_name" "$ns" "$pvc_size" "$pvc_access" "$storageclass_name"
    _kg_check_jsonpath_if_set pvc "$pvc_name" "$ns" '{.spec.storageClassName}' "$storageclass_name" "PVC '$pvc_name' storageClass"
  fi
}

recipe_cronjob_advanced() {
  local ns cronjob_name schedule image command_0 command_1 command_2 active_deadline backoff_limit
  local completions parallelism ttl_seconds suspend concurrency_policy success_history failed_history
  local job_name actual

  ns=$(_kg_ns)
  cronjob_name=$(_kg_first_set "${CRONJOB_NAME:-}" "${CJ_NAME:-}")
  schedule=$(_kg_first_set "${SCHEDULE:-}" "${CRON_SCHEDULE:-}")
  image="${IMAGE:-}"
  command_0="${COMMAND_0:-}"
  command_1="${COMMAND_1:-}"
  command_2=$(_kg_first_set "${COMMAND_2:-}" "${COMMAND:-}")
  active_deadline=$(_kg_first_set "${JOB_ACTIVE_DEADLINE_SECONDS:-}" "${ACTIVE_DEADLINE_SECONDS:-}")
  backoff_limit=$(_kg_first_set "${JOB_BACKOFF_LIMIT:-}" "${BACKOFF_LIMIT:-}")
  completions=$(_kg_first_set "${JOB_COMPLETIONS:-}" "${COMPLETIONS:-}")
  parallelism=$(_kg_first_set "${JOB_PARALLELISM:-}" "${PARALLELISM:-}")
  ttl_seconds=$(_kg_first_set "${JOB_TTL_SECONDS_AFTER_FINISHED:-}" "${TTL_SECONDS_AFTER_FINISHED:-}" "${TTL_SECONDS:-}")
  suspend="${CRONJOB_SUSPEND:-}"
  concurrency_policy="${CRONJOB_CONCURRENCY_POLICY:-}"
  success_history="${CRONJOB_SUCCESS_HISTORY_LIMIT:-}"
  failed_history="${CRONJOB_FAILED_HISTORY_LIMIT:-}"

  [[ -z "$cronjob_name" ]] && return 0

  _section "CronJob"
  check_cronjob "$cronjob_name" "$ns" "$schedule" "$image"
  _kg_check_jsonpath_if_set cronjob "$cronjob_name" "$ns" '{.spec.jobTemplate.spec.template.spec.containers[0].command[0]}' "$command_0" "CronJob '$cronjob_name' command[0]"
  _kg_check_jsonpath_if_set cronjob "$cronjob_name" "$ns" '{.spec.jobTemplate.spec.template.spec.containers[0].command[1]}' "$command_1" "CronJob '$cronjob_name' command[1]"
  _kg_check_jsonpath_if_set cronjob "$cronjob_name" "$ns" '{.spec.jobTemplate.spec.template.spec.containers[0].command[2]}' "$command_2" "CronJob '$cronjob_name' command[2]"
  _kg_check_jsonpath_if_set cronjob "$cronjob_name" "$ns" '{.spec.jobTemplate.spec.activeDeadlineSeconds}' "$active_deadline" "CronJob '$cronjob_name' activeDeadlineSeconds"
  _kg_check_jsonpath_if_set cronjob "$cronjob_name" "$ns" '{.spec.jobTemplate.spec.backoffLimit}' "$backoff_limit" "CronJob '$cronjob_name' backoffLimit"
  _kg_check_jsonpath_if_set cronjob "$cronjob_name" "$ns" '{.spec.jobTemplate.spec.completions}' "$completions" "CronJob '$cronjob_name' completions"
  _kg_check_jsonpath_if_set cronjob "$cronjob_name" "$ns" '{.spec.jobTemplate.spec.parallelism}' "$parallelism" "CronJob '$cronjob_name' parallelism"
  _kg_check_jsonpath_if_set cronjob "$cronjob_name" "$ns" '{.spec.jobTemplate.spec.ttlSecondsAfterFinished}' "$ttl_seconds" "CronJob '$cronjob_name' ttlSecondsAfterFinished"
  _kg_check_jsonpath_if_set cronjob "$cronjob_name" "$ns" '{.spec.suspend}' "$(_knorm_bool "$suspend")" "CronJob '$cronjob_name' suspend"
  _kg_check_jsonpath_if_set cronjob "$cronjob_name" "$ns" '{.spec.concurrencyPolicy}' "$concurrency_policy" "CronJob '$cronjob_name' concurrencyPolicy"
  _kg_check_jsonpath_if_set cronjob "$cronjob_name" "$ns" '{.spec.successfulJobsHistoryLimit}' "$success_history" "CronJob '$cronjob_name' successfulJobsHistoryLimit"
  _kg_check_jsonpath_if_set cronjob "$cronjob_name" "$ns" '{.spec.failedJobsHistoryLimit}' "$failed_history" "CronJob '$cronjob_name' failedJobsHistoryLimit"

  if _kg_truthy "${CHECK_CRONJOB_RUNTIME:-}"; then
    _section "CronJob Runtime"
    _info "kubectl get jobs -n $ns -l cronjob-name=$cronjob_name -o jsonpath='{.items[0].metadata.name}'"
    job_name=$(kubectl get jobs -n "$ns" -l "cronjob-name=$cronjob_name" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [[ -z "$job_name" ]]; then
      _fail "CronJob '$cronjob_name' has no spawned Jobs"
      return
    fi
    _pass "CronJob '$cronjob_name' spawned Job '$job_name'"

    [[ -n "$completions" ]] && {
      _info "kubectl get job $job_name -n $ns -o jsonpath='{.spec.completions}'"
      _keq "$(_kget job "$job_name" "$ns" '{.spec.completions}')" "$completions" "Job '$job_name' completions"
    }
    [[ -n "$parallelism" ]] && {
      _info "kubectl get job $job_name -n $ns -o jsonpath='{.spec.parallelism}'"
      _keq "$(_kget job "$job_name" "$ns" '{.spec.parallelism}')" "$parallelism" "Job '$job_name' parallelism"
    }
    [[ -n "$backoff_limit" ]] && {
      _info "kubectl get job $job_name -n $ns -o jsonpath='{.spec.backoffLimit}'"
      _keq "$(_kget job "$job_name" "$ns" '{.spec.backoffLimit}')" "$backoff_limit" "Job '$job_name' backoffLimit"
    }
    [[ -n "$ttl_seconds" ]] && {
      _info "kubectl get job $job_name -n $ns -o jsonpath='{.spec.ttlSecondsAfterFinished}'"
      _keq "$(_kget job "$job_name" "$ns" '{.spec.ttlSecondsAfterFinished}')" "$ttl_seconds" "Job '$job_name' ttlSecondsAfterFinished"
    }

    actual=$(_kget job "$job_name" "$ns" '{.status.succeeded}')
    if [[ -n "${EXPECTED_SUCCEEDED_PODS:-}" ]]; then
      _info "kubectl get job $job_name -n $ns -o jsonpath='{.status.succeeded}'"
      _keq "$actual" "${EXPECTED_SUCCEEDED_PODS}" "Job '$job_name' succeeded pods"
    fi

    if _kg_truthy "${CHECK_TTL_CLEANUP:-}" && [[ -n "$ttl_seconds" ]]; then
      local wait_seconds
      wait_seconds=$(( ttl_seconds + ${TTL_GRACE_SECONDS:-5} ))
      _info "sleep $wait_seconds"
      sleep "$wait_seconds"
      _info "kubectl get job $job_name -n $ns --no-headers"
      kubectl get job "$job_name" -n "$ns" --no-headers &>/dev/null \
        && _fail "Job '$job_name' still exists after ttlSecondsAfterFinished=${ttl_seconds}" \
        || _pass "Job '$job_name' cleaned up after ttlSecondsAfterFinished=${ttl_seconds}"
    fi
  fi
}

recipe_rbac_namespace() {
  local ns sa_name role_name rb_name verb resource expected

  ns=$(_kg_ns)
  sa_name=$(_kg_first_set "${SA_NAME:-}" "${SERVICEACCOUNT_NAME:-}")
  role_name="${ROLE_NAME:-}"
  rb_name=$(_kg_first_set "${RB_NAME:-}" "${ROLEBINDING_NAME:-}")
  verb=$(_kg_first_set "${RBAC_VERB:-}" "${CAN_I_VERB:-}")
  resource=$(_kg_first_set "${RBAC_RESOURCE:-}" "${CAN_I_RESOURCE:-}")
  expected=$(_kg_first_set "${RBAC_EXPECTED:-}" "yes")

  [[ -n "$sa_name" ]] && { _section "ServiceAccount"; check_exists serviceaccount "$sa_name" "$ns"; }
  [[ -n "$role_name" ]] && { _section "Role"; check_exists role "$role_name" "$ns"; }
  if [[ -n "$rb_name" ]]; then
    _section "RoleBinding"
    check_exists rolebinding "$rb_name" "$ns"
    [[ -n "$role_name" ]] && check_rolebinding_role "$rb_name" "$ns" "$role_name"
    [[ -n "$sa_name" ]] && check_rolebinding_subject "$rb_name" "$ns" "$sa_name"
  fi
  [[ -n "$sa_name" && -n "$verb" && -n "$resource" ]] && {
    _section "RBAC"
    check_rbac "$sa_name" "$ns" "$verb" "$resource" "$expected"
  }
}

recipe_rbac_cluster() {
  local check_ns clusterrole_name clusterrolebinding_name subject_kind subject_name subject_ns verb resource api_group expected

  check_ns=$(_kg_first_set "${CLUSTER_RBAC_CHECK_NAMESPACE:-}" "${RBAC_CHECK_NAMESPACE:-}" "${NS:-}" "${NAMESPACE:-}")
  clusterrole_name="${CLUSTERROLE_NAME:-}"
  clusterrolebinding_name=$(_kg_first_set "${CLUSTERROLEBINDING_NAME:-}" "${CRB_NAME:-}")
  subject_kind=$(_kg_first_set "${CLUSTERROLEBINDING_SUBJECT_KIND:-}" "${SUBJECT_KIND:-}" "ServiceAccount")
  subject_name=$(_kg_first_set "${CLUSTERROLEBINDING_SUBJECT_NAME:-}" "${SUBJECT_NAME:-}" "${SA_NAME:-}")
  subject_ns=$(_kg_first_set "${CLUSTERROLEBINDING_SUBJECT_NAMESPACE:-}" "${SUBJECT_NAMESPACE:-}")
  if [[ "$subject_kind" == "ServiceAccount" && -z "$subject_ns" ]]; then
    subject_ns=$(_kg_first_set "${NS:-}" "${NAMESPACE:-}")
  fi
  verb=$(_kg_first_set "${CLUSTERROLE_VERB:-}" "${RBAC_VERB:-}" "${CAN_I_VERB:-}")
  resource=$(_kg_first_set "${CLUSTERROLE_RESOURCE:-}" "${RBAC_RESOURCE:-}" "${CAN_I_RESOURCE:-}")
  api_group="${CLUSTERROLE_API_GROUP:-}"
  expected=$(_kg_first_set "${CLUSTER_RBAC_EXPECTED:-}" "${RBAC_EXPECTED:-}" "yes")

  if [[ -n "$clusterrole_name" ]]; then
    _section "ClusterRole"
    check_exists clusterrole "$clusterrole_name"
    [[ -n "$verb" && -n "$resource" ]] && check_clusterrole_rule "$clusterrole_name" "$verb" "$resource" "$api_group"
  fi

  if [[ -n "$clusterrolebinding_name" ]]; then
    _section "ClusterRoleBinding"
    check_exists clusterrolebinding "$clusterrolebinding_name"
    [[ -n "$clusterrole_name" ]] && check_clusterrolebinding_role "$clusterrolebinding_name" "$clusterrole_name"
    [[ -n "$subject_kind" && -n "$subject_name" ]] && check_clusterrolebinding_subject "$clusterrolebinding_name" "$subject_kind" "$subject_name" "$subject_ns"
  fi

  if [[ "$subject_kind" == "ServiceAccount" && -n "$subject_name" && -n "$subject_ns" && -n "$verb" && -n "$resource" && -n "$check_ns" ]]; then
    _section "Cluster RBAC"
    _info "kubectl auth can-i $verb $resource --as=system:serviceaccount:$subject_ns:$subject_name -n $check_ns"
    _keq "$(kubectl auth can-i "$verb" "$resource" --as="system:serviceaccount:$subject_ns:$subject_name" -n "$check_ns" 2>/dev/null)" "$expected" "SA '$subject_name' can-i $verb $resource"
  fi
}

recipe_priorityclass_pod() {
  local ns priorityclass_name priority_value global_default preemption_policy pod_name image

  ns=$(_kg_ns)
  priorityclass_name=$(_kg_first_set "${PRIORITYCLASS_NAME:-}" "${PC_NAME:-}")
  priority_value="${PRIORITY_VALUE:-}"
  global_default="${PRIORITY_GLOBAL_DEFAULT:-}"
  preemption_policy="${PRIORITY_PREEMPTION_POLICY:-}"
  pod_name="${POD_NAME:-}"
  image="${IMAGE:-}"

  if [[ -n "$priorityclass_name" ]]; then
    _section "PriorityClass"
    check_priorityclass "$priorityclass_name" "$priority_value" "$global_default" "$preemption_policy"
  fi

  if [[ -n "$pod_name" ]]; then
    _section "Pod"
    check_exists pod "$pod_name" "$ns"
    _kg_truthy "${EXPECT_POD_READY:-}" && check_pod_ready "$pod_name" "$ns"
    [[ -n "$image" ]] && check_image "$pod_name" "$ns" "$image"
    _kg_check_jsonpath_if_set pod "$pod_name" "$ns" '{.spec.priorityClassName}' "$priorityclass_name" "Pod '$pod_name' priorityClassName"
  fi
}

recipe_pv_pvc() {
  local ns pv_name pvc_name pv_capacity pv_access pv_storage_class pv_phase pvc_size pvc_access pvc_storage_class

  ns=$(_kg_ns)
  pv_name="${PV_NAME:-}"
  pvc_name=$(_kg_first_set "${PVC_NAME:-}" "${CLAIM_NAME:-}")
  pv_capacity="${PV_CAPACITY:-}"
  pv_access=$(_kg_first_set "${PV_ACCESS_MODE:-}" "${PV_ACCESS:-}")
  pv_storage_class=$(_kg_first_set "${PV_STORAGE_CLASS:-}" "${STORAGECLASS_NAME:-}" "${STORAGECLASS:-}")
  pv_phase="${PV_PHASE:-}"
  pvc_size="${PVC_SIZE:-}"
  pvc_access=$(_kg_first_set "${PVC_ACCESS_MODE:-}" "${PVC_ACCESS:-}")
  pvc_storage_class=$(_kg_first_set "${PVC_STORAGE_CLASS:-}" "${pv_storage_class}")

  if [[ -n "$pv_name" ]]; then
    _section "PersistentVolume"
    check_pv "$pv_name" "$pv_capacity" "$pv_access" "$pv_storage_class" "$pv_phase"
  fi

  if [[ -n "$pvc_name" ]]; then
    _section "PersistentVolumeClaim"
    check_pvc "$pvc_name" "$ns" "$pvc_size" "$pvc_access" "$pvc_storage_class"
  fi

  if [[ -n "$pv_name" && -n "$pvc_name" ]]; then
    _section "PV/PVC Binding"
    check_jsonpath pvc "$pvc_name" "$ns" '{.spec.volumeName}' "$pv_name" "PVC '$pvc_name' volumeName"
    _info "kubectl get pv $pv_name -o jsonpath='{.spec.claimRef.namespace}'"
    _keq "$(_kcget pv "$pv_name" '{.spec.claimRef.namespace}')" "$ns" "PV '$pv_name' claimRef.namespace"
    _info "kubectl get pv $pv_name -o jsonpath='{.spec.claimRef.name}'"
    _keq "$(_kcget pv "$pv_name" '{.spec.claimRef.name}')" "$pvc_name" "PV '$pv_name' claimRef.name"
  fi
}
