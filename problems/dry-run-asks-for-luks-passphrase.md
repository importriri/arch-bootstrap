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

The review of that first fix found the claim "writes nothing" false at the
very end. `bootstrap` sets `trap cleanup EXIT` and its dry-run branch
returns before clearing it, and the installer's own trap fires when it
fails, so every dry run ran, at its exit, `umount -R /mnt`, `cryptsetup
close cryptvm` and `cryptsetup close cryptroot`, as root: once on success,
twice on "sgdisk (pretend) failed". On a host where a finished
installation is still mounted for review, a rehearsal unmounted it and
closed its LUKS mappers. Nothing was mounted or open in the lab VM, whose
disk was checked unchanged afterwards.

## Fix

The README now says the dry run is interactive, asks for the passphrase
twice, never uses it, writes nothing, and names the only external commands
it runs; it also states the `--zap-all` limit of the printed plan.

Cleanup now undoes only what the same run mounted or opened: every real
`cryptsetup open` and mount sets a flag (`own`), and `cleanup` acts on the
flags alone. The wrapper learns what the installer owns through a
temporary file it hands to the installer in a real run, and adopts those
names only when the installer succeeded and left the target mounted for
its checks. A dry run sets no flag, so it unmounts and closes nothing.

## Test

`tests/unit.bats` runs the whole dry-run pipeline, partition step
included, against the logging stubs: it must log the `sgdisk --pretend`
line and `cryptsetup --help`, nothing else, and the passphrase must not
appear in the output. `tests/bootstrap-contract.bats` holds the README to
the deliberate prompt.

`tests/bootstrap-contract.bats` runs the whole entrypoint, `bootstrap` and
its installer, in dry run against the logging stubs, with a `lsblk` that
shows one disk and only the root and UEFI guards neutralized in a copy:
on success and on "sgdisk (pretend) failed", only read-only probes,
`sgdisk --pretend` and `cryptsetup --help`/`isLuks` may reach a tool, at
the exit too. Both fail on the code before this fix, which logged `umount
-R /mnt` and the two `cryptsetup close`. `tests/unit.bats` keeps the
safety net: with nothing owned `cleanup` runs nothing, and after a real
run's open and mounts it undoes those and leaves the VM mapper it never
opened.
