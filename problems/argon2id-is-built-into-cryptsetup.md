# `pacman -S argon2` does not give cryptsetup argon2id

Caught reviewing the capability check at the top of `encrypt_root`. The guard
was right to exist — a machine whose `cryptsetup` can't do argon2id should
never reach `luksFormat` — but the remedy it reached for was the wrong
package, and the control flow around it quietly defeated the guard entirely.

## The symptom (the one that never happened)

An old ISO boots, `cryptsetup --help` doesn't list argon2id, and the installer
announces it's "Installing argon2". It runs `pacman -Sy argon2`, prints
`Argon2 installed`, and — on the very next line, unconditionally — also prints
`Couldn't install Argon2`. Then it carries on to `luksFormat` with the same
cryptsetup as before and fails there instead, with a murkier message, halfway
into the destructive part of the run.

## The two things that were wrong

**Wrong package.** argon2id in cryptsetup is `libargon2`, linked at build
time. On Arch that library is already present — it's a dependency of the
`cryptsetup` package itself. The standalone `argon2` package only adds the
`argon2` CLI, a separate hashing tool; it does not retrofit argon2id onto a
cryptsetup binary that was built without it. If `--help` doesn't list
argon2id, the binary is simply too old (argon2id + LUKS2 landed in cryptsetup
2.0), and the only thing that helps is a newer **cryptsetup** — never
`pacman -S argon2`.

**Defeated guard.** The whole point of the check is to stop before a lie. But
the branch had no `else` and no `return`: the "couldn't install" line fired
even on success, and either way execution fell out of the `if` and continued.
A precondition that doesn't stop the pipeline isn't a precondition.

## Diagnose it yourself

```bash
cryptsetup --help | sed -n '/PBKDF/p'          # is argon2id in the list at all?
pacman -Qi cryptsetup | grep -i version         # ... or is the binary just old?
ldd "$(command -v cryptsetup)" | grep argon2    # libargon2 is already linked in
pacman -Ql argon2 | grep /bin/                  # the argon2 package == a CLI, /usr/bin/argon2
```

If the first line is empty but the third isn't, installing `argon2` changes
nothing that matters — the library was always there; the binary is what's
behind.

## The fix

If argon2id is missing, update the thing that actually carries it, re-verify,
and abort loudly if it's still absent. And keep a rehearsal honest: a dry-run
on a box that can't argon2id must refuse and touch nothing — no package
manager on a rehearsal.

```bash
if ! cryptsetup --help 2>&1 | grep -qw argon2id; then
        echo "this cryptsetup build does not list argon2id as a PBKDF" >&2
        if (( DRY_RUN )); then
                echo "refusing: update cryptsetup before a real run" >&2
                return 1
        fi
        echo "Updating cryptsetup on the live host ..." >&2
        pacman -Sy --noconfirm cryptsetup \
                || { echo "updating cryptsetup failed" >&2; return 1; }
        cryptsetup --help 2>&1 | grep -qw argon2id \
                || { echo "cryptsetup still cannot argon2id after the update — aborting" >&2; return 1; }
fi
```

## It stays proven, not just commented

The branch used to be invisible to CI, because the `cryptsetup` stub always
reported argon2id. Two things make the real path testable without an old ISO:

- the `cryptsetup` stub honours `STUB_NO_ARGON2ID=1`, dropping argon2id from
  `--help` (note that `grep -w argon2id` must *miss* — "argon2i" is a
  different word);
- a `pacman` stub logs its call and succeeds without providing argon2id, so
  the re-verify still gets the last word.

`tests/unit.bats` then pins both directions: a dry-run with argon2id absent
must exit non-zero, say so, and never shell out to pacman; a real run must try
to update **cryptsetup** (not `argon2`), and — argon2id still missing — abort
*before* any `luksFormat` reaches the log.

## The lessons (these outlast the bug)

- "Feature X is missing" and "install the package named X" are not the same
  question. argon2id is a capability *inside* cryptsetup, not a package you
  bolt on beside it.
- A precondition has to be able to *stop* the thing it precedes. An `if` with
  no `else`/`return` that falls through to the dangerous command is decoration.
- Success and failure messages that can both print in the same run mean the
  branch never decided anything.
- The cheapest place to catch "this box can't argon2id" is the top of the
  function, on a dry-run — long before a slow, irreversible `luksFormat`.
