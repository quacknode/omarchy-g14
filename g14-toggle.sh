#!/bin/sh
dir=${XDG_STATE_HOME:-$HOME/.local/state}/g14
mkdir -p "$dir"
stamp=$dir/m4.stamp
now=$(date +%s%3N)
if [ -f "$stamp" ]; then
  prev=$(cat "$stamp" 2>/dev/null || echo 0)
  if [ "$((now - prev))" -lt 400 ]; then
    exit 0
  fi
fi
printf '%s\n' "$now" > "$stamp"
exec omarchy-shell shell toggle io.github.quacknode.g14
