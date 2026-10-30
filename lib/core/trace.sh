#!/bin/bash

# Command trace capture, processing and write

if [[ ${_SOURCED_core_trace:-} == "loaded" ]]; then
    return 0
fi
_SOURCED_core_trace="loaded"

module::provide core.trace trace::init trace::stop

_TRACE_SAVED_PS4=""

# trace::init <trace-log-path>
trace::init() {
    TRACE_LOG_FILE="$1"
    if [[ ${FR0ST_TRACE:-0} != "1" ]]; then
        debug_msg "trace: disabled (FR0ST_TRACE not set)"
        return 0
    fi
    [[ -n "$TRACE_LOG_FILE" ]] || {
        echo "trace::init: no trace log path given" >&2
        return 1
    }
    : >"$TRACE_LOG_FILE"
    exec 3>>"$TRACE_LOG_FILE" || return 1
    # Emit-time stamp: PS4 undergoes parameter expansion per record
    _TRACE_SAVED_PS4="${PS4-+ }"
    PS4='+ [${EPOCHREALTIME:-0.0}] [${BASH_SOURCE[0]##*/}:${LINENO}${FUNCNAME[0]:+:${FUNCNAME[0]}()}] '
    BASH_XTRACEFD=3
    return 0
}

# Disable tracing and close the stream descriptor
trace::stop() {
    if [[ ${FR0ST_TRACE:-0} == "1" ]]; then
        set +x 2>/dev/null || true
        unset BASH_XTRACEFD
        if [[ -n "$_TRACE_SAVED_PS4" ]]; then
            PS4="$_TRACE_SAVED_PS4"
            _TRACE_SAVED_PS4=""
        fi
        eval 'exec 3>&- 3<&-' 2>/dev/null || true
        debug_msg "trace: stopped"
    fi
    return 0
}

return 0
