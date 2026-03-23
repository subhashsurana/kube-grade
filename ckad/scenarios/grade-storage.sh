#!/usr/bin/env bash
# TODO: implement this scenario grader — contributions welcome
LIB="$HOME/kube-grade/lib/grade-lib.sh"
source "${LIB}" 2>/dev/null || \
  source <(curl -sL https://raw.githubusercontent.com/kube-grade/kube-grade/main/lib/grade-lib.sh)
_warn "This scenario grader is not yet implemented. Contributions welcome!"
grade_summary
