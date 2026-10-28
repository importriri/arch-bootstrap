# arch-bootstrap threat model

What the installer protects, against whom, what it trusts, and where each
claim is checked. It covers one run of `bootstrap` from the Arch Linux live
medium, and the installed host as that run leaves it, before stage 2.

Stage 2 has its own
[threat model](https://github.com/importriri/hyperlab-ansible/blob/main/docs/threat-model.md).
It is a reference for what comes later, not evidence that its protections
exist right after bootstrap: a freshly installed host has none of the
network isolation, guest confinement, USB policy or audit that stage 2
describes until `hyperlab-ansible` has been applied to it, and those
protections then carry the evidence levels that page gives them.

Each claim below says where it is checked: a test that `bash verify.sh`
runs, the disposable two-disk gate `tests/vm-pipeline-test` (run only in a
throwaway VM, see [`release-gates.md`](release-gates.md)), or the source
alone. "Source only" means no automated check covers it. None of this is a
hardware observation: the clean-install and replay gates in
[`release-gates.md`](release-gates.md) are still pending.

## What is protected

- **Data at rest on the installed disks**: root, `/home`, logs, caches and
  the VM store, while the machine is powered off and the volumes are locked.
- **The root LUKS passphrase**: typed by the operator, never written to a
  file by the installer.
- **The VM-disk key** of the optional dedicated VM disk.
- **The Secure Boot signing keys** that `sbctl` generates inside the new
  system.
- **The disks the operator did not choose**, against accidental
  destruction, but only while none of them carries a partition labelled
  `ARCH_ESP`, `ARCH_ROOT` or `ARCH_VM` (see
  [Partition labels](#partition-labels-are-global)).
- **The storage hand-off**: stage 2 must receive a description of the VM
  store that matches what was actually mounted, or no description at all.

## What is trusted

Each of these is trusted completely. If one is compromised, nothing on this
page holds.

| Trusted input | Why it must be trusted | What the installer checks |
|---|---|---|
| The live medium | It runs the installer, reads every keystroke and holds the passphrase in memory. | Nothing about its authenticity. It must be booted in 64-bit UEFI mode (`check_uefi`); the disk holding `/run/archiso/bootmnt` is refused as a target (`confirm_wipe`). Verifying the downloaded image is the operator's job, with Arch Linux's own instructions. This project ships no image: [ADR 0001](adr/0001-iso-build-and-distribution.md) is a proposal and nothing of it is built. |
| The operator and the root session | The installer runs as root (`check_root`) and does what the person at the keyboard confirms. | That the confirmations match (see below). Anyone else with root in that session sees and can change everything. |
| The reviewed source | The installer does not verify its own integrity. | Nothing. Checking that `git rev-parse HEAD` is the commit they reviewed is the operator's job. |
| Packages and the keyring | `pacstrap` installs `PACSTRAP_PACKAGES` from the Arch mirrors; `pacman`, as the live medium configures it, checks package signatures against `archlinux-keyring`. | `pacstrap_base` refreshes `archlinux-keyring` on the live medium before it runs `pacstrap -K`. `encrypt_root` may upgrade `cryptsetup` on the live medium when it lacks argon2id. The mirrors and Arch Linux's signing keys are trusted. The licences of the packages it names are recorded, with open questions, in [`third-party-licences.md`](third-party-licences.md). |
| The selected disks | The operator chooses them. | Only that the typed path matches the chosen disk; nothing about its contents. |
| The firmware | It decides what boots and whether Secure Boot is enforced. | Only UEFI mode and 64-bit size. Firmware settings, updates and passwords are out of scope. |
| The generated signing keys | Whoever holds them can sign a boot loader or kernel the firmware will accept once they are enrolled. | They are created inside the target root (`setup_secureboot`), so they are on the encrypted root volume, readable by root on the running host. |

The network is not trusted for integrity: package signatures carry that.
`check_network` only refuses to start without a reply from `archlinux.org`.

## Who is considered

1. **Someone who takes the powered-off laptop or a removed disk.** LUKS2
   stands between them and the data, as strong as the passphrase.
2. **The operator making a mistake**: the wrong disk, a real run instead of
   a rehearsal, a rerun over an earlier run's leftovers. The guards below
   are against accidents, not attackers: anyone with root on the live
   medium can bypass them by running `cryptsetup` or `sgdisk` directly.
3. **A run that fails half way**: a tool error, a full disk, an interrupted
   write. The installer stops, says what it left, and does not hand
   unverified storage to stage 2.

Not considered: an attacker who controls the live medium, the root session,
the repository checkout, the package mirrors together with a signing key,
or the firmware; an attacker with write access to the EFI system partition
(see [Secure Boot](#secure-boot-what-is-signed-what-is-not)); an attacker on
the running, unlocked host.

## Mechanisms and their evidence

### Accident guards

| Mechanism | Source | Checked by | Limit |
|---|---|---|---|
| The dry run is the default: `DRY_RUN=1` unless set; it writes nothing and runs only `sgdisk --pretend`, `cryptsetup --help` and `cryptsetup isLuks`, besides read-only probes | `installer`: `DRY_RUN`, every step's dry-run branch | `tests/unit.bats`: "a full dry run reaches no tool but sgdisk --pretend and cryptsetup's probes"; `tests/bootstrap-contract.bats`: "a dry run of the whole entrypoint changes nothing, at its exit either" | Bash evaluates `DRY_RUN` as an arithmetic expression. Anything that evaluates to `0` is a real run: `0`, but also `00` or `1-1`. A word such as `yes`, `true` or `no` is read as the name of a variable: under the installer's `set -u`, when that variable is unset, the run stops with `unbound variable` at partitioning, after the disk prompts and before any write; when it is set, its value decides. Use exactly `DRY_RUN=0` for a real run and leave it unset (or `1`) otherwise. |
| Every selected disk is confirmed by typing its full path back | `confirm_wipe` | `tests/unit.bats`: "confirm_wipe accepts the exact path", "confirm_wipe rejects a wrong path" | A correctly retyped wrong disk is destroyed. There is no undo and no backup step: the operator verifies an external backup first. |
| The disk holding the live medium is refused | `confirm_wipe` (`/run/archiso/bootmnt`) | Source only | Works only when the medium is mounted at that Archiso path. |
| The primary disk is removed from the optional VM-disk menu | `check_disk` (second argument), `main` | Source only; gate 4 asks the operator to observe it | — |
| Partitions are addressed by GPT partition label, never by a `sda1`-style name | `ESP_PART`, `ROOT_PART`, `VM_PART`; `partition_disk`, `encrypt_vm_disk` | Source; `tests/vm-pipeline-test` on fresh loop devices | The label path is global, not tied to the confirmed disk: see [Partition labels](#partition-labels-are-global). |
| A run refuses to start while `/mnt`, `cryptroot` or `cryptvm` is in use, or when the mounts cannot be listed | `refuse_busy_target` | `tests/bootstrap-contract.bats`: "a run refuses to start over a mounted /mnt, and the dry run says so", "a run refuses to start over an open cryptroot or cryptvm", "a run refuses to start when the mounts cannot be listed" | It looks only at `/mnt` and those two mapper names. |

### Partition labels are global

After it partitions a confirmed disk, the installer reaches the new
partitions through `/dev/disk/by-partlabel/ARCH_ESP`, `ARCH_ROOT` and
`ARCH_VM`. Those links are named after a label, not after the disk. The
installer checks only that a link exists (`partition_disk`,
`encrypt_vm_disk`), not that it points to a partition of the disk just
confirmed, and then runs `wipefs`, `mkfs.fat`, `cryptsetup luksFormat` and
`mount` on it. When several devices claim the same link, udev gives it to
the one with the highest `link_priority`, and when no priority is set,
which one owns it is undefined
([`udev(7)`](https://www.freedesktop.org/software/systemd/man/latest/udev.html), `SYMLINK`).
No test covers a second disk carrying the same label.

So a disk that was never confirmed can be destroyed when it already carries
one of the three labels: an external disk from an earlier installation,
or, in a two-disk run, the disk about to be dedicated to VM storage, which
is cleared only after the root partitions have been formatted. The dry run
does not look for this.

Before a real run, list the labels of every attached disk:

```bash
# Show every disk and partition with its GPT partition label.
lsblk -o NAME,TYPE,SIZE,PARTLABEL
```

Stop if `ARCH_ESP` or `ARCH_ROOT` appears on any disk other than the one
you will confirm as the target, or `ARCH_VM` on any disk other than the
target and the one you will dedicate to VM storage. Disconnecting every
disk you are not installing to is the simplest way to rule this out. Old
labels on the target disk itself are not a problem: it is cleared before
the links are read.

### Encryption at rest

| Mechanism | Source | Checked by | Limit |
|---|---|---|---|
| Root is LUKS2 with argon2id, `aes-xts-plain64`, a 512-bit key and `sha512` | `installer`: `LUKS_*` constants, `encrypt_root` | `tests/luks-header-verify.sh` formats a real header with those constants and reads it back; `tests/unit.bats` covers the argon2id probe; `tests/vm-pipeline-test` on loop devices | Only data written after installation is encrypted. `luksFormat` does not wipe the data area (`cryptsetup-luksFormat(8)`), and the installer clears only partition tables and signatures (`sgdisk --zap-all`, `wipefs`), so earlier plaintext on the disk can remain readable until overwritten. The ESP is not encrypted. |
| The passphrase is read without echo, confirmed, refused when empty, and passed to `cryptsetup` on standard input with no trailing newline; it is never written to a file | `read_passphrase`, `encrypt_root` | `tests/unit.bats`: the three `read_passphrase` tests; `tests/luks-header-verify.sh`: the newline trap | It lives in the memory of the root shell during the run. The dry run asks for it too, to prove the match, and discards it. |
| An optional second disk is a separate LUKS2 container with the same parameters, unlocked at boot by a random 4096-byte key file stored on the encrypted root at `/etc/cryptsetup-keys.d/cryptvm.key`, mode `0400` | `encrypt_vm_disk`, `finalize_vm_storage_key` | `tests/bootstrap-contract.bats`: "dedicated key finalization requires a regular keyfile and mode 0400"; `tests/unit.bats`: "encrypt_vm_disk adds a keyfile-based crypttab entry and adopts the fstab line"; `tests/vm-pipeline-test` | The VM disk is exactly as safe as the root volume: whoever unlocks root, or is root on the running host, can read the key. The key file is the container's only key, so losing or reformatting the root volume makes the VM disk unreadable. The `crypttab` line has no `x-initrd.attach` option, so the key is read from the unlocked root rather than placed in the initramfs; this is not observed on an installed host. |
| No swap on disk: swap is zram, in memory | `configure_zram` | `tests/unit.bats`: "configure_zram dry-run mentions no swap partition" | The installer configures nothing that removes keys from memory before suspend: a sleeping machine is an unlocked one. |

### Storage hand-off

| Mechanism | Source | Checked by | Limit |
|---|---|---|---|
| The VM store gets `chattr +C` while empty, so VM images below it inherit No_COW | `mount_layout`, `encrypt_vm_disk` | `tests/unit.bats`: "VM storage relies on chattr +C, not a misleading nodatacow mount option"; `tests/vm-pipeline-test` | A storage and performance condition, not a security property. No_COW means in-place writes, which `btrfs(5)` says come "at the cost of potential partial writes" when interrupted; it also documents that the `nodatacow` mount option, which sets this same attribute, implies `nodatasum`. Do not count on Btrfs to detect corruption of a VM image. |
| Before writing the hand-off, `bootstrap` observes the VM store: mapper, Btrfs, filesystem root (`/@vm` on `cryptroot` or `/` on `cryptvm`), a real directory, `+C`, empty | `bootstrap`: `detect_vm_storage_topology`, `verify_vm_storage` | `tests/bootstrap-contract.bats`: "topology detection distinguishes cryptroot @vm from cryptvm root", "storage verification accepts the declared fsroot and rejects drift" | It checks the state at install time only. |
| `/etc/privatestack/bootstrap-storage.yml` is written only after those checks pass; a failed write, ownership or mode change stops `bootstrap` with a non-zero exit and without its final `[OK]` | `write_storage_contract`, `bootstrap_main` | `tests/bootstrap-contract.bats`: the "contract refuses ..." and "bootstrap refuses ..." tests, both topologies; the comparison with stage 2's own guard runs in required mode (see [`release-gates.md`](release-gates.md)) | The file is non-secret, plain YAML, `root:root 0644`, with no signature: it is a description, not an integrity proof, and root on the installed host can change it. There is no atomic replacement: an interrupted write can leave a partial file, and a run that does not end with `[OK] arch-bootstrap complete` is a failed installation whatever file it left. |

### Cleanup after a failure

| Mechanism | Source | Checked by | Limit |
|---|---|---|---|
| At exit, a failed real run unmounts what it mounted, newest first, then closes `cryptvm` and `cryptroot` if it opened them; it names what it could not release. A dry run releases nothing because it took nothing | `installer`: `cleanup`, `own_mount`, `own_mapper`; `bootstrap`: `adopt_installer_work` | `tests/unit.bats`: "cleanup unmounts, newest first, only the mount points this run recorded", "cleanup says what it could not undo and how to finish it"; `tests/bootstrap-contract.bats`: "the wrapper owns what a successful installer leaves, without a side channel" and the "bootstrap refuses ... and cleans up adopted resources" tests | Cleanup is not rollback. Partition tables, LUKS headers and filesystems already written stay written, and what they replaced cannot be restored. Nothing is promised across a power loss or a killed process: a run stopped that way leaves whatever it had mounted or opened, and the next run refuses to start until it is released. |

## Secure Boot: what is signed, what is not

Three separate things, of which the installer does only the first:

1. **Signing.** `setup_secureboot` runs `sbctl create-keys` inside the new
   system and signs `/boot/EFI/systemd/systemd-bootx64.efi`,
   `/boot/EFI/BOOT/BOOTX64.EFI` and `/boot/vmlinuz-linux-hardened`. The
   dry-run branch is tested (`tests/unit.bats`: "setup_secureboot dry-run
   signs nothing and defers enrollment to the user"); the real signing path
   is source only. What re-signs these files after a later package update
   is `sbctl`'s business, not tested here.
2. **Enrollment.** The keys do nothing until the operator puts the firmware
   in Setup Mode, runs `sbctl enroll-keys` and enables Secure Boot. The
   installer only prints this step. Until it is done, the signatures
   protect nothing: with Secure Boot off, the firmware checks none. Whether
   a given firmware accepts the keys and enforces them is not proved by
   this repository.
3. **Protecting the initramfs and the kernel command line.** Not done. The
   initramfs `/boot/initramfs-linux-hardened.img` and the loader entry that
   holds the command line are unsigned files on the unencrypted FAT ESP.
   `editor no` in `loader.conf` only stops editing the command line at the
   boot menu (source only); it does not stop anyone who can write the ESP.

So even with keys enrolled, whoever can write the ESP, for a few minutes
with the machine powered off or as root on the running host, can replace
the initramfs and capture the passphrase at the next boot. There is no
measured boot, no TPM binding, no PIN and no unified kernel image; this is
not protection against an evil-maid attack. A signed installer image does
not exist either.

## Locked is not the same as unlocked

LUKS protects a powered-off machine whose volumes are locked. Once the
passphrase is typed, the running host holds the volume keys in memory, the
VM-disk key file is readable by root, and the Secure Boot private keys sit
on the root filesystem. Anyone with root on the running host, or a kernel
compromise, has all of it. The installer adds no defence for the unlocked
host beyond its package list: it installs no SSH server and enables only
`iwd`, `systemd-networkd` and `systemd-resolved`, it configures no
firewall, and it creates no user account: only `root` gets a password, set
by the operator.

## Isolation is stage 2's job

`bootstrap` installs no hypervisor and isolates nothing. It prepares an
encrypted store for VM images; how guests are separated from each other and
from the host is decided and checked by `hyperlab-ansible`, with the limits
its threat model lists. HyperLab is not Qubes OS and does not provide Qubes
OS security properties.

## Hardware evidence

The Nitro 5 has run the bootstrap-to-stage-2 host path, and individual
components have repeatable evidence there. That history is not acceptance
of the frozen pipeline: `arch-hypervisor-lab` records both the Nitro and
the Predator as `pipeline-pending`, and the clean installation, encryption,
mount and boot observations of gates 3 and 4 in
[`release-gates.md`](release-gates.md) are pending for both.

## Cases reviewed against this page

| Case | What happens | Where it is said |
|---|---|---|
| Compromised live medium or root session | Not defended: it sees the passphrase and can write anything. | [What is trusted](#what-is-trusted) |
| Wrong disk confirmed | It is destroyed; the guard only proves the typed path matches. | [Accident guards](#accident-guards) |
| Another attached disk already carries `ARCH_ROOT`, `ARCH_ESP` or `ARCH_VM` | Not detected: the label path may resolve to that disk, which is then wiped, encrypted or formatted although the right disk was confirmed. The operator checks the labels and stops. | [Partition labels](#partition-labels-are-global) |
| Partial contract write | `bootstrap` stops non-zero, cleans up its own mounts and mappers, prints no final `[OK]`; a partial file may remain and the installation counts as failed. | [Storage hand-off](#storage-hand-off) |
| Modified initramfs on the ESP | Not detected, even with keys enrolled. | [Secure Boot](#secure-boot-what-is-signed-what-is-not) |
| Keys never enrolled | The firmware checks none of the signatures the installer made. | [Secure Boot](#secure-boot-what-is-signed-what-is-not) |
| Private reporting disabled | The reporter keeps the details private; no other channel is invented. | [`SECURITY.md`](../SECURITY.md) |

## Still with the operator

- enabling GitHub private vulnerability reporting for this repository and
  checking that the form opens;
- verifying the live medium, the reviewed commit and an external backup
  before a real run;
- checking that no other attached disk carries an `ARCH_ESP`, `ARCH_ROOT`
  or `ARCH_VM` label before a real run;
- Secure Boot enrollment and firmware settings on each machine;
- the clean-install and replay gates on Nitro and Predator;
- the open licence questions in
  [`third-party-licences.md`](third-party-licences.md) and the installer
  image proposed in [ADR 0001](adr/0001-iso-build-and-distribution.md).
