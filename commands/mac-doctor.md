---
description: Diagnose Mac automation permissions and tool health
---

Run `nova doctor` and `nova doctor --secure-input`.

Report in plain language: what is granted, what is missing, and the single next action.
If something is missing, name the exact app that needs the grant, which is the host app
doctor printed, not "Claude" and not "nova."

If everything is granted but something is still failing, load the `mac-debug` skill and
work the symptom table. Do not guess.
