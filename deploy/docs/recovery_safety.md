# Recovery Safety

The formal recovery sequence is `disable -> clear-only -> verify -> separate enable`. Clear while a live fault
is present must not release protection. Read-only status inspection must not write CTRL, threshold, PWM or
reserved registers. The release does not authorize board fault injection or clear/recovery execution.
