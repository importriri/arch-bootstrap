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
