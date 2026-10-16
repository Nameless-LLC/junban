---
description: Check the junban setup (tmux, hooks, badges) and print a report for bug reports
allowed-tools: Bash(bash *scripts/doctor.sh*)
---

junban doctor output:

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh"`

Summarise the result for the user in two or three short lines: say whether junban looks healthy, and for each warn or FAIL line, the one thing to do about it (the → line). If everything is ok, say so. Do not change any files or settings yourself.
