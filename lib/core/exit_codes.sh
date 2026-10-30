#!/bin/bash

# Exit codes.

if [[ ${_SOURCED_core_exit_codes:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_core_exit_codes="loaded"

declare -gr EXIT_OK=0
declare -gr EXIT_STAGE_FAIL=10
declare -gr EXIT_VALIDATION_FAIL=11
declare -gr EXIT_USER_ABORT=12
declare -gr EXIT_INTERNAL=13
declare -gr EXIT_RESUME_RECOVERABLE=14

return 0
