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

## The lesson

A file written for another program is tested by reading it the way that
program reads it. A text comparison pins whatever the writer emits, wrong
or right.
