# The dry run asked for the LUKS passphrase the README said only the real run asks for

Seen on 2026-10-07 in a nested lab VM, running `DRY_RUN=1 bash bootstrap`
on a blank 80 GiB virtio disk: after the partition plan and "[DRY-RUN] no
changes written to /dev/vda", the run stopped at "LUKS passphrase:" and
"Repeat passphrase:". The README said "The real run asks for the root LUKS
passphrase", so an operator rehearsing with prepared answers had nothing
ready for that prompt, and an answer meant for another prompt could land
in it.

## Cause

Not a defect in the installer: `encrypt_root` reads and confirms the
passphrase in the dry run on purpose (`installer`, the comment "acquire +
confirm the passphrase in the dry-run too"), because the match check is
the one part of encryption a rehearsal can prove. The README described
only the real run.

What a full dry run executes was checked with the test stubs: `sgdisk
--pretend --zap-all … -p DISK` and `cryptsetup --help` (and `cryptsetup
isLuks` when the partition exists), besides read-only probes. No
`cryptsetup luksFormat` or `open`, no `mkfs`, `wipefs`, `partprobe`,
`pacstrap` or mount. The lab disk was unchanged afterwards (no signature,
same allocation).

Found on the way: `sgdisk --pretend` does not simulate `--zap-all`. On a
disk that already holds a GPT the printed plan shows the old partitions
and sgdisk ends with "Error encountered; not saving changes" (exit 4),
seen on a 2 GiB image in the same VM; the image was unchanged. It is not a
false green: `partition_disk` returns 1 on that exit ("sgdisk (pretend)
failed on DISK"), `main` exits 1 at `partition_disk "$disk" || exit 1`, and
`bootstrap` returns non-zero after the installer. A dry run of a disk that
already holds a table fails loudly instead of rehearsing it; that is left
as it is for now.

## Fix

The README now says the dry run is interactive, asks for the passphrase
twice, never uses it, writes nothing, and names the only external commands
it runs; it also states the `--zap-all` limit of the printed plan.

## Test

`tests/unit.bats` runs the whole dry-run pipeline, partition step
included, against the logging stubs: it must log the `sgdisk --pretend`
line and `cryptsetup --help`, nothing else, and the passphrase must not
appear in the output. `tests/bootstrap-contract.bats` holds the README to
the deliberate prompt.
