# logged, always-succeeds stub behaviour. STUB_LOG is set by the test.
_log() { printf '%s %s\n' "$(basename "$0")" "$*" >> "${STUB_LOG:-/dev/null}"; }
