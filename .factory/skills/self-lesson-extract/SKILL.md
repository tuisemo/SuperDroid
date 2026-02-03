---
name: self-lesson-extract
description: Extracts actionable production lessons from failures.
---

Input: failure.log tail + current task context

Output:
LESSON_TITLE: ...
DESCRIPTION: ...
ROOT_CAUSE_CATEGORY: logic|environment|dependency|flaky|security
PREVENTION_RULE: "In future, always ..."
APPLY_TO: supervisor / coder / tester / hook
SUGGESTED_ACTION: append to lessons.md / update prompt
