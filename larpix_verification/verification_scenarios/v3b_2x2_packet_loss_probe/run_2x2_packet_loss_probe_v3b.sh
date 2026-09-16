#!/usr/bin/env bash
set -euo pipefail

# Reproduce the recorded v3b comparison with the maintained 2x2 runner.
repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
runner="$repository_root/larpix_verification/verification_scenarios/v3c_2x2_packet_loss_probe/run_2x2_packet_loss_probe.sh"

export CHIP_TARGET="${CHIP_TARGET:-chip_larpix_v3b_build}"
export CHIP_BIN_NAME="${CHIP_BIN_NAME:-chip_larpix_v3b}"
export CHIP_VARIANT_LABEL="${CHIP_VARIANT_LABEL:-v3b}"
export RTL_VERSION_LABEL="${RTL_VERSION_LABEL:-v3b}"

exec "$runner" "$@"
