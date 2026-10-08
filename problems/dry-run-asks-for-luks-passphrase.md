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
`cryptsetup open` records its mapper and every real mount records its own
mount point, and `cleanup` unmounts those points one by one, newest first,
then closes those mappers. A step that releases its own mount takes it off
the list. What cleanup cannot release it reports, with the commands that
finish the job, instead of hiding it. After a successful installer run the
wrapper owns the layout's mount points and the mappers itself: it knows
them from the layout, and it knows they are this run's because the
installer refuses to start when `/mnt` or a mapper is already in use. That
refusal holds in the dry run too, which says that a real run would refuse
and exits with an error; it is what keeps a run that died earlier from
blocking the next one without a word. A dry run records nothing, so it
unmounts and closes nothing.

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

A second review found three gaps in that first version, closed with
their own tests: one flag stood for every mount and released `umount -R
/mnt` even when only `/mnt/.btrfs-top` was this run's (or when `/mnt` was
the operator's); the names travelled from installer to wrapper through a
temporary file whose write was never checked; and teardown errors were
hidden. `tests/unit.bats` checks newest-first unmounting of recorded
points only and the reported failures; `tests/bootstrap-contract.bats`
checks the refusal over a mounted `/mnt` and over an open mapper, in dry
run, and the wrapper's adoption without a side channel.
