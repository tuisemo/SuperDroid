---
name: auto-test-and-fix
description: End-to-end test → analyze → propose fix → verify loop (production safe).
---

Steps:
1. Execute tests via pwsh: pytest --tb=no -q
2. If pass → output SUCCESS
3. If fail → invoke tester droid for root cause
4. Propose exact coder delegation with file + line + expected behavior
5. After coder edit → re-run test until pass or max 3 attempts

Output:
TEST_RUN_RESULT: PASS/FAIL
ITERATION: N/3
CURRENT_FAILURE: ...
PROPOSED_FIX_DELEGATION: coder "Modify X in file Y to Z"
VERIFICATION_PLAN: next test command
