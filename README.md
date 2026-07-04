# arch-bootstrap

A minimal, test-driven Arch Linux installer written in plain bash.

**Target stack (non-negotiable):** LUKS2 (argon2id) · Btrfs subvolumes ·
systemd-boot · `sd-encrypt` mkinitcpio hooks · Secure Boot via sbctl with
custom keys · `linux-hardened` · zram (no swap partition).

> ⚠️ **Status: work in progress — pre-alpha.**
> The partitioning phase is complete and tested; encryption and everything
> after it are not written yet. Do **not** run this against real hardware.
> Development happens against loop devices and QEMU/KVM snapshots only.

## Design principles

- **Safe by default.** `DRY_RUN=1` unless you explicitly say otherwise:
  the script shows what it *would* do (`sgdisk --pretend`) and writes nothing.
- **Verify, don't trust.** Every destructive step sits behind an explicit
  gate (retype the full disk path to confirm) and a guard (refuses to wipe
  the live boot medium). Every critical command checks its own exit code —
  `set -e` is the net, not the plan.
- **Tested before trusted.** A companion test suite exercises the real
  functions (sourced, not copied) against loop devices: the gate, the
  dry-run honesty, the real write path, udev symlinks, GPT contents.
- **Stable references.** Partitions are addressed via GPT partlabels
  (`/dev/disk/by-partlabel/…`), never by concatenated device names —
  immune to the `sda1` vs `nvme0n1p1` suffix trap.

## Layout produced

| # | Size | Type | Partlabel  | Purpose                          |
|---|------|------|------------|----------------------------------|
| 1 | 1 GiB | ef00 | ARCH_ESP   | EFI System Partition (kernel + initramfs live here with systemd-boot) |
| 2 | rest  | 8309 | ARCH_ROOT  | LUKS2 container → Btrfs (next phase) |

No swap partition: zram only (configured in a later phase).

## Usage

```bash
# dry run (default): shows the resulting table, writes nothing
sudo ./installer

# real run — only inside a VM for now
sudo DRY_RUN=0 ./installer
```

## Testing

```bash
sudo ./test-installer      # needs: gptfdisk, parted, util-linux
shellcheck -x test-installer
```

The suite checks its own dependencies first, builds disposable sparse
images, attaches a loop device, and walks the whole ladder: lint → gate
(reject/accept) → dry-run (must fail honestly on a too-small disk, pass on
a correct one) → real write → udev symlinks → GPT read-back. Teardown runs
on every exit path. No real disk is ever touched.

## Roadmap

- [x] Preflight checks (root, 64-bit UEFI, network)
- [x] Interactive target disk selection (zram-aware, validated input)
- [x] Destruction gate (path re-typing, live-media guard)
- [x] GPT partitioning (dry-run by default, partlabels, kernel/udev sync)
- [x] Loop-device test suite
- [ ] LUKS2 encryption (argon2id)
- [ ] Btrfs subvolume layout (`@`, `@home`, `@snapshots`, `@var_log`, …)
- [ ] Base install (pacstrap, `linux-hardened`)
- [ ] systemd-boot + `sd-encrypt` initramfs
- [ ] Secure Boot (sbctl, custom keys)
- [ ] zram configuration

## Context

Stage 1 of a three-stage build:
**arch-bootstrap** (base install, this repo) → **Ansible roles** (configuration, planned) →
**[arch-hypervisor-lab](https://github.com/importriri/arch-hypervisor-lab)** (the four-domain KVM/VFIO lab it all leads to).

## License

MIT
