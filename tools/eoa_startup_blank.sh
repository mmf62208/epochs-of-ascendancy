#!/usr/bin/env bash
# STARTUP-BLANK: thin wrapper over the merged #166 harness.
# Does not duplicate inventory / garrison / seed / xvfb setup.
#
#   tools/eoa_startup_blank.sh
#   EOA_STARTUP_BLANK_ONLY=pointer tools/eoa_startup_blank.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -n "${EOA_STARTUP_BLANK_OUT:-}" ]]; then
  export EOA_STARTUP_PARITY_OUT="$EOA_STARTUP_BLANK_OUT"
else
  export EOA_STARTUP_PARITY_OUT="${EOA_STARTUP_PARITY_OUT:-/tmp/eoa-startup-blank}"
  export EOA_STARTUP_BLANK_OUT="$EOA_STARTUP_PARITY_OUT"
fi
ONLY="${EOA_STARTUP_BLANK_ONLY:-}"
if [[ -z "$ONLY" ]]; then
  export EOA_STARTUP_BLANK=1
else
  export EOA_STARTUP_BLANK=0
  case "$ONLY" in
    pointer|enter)
      export EOA_STARTUP_BLANK_BEGIN="$ONLY"
      ;;
    mutant)
      export EOA_STARTUP_BLANK_BEGIN=pointer
      export EOA_STARTUP_BLANK_MUTANT=1
      ;;
    drag_move)
      export EOA_STARTUP_BLANK_BEGIN=pointer
      export EOA_STARTUP_BLANK_DRAG=1
      export EOA_STARTUP_BLANK_DRAG_MOVE=1
      export EOA_STARTUP_BLANK_SOAK_S="${EOA_STARTUP_BLANK_SOAK_S:-3}"
      ;;
    drag_nomove)
      export EOA_STARTUP_BLANK_BEGIN=pointer
      export EOA_STARTUP_BLANK_DRAG=1
      export EOA_STARTUP_BLANK_DRAG_MOVE=0
      export EOA_STARTUP_BLANK_SOAK_S="${EOA_STARTUP_BLANK_SOAK_S:-3}"
      ;;
    return_spot)
      export EOA_STARTUP_BLANK_BEGIN=pointer
      export EOA_STARTUP_BLANK_RETURN_SPOT=1
      ;;
    *)
      echo "EOA_STARTUP_BLANK_ONLY must be pointer, enter, mutant, drag_move, drag_nomove, return_spot, or empty" >&2
      exit 2
      ;;
  esac
fi
export EOA_STARTUP_BLANK_SOAK_S="${EOA_STARTUP_BLANK_SOAK_S:-120}"
exec "$ROOT/tools/eoa_startup_parity.sh"
