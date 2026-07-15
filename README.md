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
> The installed system boots into a TTY: systemd-boot entry built on
> `rd.luks.name` (the LUKS UUID, not the GPT PARTUUID), zram in place of a
> swap partition, wifi one `iwctl` away. Secure Boot is not written yet.
> Do **not** run this against real hardware — QEMU/KVM snapshots only.

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
| 2 | rest  | 8309 | ARCH_ROOT  | LUKS2 container (argon2id) → Btrfs subvolumes |

No swap partition: zram only.

Inside the container, all mounted `compress=zstd:1,noatime` — except `@vm`:

| Subvolume | Mounted at | Notes |
|-----------|------------|-------|
| `@` | `/` | pacman's db stays in here on purpose: a rollback of `@` can never desync it |
| `@home` | `/home` | |
| `@snapshots` | `/.snapshots` | |
| `@var_log` | `/var/log` | survives a root rollback |
| `@var_cache` | `/var/cache` | |
| `@var_tmp` | `/var/tmp` | |
| `@vm` | `/var/lib/libvirt/images` | `nodatacow` + `chattr +C`, no compression — COW and VM images don't mix |

## Usage

```bash
# dry run (default): shows what every phase *would* do, writes nothing
sudo ./installer

# real run — only inside a VM for now
sudo DRY_RUN=0 ./installer
# a full real run asks two things along the way:
# the LUKS passphrase and the root password for the new system
```

## First boot

```bash
# unlock at the sd-encrypt prompt, log in as root, then:
iwctl station wlan0 connect "YOUR-SSID"   # wifi — or just plug ethernet in
ping -c1 archlinux.org                    # networkd + resolved sanity check
git clone https://github.com/importriri/privatestack-ansible   # stage 2
```

`git` and `ansible` are already installed: no pacman round-trip stands
between an unlocked disk and the first playbook.

## Testing

```bash
shellcheck -x installer test-installer tests/*   # lint, everywhere
bats tests/unit.bats                              # unit: real functions, stubbed tools
sudo bash tests/luks-header-verify.sh             # REAL LUKS2 header on a sparse file
sudo VM_TEST=1 ./tests/vm-pipeline-test           # VM only: partition → LUKS → Btrfs → mount, for real
sudo ./test-installer                             # loop devices: the partitioning ladder
```

`unit.bats` sources the installer and runs the real functions with the
destructive binaries stubbed out; tests for phases that don't exist yet skip
themselves, so one suite follows the project through every milestone.
`luks-header-verify.sh` mocks nothing: it formats a sparse file and reads the
header back (`luksDump` — argon2id, aes-xts, 512-bit), then proves the
passphrase newline trap on a real keyslot. The pipeline test runs the real
write path end to end on a loop device and asserts what matters: seven
subvolumes, `compress=zstd:1` on `@`, `nodatacow`+`+C` on `@vm`, the ESP on
`/boot` — and outside a VM it skips itself and says why. The loop-device
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
- [x] Btrfs subvolume layout (`@`, `@home`, `@snapshots`, `@var_log`, …)
- [x] Base install (pacstrap, `linux-hardened`, TTY-only package set)
- [x] systemd-boot + `sd-encrypt` initramfs
- [ ] Secure Boot (sbctl, custom keys)
- [x] zram configuration
- [x] Network for a headless host: iwd + systemd-networkd + systemd-resolved
- [ ] Optional dual disk: LUKS2 container for `@vm`, keyfile-unlocked via crypttab
- [ ] Layered test suite (unit · real LUKS header · VM pipeline) wired into CI

## Context

Stage 1 of a three-stage build:
**arch-bootstrap** (base install, this repo) → **Ansible roles** (configuration, planned) →
**[arch-hypervisor-lab](https://github.com/importriri/arch-hypervisor-lab)** (the four-domain KVM/VFIO lab it all leads to).

## License

MIT
