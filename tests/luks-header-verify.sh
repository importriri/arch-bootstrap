#!/usr/bin/env bash
# Real verification that does NOT need device-mapper:
#   1. read_passphrase: match / mismatch / empty, and NO trailing newline on stdout
#   2. the actual LUKS2 header cryptsetup writes with the installer's real
#      constants — luksFormat + luksDump on a sparse file (no dm needed)
#   3. the newline trap: a passphrase fed with a trailing newline must NOT
#      authenticate against a header created without one (luksAddKey, no dm)
#
# usage:  sudo ./tests/luks-header-verify.sh
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="$HERE/installer"

pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*"; exit 1; }

# import the installer's functions + constants (launcher guard keeps main off)
export DRY_RUN=1
# shellcheck disable=SC1090,SC1091
source "$INSTALLER"

echo "== read_passphrase =="

# matching pair: stdout must be exactly the secret, with NO trailing newline
out=$(printf 'hunter2hunter2\nhunter2hunter2\n' | read_passphrase 2>/dev/null) \
	|| fail "read_passphrase rejected a matching pair"
[[ $out == "hunter2hunter2" ]] || fail "stdout was '$out', expected the raw secret"
[[ $(printf '%s' "$out" | wc -c) -eq 14 ]] || fail "stdout length wrong (trailing newline leaked?)"
pass "matching pair: exact secret on stdout, no trailing newline"

# mismatch must fail
if printf 'aaaa\nbbbb\n' | read_passphrase >/dev/null 2>&1; then
	fail "read_passphrase accepted a mismatched pair"
fi
pass "mismatched pair rejected"

# empty must fail
if printf '\n\n' | read_passphrase >/dev/null 2>&1; then
	fail "read_passphrase accepted an empty passphrase"
fi
pass "empty passphrase rejected"

echo
echo "== real LUKS2 header with the installer's constants =="

img=$(mktemp /tmp/luks-verify.XXXXXX)
trap 'rm -f "$img"' EXIT
truncate -s 32M "$img"

# same fmt_args the installer builds, but with fast argon2id so the test is quick
secret='correct horse battery'
printf '%s' "$secret" | cryptsetup luksFormat \
	--type luks2 \
	--cipher   "$LUKS_CIPHER" \
	--key-size "$LUKS_KEY_SIZE" \
	--hash     "$LUKS_HASH" \
	--pbkdf    "$LUKS_PBKDF" \
	--pbkdf-force-iterations 4 --pbkdf-memory 32 \
	--batch-mode --key-file - "$img" \
	|| fail "luksFormat with the installer constants failed"
pass "luksFormat accepted (cipher=$LUKS_CIPHER key=$LUKS_KEY_SIZE pbkdf=$LUKS_PBKDF)"

dump=$(cryptsetup luksDump "$img")
grep -q "Version:.*2"                 <<< "$dump" || fail "header is not LUKS2"
grep -qi "cipher:.*$LUKS_CIPHER"      <<< "$dump" || fail "cipher mismatch in header"
grep -qi "$LUKS_KEY_SIZE bits"        <<< "$dump" || fail "key size mismatch in header"
grep -qi "PBKDF:.*$LUKS_PBKDF"        <<< "$dump" || fail "PBKDF is not $LUKS_PBKDF"
pass "luksDump confirms LUKS2 / $LUKS_CIPHER / $LUKS_KEY_SIZE-bit / $LUKS_PBKDF"

echo
echo "== the newline trap (why printf '%s', never a here-string) =="

FAST=(--pbkdf argon2id --pbkdf-force-iterations 4 --pbkdf-memory 32 --batch-mode)

# the SAME secret fed with printf (no newline) authenticates -> can add a keyslot
printf '%s' "$secret" | cryptsetup luksAddKey "${FAST[@]}" --key-file - "$img" \
	<(printf 'second') 2>/dev/null \
	|| fail "printf-fed secret failed to authenticate against its own header"
pass "printf-fed secret (no newline) authenticates"

# the SAME secret WITH a trailing newline must NOT authenticate
if cryptsetup luksAddKey "${FAST[@]}" \
	--key-file <(printf '%s\n' "$secret") "$img" <(printf 'third') 2>/dev/null; then
	fail "a trailing newline still authenticated — the trap would be silent!"
fi
pass "same secret + trailing newline is REJECTED (locks you out at boot: proven)"

echo
echo "ALL LUKS VERIFICATIONS PASSED"
