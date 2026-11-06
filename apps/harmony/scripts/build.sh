#!/usr/bin/env bash
set -euo pipefail
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLT_DIR="${HARMONYOS_CLT_ROOT:-$HOME/Tools/command-line-tools}"
if [[ ! -x "$CLT_DIR/bin/hvigorw" ]]; then
  echo 'Set HARMONYOS_CLT_ROOT to the HarmonyOS Command Line Tools directory.' >&2
  exit 1
fi
export DEVECO_SDK_HOME="$CLT_DIR/sdk"
export OHOS_SDK_HOME="$CLT_DIR/sdk/default/openharmony"
export PATH="$CLT_DIR/bin:$PATH"
cd "$APP_DIR"
node scripts/bundle.mjs
node scripts/build-surfaces.mjs
ohpm install
hvigorw --mode module -p module=entry@default -p product=default assembleHap --no-daemon
