# verify.sh used an unlocked sudo without asking, for a step that needs no root

Raised by the operator on 2026-10-07 while reviewing the verification gate.

## What was wrong

`verify.sh` ran its LUKS step as root in two ways: when the run already was
root, or, when `sudo -n true` succeeded, through `sudo bash
tests/luks-header-verify.sh`. A sudo credential still cached from an earlier
command, or a passwordless rule, was used by a script that never asked for
it. As root it then ran: `sudo -n true`; sourcing `installer`, which at top
level only assigns constants (`installer:5-76`) and starts `main` only when
run directly (`installer:1020-1029`); the `read_passphrase` checks;
`mktemp`, `truncate` and `rm` of a 32 MiB file in `/tmp`; and `cryptsetup
luksFormat`, `luksDump` and `luksAddKey` on that file. Without either it
stopped with "needs root".

The step never needed root. Run as a normal user (uid 1000) on 2026-10-07,
`bash tests/luks-header-verify.sh` passed every check, and no
`/tmp/luks-verify.*` file was left.

## Fix

`verify.sh` runs `bash tests/luks-header-verify.sh` directly and contains
no sudo. CI runs `bash verify.sh`, and the README and the release gates say
so.

## Known risk

CI now runs `bash verify.sh`, so `cryptsetup luksFormat`, `luksDump` and
`luksAddKey` run as the runner's normal user. That was seen on Arch
(cryptsetup on the Nitro), not on the Ubuntu runner; it is verified only
after the next push.

## Test

`tests/bootstrap-contract.bats` refuses any `sudo` in `verify.sh` and the
LUKS step and a `sudo bash verify.sh` in CI, and runs the LUKS step with an
unlocked fake `sudo` first on `PATH`: it must pass and leave the fake
untouched. It fails on the previous `verify.sh`.
