#!/usr/bin/env bash
set -euo pipefail

# Reproduce the recorded v3b comparison with the maintained 15x15 runner.
repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
runner="$repository_root/larpix_verification/verification_scenarios/v3c_15x15_two_track_charge_deposition/run_15x15_event_staggered_multichip.sh"

export CHIP_TARGET="${CHIP_TARGET:-chip_larpix_v3b_build}"
export CHIP_BIN_NAME="${CHIP_BIN_NAME:-chip_larpix_v3b}"
export CHIP_VARIANT_LABEL="${CHIP_VARIANT_LABEL:-v3b}"
export RTL_VERSION_LABEL="${RTL_VERSION_LABEL:-v3b}"
export REQUIRE_ALL_TARGETS="${REQUIRE_ALL_TARGETS:-0}"

exec "$runner" "$@"
