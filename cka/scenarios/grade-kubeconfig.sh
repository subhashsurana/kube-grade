#!/usr/bin/env bash
# TODO: implement this scenario grader
LIB="$HOME/kube-grade/lib/grade-lib.sh"
if [[ -f "$LIB" ]]; then
  # shellcheck source=/dev/null
  source "$LIB"
else
  # shellcheck source=/dev/null
  source <(curl -sL https://raw.githubusercontent.com/kube-grade/kube-grade/main/lib/grade-lib.sh)
fi
_warn "This scenario grader is not yet implemented. Contributions welcome!"
grade_summary
