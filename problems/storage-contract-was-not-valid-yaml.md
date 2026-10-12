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

## The lesson

A file written for another program is tested by reading it the way that
program reads it. A text comparison pins whatever the writer emits, wrong
or right.
