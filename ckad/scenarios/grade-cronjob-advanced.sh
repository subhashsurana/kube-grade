#!/usr/bin/env bash
# =============================================================================
# kube-grade / ckad / grade-cronjob-advanced.sh
# Scenario: Advanced CronJob with jobTemplate controls
#
# Env overrides:
#   NS=batch CRONJOB_NAME=task-cron SCHEDULE='*/5 * * * *' IMAGE=busybox \
#   COMMAND_0=/bin/sh COMMAND_1=-c COMMAND_2='echo Processing && sleep 30' \
#   JOB_ACTIVE_DEADLINE_SECONDS=40 JOB_BACKOFF_LIMIT=2 JOB_COMPLETIONS=4 \
#   JOB_PARALLELISM=2 JOB_TTL_SECONDS_AFTER_FINISHED=120 \
#   bash grade-cronjob-advanced.sh
# =============================================================================

LIB="$HOME/kube-grade/lib/grade-recipes.sh"
if [[ -f "$LIB" ]]; then
  # shellcheck source=/dev/null
  source "$LIB"
else
  # shellcheck source=/dev/null
  source <(curl -sL https://raw.githubusercontent.com/subhashsurana/kube-grade/main/lib/grade-recipes.sh)
fi

NS="${NS:-batch}"
CRONJOB_NAME="${CRONJOB_NAME:-task-cron}"
SCHEDULE="${SCHEDULE:-*/5 * * * *}"
IMAGE="${IMAGE:-busybox}"
COMMAND_0="${COMMAND_0:-/bin/sh}"
COMMAND_1="${COMMAND_1:--c}"
COMMAND_2="${COMMAND_2:-echo Processing && sleep 30}"
JOB_ACTIVE_DEADLINE_SECONDS="${JOB_ACTIVE_DEADLINE_SECONDS:-40}"
JOB_BACKOFF_LIMIT="${JOB_BACKOFF_LIMIT:-2}"
JOB_COMPLETIONS="${JOB_COMPLETIONS:-4}"
JOB_PARALLELISM="${JOB_PARALLELISM:-2}"
JOB_TTL_SECONDS_AFTER_FINISHED="${JOB_TTL_SECONDS_AFTER_FINISHED:-120}"
EXPECTED_SUCCEEDED_PODS="${EXPECTED_SUCCEEDED_PODS:-4}"
CHECK_CRONJOB_RUNTIME="${CHECK_CRONJOB_RUNTIME:-0}"
CHECK_TTL_CLEANUP="${CHECK_TTL_CLEANUP:-0}"

recipe_cronjob_advanced
grade_summary
