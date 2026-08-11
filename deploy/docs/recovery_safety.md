# Recovery Safety

The formal recovery sequence is `disable -> clear-only -> verify -> separate enable`. Clear while a live fault
is present must not release protection. Read-only status inspection must not write CTRL, thresholds, PWM, or
reserved registers. This release does not authorize physical fault injection or recovery execution.
