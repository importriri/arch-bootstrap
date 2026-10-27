# The storage contract was not valid YAML

Found on 2026-10-11 by HyperLab's `foundation.yml --check` in its nested lab
host, installed with `34aa9cd`: the `bootstrap_storage` role refused
`/etc/privatestack/bootstrap-storage.yml` before it compared a single field.

## The symptom

A single-disk installation wrote

```yaml
  subvolume: @vm
```

and every YAML parser refuses the whole file:

```
yaml.scanner.ScannerError: while scanning for the next token
found character '@' that cannot start any token
```

YAML reserves `@` as an indicator: a plain (unquoted) scalar cannot start
with it. The dedicated-disk contract (`subvolume: null`) parses, so only the
single-disk topology was affected. The README already showed the value
quoted (`subvolume: "@vm"`); the writer did not.

## Why the tests passed

`tests/bootstrap-contract.bats` compared the file line by line with `grep`,
and pinned exactly the wrong text (`'^  subvolume: @vm$'`). A text match
cannot tell valid YAML from invalid YAML, and nothing in this repository
ever parsed the contract its consumer parses.

## The fix

`write_storage_contract` writes `subvolume: "@vm"`. Both topology tests now
read the contract with a YAML parser (`yaml.safe_load`, as HyperLab's guard
does) and compare every parsed field and value, in order: `'@vm'` as a
string, `None` for null, `True` for `require_nocow`. Against `34aa9cd` the
single-disk test fails (the parser refuses the file); with the fix both pass.
`verify.sh` and CI now require Python's YAML module.

## Repair on a host installed with `34aa9cd`

The fix changes only new installations: `bootstrap` does not run again on an
installed host, and HyperLab's adoption never replaces a contract that
already exists. On such a host, as root, quote the one value in place and
check the result:

```bash
contract=/etc/privatestack/bootstrap-storage.yml
sha256sum "$contract"                                  # keep, before
sed -i 's/^  subvolume: @vm$/  subvolume: "@vm"/' "$contract"
python3 -c 'import sys, yaml; print(yaml.safe_load(open(sys.argv[1]))["vm_store"]["subvolume"])' "$contract"
stat -c '%U:%G %a' "$contract"                         # root:root 644
sha256sum "$contract"                                  # keep, after
```

The parser prints `@vm`; nothing else in the file changes. A dedicated-disk
installation (`subvolume: null`) needs no repair. Reinstalling with the
fixed writer is the complete proof.

The tests also refuse a repeated key (which `safe_load` would resolve in
silence to the last copy) and any top-level key besides `schema_version`
and `vm_store`, and the dedicated-disk test now checks the file exists with
mode 0644, as the single-disk test already did. Each of the three was
proved with a writer mutant that passed the previous tests and fails now.

Reviewed and left as they are (2026-10-12): the other values are still
written unquoted, but each is a fixed constant of the installer; the writer
does not read the file back after writing it; `expected_subvolume` holds
the YAML form `"@vm"`, used only in the heredoc; an unknown topology is
written with the single-disk values, but its only caller returns one of the
two known ones.

## Consumer regression and mutation catalogue

The parser repair still left three independently maintained contracts: this
writer, the stage-2 guard and the acceptance manifest. A valid YAML document
with a renamed installer label could pass the producer tests while the real
consumer refused a fresh installation. The storage comparison now lives in
`tests/bootstrap-contract.bats`, reached by the existing full verifier:

```bash
HYPERLAB_ANSIBLE_REPO=/path/to/hyperlab-ansible \
  CROSS_REPO_STORAGE_REQUIRED=1 bash verify.sh
```

It executes `write_storage_contract` from temporary source copies for both
topologies and feeds the resulting files to the actual sibling guard CLI.
Synthetic mount evidence is independent of the installer constants. The entire
manifest topology mapping is compared to projections of the successful guard
JSON, rather than to another hand-written schema. Only storage agreement with
`release/acceptance.v2.yml` is tested. Neither sibling source nor live storage
is changed; the consumer runs with `-B` and `PYTHONDONTWRITEBYTECODE=1`.

Run the focused checks with:

```bash
HYPERLAB_ANSIBLE_REPO=/path/to/hyperlab-ansible \
  CROSS_REPO_STORAGE_REQUIRED=1 \
  bats --print-output-on-failure --filter 'storage' tests/bootstrap-contract.bats
```

The following mutations were observed failing the predicted check, then passing
again after restoring the saved source copy. Producer and manifest mutations use
temporary fixtures; the real sibling is never mutated.

| Mutation | Predicted check and observed result |
| --- | --- |
| Rename `ROOT_LABEL` or `VM_LABEL` in a producer copy | Actual writer comparison red: guard exit 2 at `root_partlabel` or `vm_partlabel`; restored green |
| Rename either mapper, change the VM mountpoint or writer subvolume | Actual writer comparison red at the corresponding declared field; restored green |
| Change a manifest topology shape | Actual writer comparison red with `manifest storage disagreement`; restored green |
| Add a topology or field, remove a topology, duplicate a key or corrupt YAML | Manifest fixture comparison refused each input with its own diagnostic; clean manifest green |
| Ignore the manifest equality assertion | Manifest regression red because the incompatible fixture succeeded; restored green |
| Replace writer execution with captured, fixed clean output | Producer mutation regression red because changed labels no longer reached the consumer; restored green |
| Supply a different observed mapper or filesystem root | Actual guard exit 2 at the observed field; clean evidence green |
| Make a generated contract writable or redirect it through a symlink | Actual guard exit 2 at its existing file checks; clean file green |
| Swallow the consumer failure in the comparison wrapper | Required consumer-refusal regression red; restored green |
| Treat an absent required sibling as optional | Missing-required-input regression red; restored green |
| Disable CI required mode, point at the wrong sibling, swallow exit 23 or narrow `push` to one branch | Executed workflow-body regression red; restored green |

The workflow regression parses the actual job and creates local checkout
fixtures with a recording verifier. It executes the real run body, verifies the
required flag and sibling path, and observes both exit 0 and exit 23 propagating.
Provisioning is not executed. This is software evidence, not a hosted CI run.

The full verifier was also exercised from an isolated standalone fixture with
both variables unset (explicit skip and PASS), and in required mode against the
real readable sibling (actual comparison and PASS). A required run without a
sibling failed; a real consumer refusal stayed a failure rather than a skip.
During these checks the unchanged writer revision was
`eabc13bf98be45e2bf89c66acb08f4463c95dd04` and the sibling revision was
`f74510388a9bfa2a63014abba3ef9d11c46bd52d`; verification changes were present in
the producer worktree. Revision output identifies integration inputs and does
not freeze or promote a hardware campaign. No new hardware observation is made.

### The workflow fixture inherited its required inputs

The workflow already supplies both storage inputs, but its recording-verifier
fixture copied `os.environ` before applying the parsed job and step settings.
If the caller exported `CROSS_REPO_STORAGE_REQUIRED=1`, deleting that setting
from a workflow copy could still pass. An inherited `HYPERLAB_ANSIBLE_REPO`
pointing at the expected local checkout could conceal the same deletion.

Each verifier invocation now copies the ordinary environment, removes both
storage inputs, then applies the workflow settings, with step values taking
precedence over job values as before. Unrelated inputs such as `PATH` survive.
The fixture checks the required flag, resolved sibling directory and working
directory independently, with exits 0 and 23. It deletes the recording file
before each invocation so an earlier observation cannot satisfy a later check.

Normal Bats discovery runs three clean controls (parent inputs absent, matching
and conflicting) and four deletion cases (each setting removed separately,
with parent inputs absent and matching). All use the same executed fixture.
A deletion passes its negative test only with the exact
`missing workflow input: CROSS_REPO_STORAGE_REQUIRED` or
`missing workflow input: HYPERLAB_ANSIBLE_REPO` assertion. A parse error, missing
directory or missing observation does not qualify. Before adding the two
scrubs, both matching-parent deletion tests were red because the weakened
workflows incorrectly succeeded; the absent-parent cases already detected them.

Run the workflow cases (seven at the time, ten with the stale-observation
regression below) with either caller environment:

```bash
env -u HYPERLAB_ANSIBLE_REPO -u CROSS_REPO_STORAGE_REQUIRED \
  bats --print-output-on-failure --filter 'required storage CI' tests/bootstrap-contract.bats
HYPERLAB_ANSIBLE_REPO=/path/to/hyperlab-ansible CROSS_REPO_STORAGE_REQUIRED=1 \
  bats --print-output-on-failure --filter 'required storage CI' tests/bootstrap-contract.bats
```

The following mutations were observed in isolated workflow/test copies, with
saved copies restored between cases. Each check ran with both caller variables
unset and with both supplied; the clean controls also construct the exact
matching and conflicting parent values themselves. No mutation stayed green.

| Mutation | Predicted check and observed result |
| --- | --- |
| Delete the workflow's required-mode setting | All three clean controls red with `missing workflow input: CROSS_REPO_STORAGE_REQUIRED`, including parent flag `1`; restored green |
| Delete the workflow's sibling setting | All three clean controls red with `missing workflow input: HYPERLAB_ANSIBLE_REPO`, including the expected fixture path in the parent; restored green |
| Remove only the required-mode environment scrub from the test copy | Matching-parent required-flag deletion regression red because the weakened workflow succeeded; restored green |
| Remove only the sibling environment scrub from the test copy | Matching-parent sibling-path deletion regression red because the weakened workflow succeeded; restored green |
| Append `\|\| exit 0` to the workflow verifier body | All three clean controls red with expected/actual exits `(23, 0)`; restored green |
| Record only exit 0, leaving exit 23 without a fresh observation | All three clean controls red with `FileNotFoundError` at the second invocation's recording file; restored green |

For the workflow deletions, swallowed exit and stale recording, the mutation
command in the temporary copy was:

```bash
bats --print-output-on-failure --filter 'required storage CI (executes|supplies)' tests/bootstrap-contract.bats
```

For the scrub mutations, the corresponding commands were:

```bash
bats --print-output-on-failure --filter 'required storage CI refuses a missing required flag with matching parent inputs' tests/bootstrap-contract.bats
bats --print-output-on-failure --filter 'required storage CI refuses a missing sibling path with matching parent inputs' tests/bootstrap-contract.bats
```

All seven focused cases passed in both caller modes. Both complete verifier
runs also passed: Bash syntax, ShellCheck, all 77 discovered Bats cases (four
explicit dependent skips only in standalone mode) and the real temporary-file
LUKS2 header check. Required mode compared both topologies with the actual guard
and manifest. Sibling metadata, including existing bytecode caches, was unchanged.
This is software-verified fixture isolation; hosted CI and the frozen Nitro and
Predator installation/storage gates still need their own evidence.

### A stale observation was caught only by a manual mutation

The fixture removes `record_path` before each invocation, but its normal
recording verifier writes a new observation every time. Deleting that cleanup
therefore left every discovered test green: the exit-23 invocation overwrote the
exit-0 observation before it was read. Only the manual "record only exit 0"
mutation above showed the cleanup mattered, and it ended in a generic
`FileNotFoundError`.

`_storage_workflow_case` now takes a third argument. `always` is the normal
recording verifier. `success-only` is a fault written into the verifier the
helper generates (not an inherited variable): it records nothing when
`VERIFY_RC` is not 0 and still exits with `VERIFY_RC`. Both run the same parsed
workflow body, environment scrub, job and step precedence, working directory,
exit check and record validation. After the exit check, a missing record is
refused as `no fresh observation for exit N`. Each validated record prints
`valid observation for exit N`. The JSON is unchanged, so no other check can
detect staleness by accident.

Three discovered tests, one for each existing parent scenario (absent, matching
and conflicting), run the real workflow with `success-only`:

- `required storage CI refuses a stale observation with absent parent inputs`
- `required storage CI refuses a stale observation with matching parent inputs`
- `required storage CI refuses a stale observation with conflicting parent inputs`

Each test requires status 1, a first line of `valid observation for exit 0`,
and no `valid observation for exit 23` line. The last line must be
`AssertionError: no fresh observation for exit 23`, and the record file must be
absent afterwards. A parse, setup, path or wrong-exit error does not satisfy the
test. The workflow still supplies both inputs; the caller cannot supply them.
Before the explicit freshness assertion existed, all three tests were red with
`FileNotFoundError`.

The mutations below were observed in a temporary tree copy, with each caller
mode (both variables unset, then
`HYPERLAB_ANSIBLE_REPO=/path/to/hyperlab-ansible CROSS_REPO_STORAGE_REQUIRED=1`).
Every case ran:

```bash
bats --print-output-on-failure --filter 'required storage CI' tests/bootstrap-contract.bats
```

The saved copy was restored and all ten cases were green again.

| Mutation | Observed result |
| --- | --- |
| Remove `record_path.unlink(missing_ok=True)` from the test copy | The three stale-observation tests were red at `[ "$status" -eq 1 ]`, exit 0, because their output contained `valid observation for exit 23`: the exit-0 record was reused. The seven controls and deletion cases stayed green |
| Make `success-only` record on every exit in the test copy | The three stale-observation tests were red with status 0, because they never reached the refusal. The other seven stayed green |
| Append `\|\| exit 0` to the storage job's verifier body in a workflow copy | The three clean controls were red with `AssertionError: (23, 0)`. The three stale-observation tests were also red with `AssertionError: (23, 0)`, not the freshness refusal. The four deletion cases stayed green, since they fail at exit 0 |

Normal `bats tests/*.bats` discovery now finds 80 tests. Both complete verifiers
passed. Standalone mode passed 76 tests and explicitly skipped the four
sibling-dependent ones. Required mode passed all 80 with no skips, the actual
guard accepted both topologies, and the manifest mapping matched. Sibling
metadata was unchanged and no bytecode was written. This is software-verified
fixture coverage. It is not a hosted CI run or a storage observation on any
machine.

## A contract that could not be written still reported success

Found on 2026-10-25 by reading the hand-off path: `write_storage_contract`
ran `cat > "$contract_path" <<EOF` and never checked it. `bootstrap_main`
calls the writer as `write_storage_contract "$topology" || return 1`; inside
an OR list errexit is off, so `set -e` does not stop at the failed `cat`.
The `chown` and `chmod` after it succeed on whatever the failed write left
(even on a directory), and the run printed both markers:

```
bootstrap: line 121: .../mnt/etc/privatestack/bootstrap-storage.yml: Is a directory
[OK] stage-2 storage contract written: /etc/privatestack/bootstrap-storage.yml
[OK] arch-bootstrap complete — storage is ready for hyperlab-ansible
```

That is how the whole-entrypoint test's output ends against the writer of
`af90303` (paths shortened), with exit status 0, for both topologies and
for both the open and the partial write failure. The success path then disables the EXIT cleanup, so
a run with no contract, or a truncated one, also left everything mounted and
open as if it had finished.

The writer now checks the heredoc's status, with the same `|| { echo ...;
return 1; }` the installer uses for its own files, and fails with
`Could not write the bootstrap storage contract`. Neither marker is printed,
the run exits nonzero and its EXIT trap releases what it adopted from the
installer, newest mount first, then `cryptvm` (two disks) and `cryptroot`.

There is no rollback and no atomic replacement: a writer that stopped after
a prefix leaves that partial file on the target root filesystem, and nothing
here promises anything after a power loss. A run that did not print
`[OK] arch-bootstrap complete` is a failed installation, whatever file it
left behind.

The regressions, both topologies each, all through the real writer:

- a directory at the destination, so the open fails (as root too);
- a `cat` stub that reads the whole heredoc, writes its first 32 bytes and
  exits 74, so the failure happens at the write, past `install`;
- the whole entrypoint, executed with its real entry guard, EXIT trap,
  `bootstrap_main` and writer. Only the executed installer is replaced, by
  a fixture that leaves the layout in a mount table and the mappers as files
  inside the test directory; `findmnt`, `lsattr`, `umount`, `cryptsetup`,
  `install` and `chown` are PATH stubs. The cleanup argv must equal the
  reverse layout written out in the test, and an unrelated mount and mapper
  must survive. The successful runs release nothing.

Directory, ownership and mode failures still refuse with their own
diagnostics, and the dry run now has its own `/mnt` in the test, so its
check that it wrote no hand-off looks at the real destination. Run them with:

```bash
bats --filter 'contract refuses|failures still propagate|bootstrap refuses|bootstrap keeps|dry run' \
  tests/bootstrap-contract.bats
```

Each mutation was made in a temporary copy (`bootstrap`, `installer` and
`tests/` copied to a scratch directory, the shipped source untouched),
observed red, restored from its saved copy and observed green:

| Mutation of the copy's `bootstrap` | `--filter` | Observed |
| --- | --- | --- |
| Drop the `\|\| { ...; return 1; }` after the heredoc | `contract refuses an open failure\|contract refuses a partial writer failure` | 4 of 4 red at the status check: exit 0 and the stage-2 marker, both topologies; restored 4 green |
| `write_storage_contract "$topology" \|\| :` in `bootstrap_main` | `bootstrap refuses .* and cleans up adopted resources` | 4 of 4 red at the exit status, with the completion marker printed; restored 4 green |
| `trap - EXIT` just before the writer | same | 4 of 4 red at the cleanup argv (none ran); restored 4 green |

## The lesson

A file written for another program is tested by reading it the way that
program reads it. A text comparison pins whatever the writer emits, wrong
or right. And a write is a command like any other: inside an OR list
errexit does not see it, so its status is checked where it happens.
