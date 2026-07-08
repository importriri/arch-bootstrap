# The negative assertion that asserted nothing

Found while lint-sweeping the test suite itself. Two of the most important
assertions in `tests/unit.bats` — the ones guarding against a regression to
the legacy `cryptdevice=` syntax and the legacy `encrypt` hook — were
decorative. They could never fail.

## The symptom

```bash
# inside a @test block:
! grep -q "cryptdevice=" "$entry"
```

Green when the string is absent. Green when the string is present. Green
always. The test suite reported 21/21 while two of those 21 protected
exactly nothing.

## Diagnose it yourself, step by step

bats detects a failing line through `set -e` semantics. And POSIX is explicit:
**errexit ignores a pipeline prefixed with `!`**. So:

- string absent → `grep` fails → `!` flips it to success → line passes. Fine.
- string present → `grep` succeeds → `!` flips it to failure → but a
  `!`-prefixed pipeline is exempt from errexit → **the test keeps going and
  passes anyway.**

The tool that caught it was shellcheck, pointed at the `.bats` file:

```
SC2314 (error): In Bats, ! does not cause a test failure.
                Use 'run ! ' (on Bats >= 1.5.0) instead.
```

## The fix

Make the exit code a first-class value and assert on it:

```bash
run grep -q "cryptdevice=" "$entry"
[ "$status" -ne 0 ]
```

Verified both ways after the fix: plant `cryptdevice=` in a fixture → the
test goes red; remove it → green.

## The lessons (these outlast the bug)

- Tests are code. Lint them with the same `shellcheck -x` the installer gets —
  this bug lived in the safety net, the one place a silent pass hurts most.
- A suite that has never failed on purpose is unproven. Break the thing it
  guards once, watch it go red, then trust it.
- `!` in errexit-land is a known trap in scripts; in bats it is the same trap
  wearing a test framework.
