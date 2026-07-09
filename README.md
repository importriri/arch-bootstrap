# arch-bootstrap

![lint](https://github.com/importriri/arch-bootstrap/actions/workflows/ci.yml/badge.svg)

A minimal, test-driven Arch Linux installer written in plain bash.

**Target stack (non-negotiable):** LUKS2 (argon2id) · Btrfs subvolumes ·
systemd-boot · `sd-encrypt` mkinitcpio hooks · Secure Boot via sbctl with
custom keys · `linux-hardened` · zram (no swap partition).

**The host it produces:** TTY only — no GPU driver, no Bluetooth, no desktop.
Its first job is to fetch the Ansible stage and become the lab, nothing else.
Networking is `iwd` (wifi, `iwctl`) plus `systemd-networkd` (wired DHCP) and
`systemd-resolved` (DNS), all enabled at install time; `git` and `ansible`
ship in the base set, so the machine is stage-2-ready the moment DNS resolves.

> ⚠️ **Status: work in progress — pre-alpha.**
> Partitioning and LUKS2 encryption are complete; the encryption path is
> unit-tested and its header verified for real (`luksDump` on a sparse file).
> Everything after it is not written yet. Do **not** run this against real
> hardware. Development happens against loop devices and QEMU/KVM snapshots only.

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
| 2 | rest  | 8309 | ARCH_ROOT  | LUKS2 container (argon2id) → Btrfs (next phase) |

No swap partition: zram only (configured in a later phase).

## Usage

```bash
# dry run (default): shows what every phase *would* do, writes nothing
sudo ./installer

# real run — only inside a VM for now
sudo DRY_RUN=0 ./installer
```

## Testing

```bash
shellcheck -x installer test-installer tests/*   # lint, everywhere
bats tests/unit.bats                              # unit: real functions, stubbed tools
sudo bash tests/luks-header-verify.sh             # REAL LUKS2 header on a sparse file
sudo ./test-installer                             # loop devices: the partitioning ladder
```

`unit.bats` sources the installer and runs the real functions with the
destructive binaries stubbed out; tests for phases that don't exist yet skip
themselves, so one suite follows the project through every milestone.
`luks-header-verify.sh` mocks nothing: it formats a sparse file and reads the
header back (`luksDump` — argon2id, aes-xts, 512-bit), then proves the
passphrase newline trap on a real keyslot. The loop-device
suite is unchanged: dependencies first, disposable images, teardown on every
exit path. No real disk is ever touched.

When the tooling itself breaks in interesting ways, the story gets a
writeup in [`problems/`](problems/).

## Roadmap

- [x] Preflight checks (root, 64-bit UEFI, network)
- [x] Interactive target disk selection (zram-aware, validated input)
- [x] Destruction gate (path re-typing, live-media guard)
- [x] GPT partitioning (dry-run by default, partlabels, kernel/udev sync)
- [x] Loop-device test suite
- [x] LUKS2 encryption (argon2id)
- [ ] Btrfs subvolume layout (`@`, `@home`, `@snapshots`, `@var_log`, …)
- [ ] Base install (pacstrap, `linux-hardened`, TTY-only package set)
- [ ] systemd-boot + `sd-encrypt` initramfs
- [ ] Secure Boot (sbctl, custom keys)
- [ ] zram configuration
- [ ] Network for a headless host: iwd + systemd-networkd + systemd-resolved
- [ ] Optional dual disk: LUKS2 container for `@vm`, keyfile-unlocked via crypttab
- [ ] Layered test suite (unit · real LUKS header · VM pipeline) wired into CI

## Context

Stage 1 of a three-stage build:
**arch-bootstrap** (base install, this repo) → **Ansible roles** (configuration, planned) →
**[arch-hypervisor-lab](https://github.com/importriri/arch-hypervisor-lab)** (the four-domain KVM/VFIO lab it all leads to).

## License

MIT
