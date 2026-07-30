# arch-bootstrap

[![ci](https://github.com/importriri/arch-bootstrap/actions/workflows/ci.yml/badge.svg)](https://github.com/importriri/arch-bootstrap/actions/workflows/ci.yml)

A plain Bash installer for the encrypted Arch Linux base used by my KVM/VFIO
laptop lab.

It installs:

- LUKS2 with Argon2id;
- Btrfs subvolumes;
- systemd-boot and `sd-encrypt`;
- `linux-hardened`;
- Secure Boot keys managed with `sbctl`;
- zram instead of a swap partition;
- iwd, systemd-networkd and systemd-resolved;
- Git and Ansible for the second configuration stage.

The installed system is TTY-only. GPU drivers, the desktop and libvirt are
configured later by
[privatestack-ansible](https://github.com/importriri/privatestack-ansible).

> **Status: pre-release.** The script, unit tests and disposable storage tests
> are available. A successful VM run does not replace a clean install and boot
> check on each target laptop.

## Safety model

`DRY_RUN=1` is the default. The installer prints the planned operations and
uses `sgdisk --pretend` without writing a partition table.

A real run requires the full target device path to be typed again. The script
also refuses the live boot medium and checks the result of each destructive
step. Partitions are referenced by GPT partlabel rather than names such as
`sda1` or `nvme0n1p1`.

## Disk layout

| Partition | Size | Type | Partlabel | Purpose |
|---|---:|---|---|---|
| ESP | 1 GiB | `ef00` | `ARCH_ESP` | systemd-boot, kernel and initramfs |
| Root | remaining space | `8309` | `ARCH_ROOT` | LUKS2 container with Btrfs |

Root subvolumes:

| Subvolume | Mount point | Notes |
|---|---|---|
| `@` | `/` | Includes the pacman database so a root rollback remains consistent |
| `@home` | `/home` | User data |
| `@snapshots` | `/.snapshots` | Snapshot mount |
| `@var_log` | `/var/log` | Logs survive a root rollback |
| `@var_cache` | `/var/cache` | Package and application caches |
| `@var_tmp` | `/var/tmp` | Persistent temporary files |
| `@vm` | `/var/lib/libvirt/images` | Created empty and marked `+C` |

The normal Btrfs mounts use `compress=zstd:1,noatime`. VM storage relies on the
per-directory No_COW attribute instead of a filesystem-wide `nodatacow` mount
option.

An optional second disk can be formatted as an encrypted `cryptvm` filesystem.
A root-only keyfile unlocks it through `/etc/crypttab`, and the installer mounts
it at `/var/lib/libvirt/images`. The root filesystem's empty `@vm` subvolume is
left as a fallback.

## Usage

```bash
# Default dry run
sudo ./installer

# Real write path: use only on a disposable VM or a disk you intend to erase
sudo DRY_RUN=0 ./installer
```

A real run asks for the LUKS passphrase and the root password for the new
system.

## First boot

```bash
iwctl station wlan0 connect "YOUR-SSID"   # or connect Ethernet
ping -c1 archlinux.org
git clone https://github.com/importriri/privatestack-ansible
```

## Verification

```bash
shellcheck -x installer test-installer tests/*
bats tests/unit.bats
sudo bash tests/luks-header-verify.sh
sudo VM_TEST=1 ./tests/vm-pipeline-test
sudo ./test-installer
```

The unit suite sources the real installer functions while replacing destructive
commands. `luks-header-verify.sh` creates and reads a real LUKS2 header on a
sparse file. The VM pipeline and loop-device suite use disposable devices and
tear them down on every exit path.

Release and hardware checks are listed in
[`docs/release-gates.md`](docs/release-gates.md). Problems that changed the
implementation are kept under [`problems/`](problems/).

## Project context

```text
arch-bootstrap  ->  privatestack-ansible  ->  arch-hypervisor-lab
base install        host configuration        architecture and test records
```

## License

MIT
