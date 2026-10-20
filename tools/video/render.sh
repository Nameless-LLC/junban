#!/usr/bin/env bash
# render.sh — film the demo (record.sh) and render the five videos the site uses
# into docs/media. Needs Node, and the fonts the frames are drawn in: JetBrains
# Mono, Noto Sans CJK JP and Inter (any 0.6em monospace font works for Latin).
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$HERE"
[ -d node_modules ] || npm install --no-audit --no-fund
unset TMUX
bash record.sh en; bash record.sh ja
r() { npx remotion render src/index.ts "$1" "$ROOT/docs/media/$2" --public-dir build --crf 26 --log error; }
r JunbanDemoEN junban-demo-en.mp4
r JunbanDemoJA junban-demo-ja.mp4
r JunbanDemoMobileEN junban-demo-mobile-en.mp4
r JunbanDemoMobileJA junban-demo-mobile-ja.mp4
r JunbanDemoSquare junban-demo-square.mp4
python3 "$ROOT/tools/build-site.py"
