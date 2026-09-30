#!/bin/bash
# Copies build/FinderTweaks.app into ~/Applications and (re)launches it.
set -euo pipefail
cd "$(dirname "$0")/.."
DEST="$HOME/Applications/FinderTweaks.app"
if pkill -x FinderTweaks; then sleep 0.5; fi
rm -rf "$DEST"
ditto build/FinderTweaks.app "$DEST"
open "$DEST"
echo "installed $DEST"
