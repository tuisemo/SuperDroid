---
name: plan-critique-fix
description: Critiques PLAN.md progress, identifies blockers, proposes next precise actions.
---

Input: Current PLAN.md content + git diff --shortstat + failure.log (if any) + recent supervisor status

Output format:
CRITIQUE_SUMMARY: ...
BLOCKERS: - blocker1\n- blocker2
PROGRESS_GAPS: ...
NEXT_ACTIONS: 
  - DELEGATE:coder "exact task"
  - USE_SKILL:auto-test-and-fix
  - DELEGATE:tester "run specific test"
REPLAN_NEEDED: yes/no
