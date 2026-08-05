# arch-bootstrap

![lint](https://github.com/importriri/arch-bootstrap/actions/workflows/ci.yml/badge.svg)

A minimal, test-driven Arch Linux bootstrap written in Bash.

**Target stack:** LUKS2/argon2id · Btrfs subvolumes · systemd-boot ·
`sd-encrypt` mkinitcpio hooks · Secure Boot keys through `sbctl` ·
`linux-hardened` · zram, with no swap partition.

**The host it produces:** TTY only: no GPU driver, Bluetooth or desktop. Its
first job is to fetch
[`privatestack-ansible`](https://github.com/importriri/privatestack-ansible)
and become the hypervisor lab. `iwd`, `systemd-networkd`,
`systemd-resolved`, Git and Ansible are installed and enabled before hand-off.

> **Status: Nitro host path validated; release evidence still pending.** The
> complete local verifier, disposable two-loop-device storage gate and
> bootstrap-to-stage-2 host path have been exercised on the Nitro 5. A stable
> release still requires frozen clean-install evidence on Nitro and Predator.

## Entrypoints

`bootstrap` is the complete public entrypoint. It runs the tested `installer`
engine and then verifies the mounted VM store and writes the versioned stage-2
contract. Invoke it explicitly with Bash so the command is independent of the
checkout's executable-bit preservation. `installer` remains an internal,
sourceable engine for fine-grained unit tests; using it directly omits the final
Ansible hand-off contract.

## Safety principles

- `DRY_RUN=1` is the default. Partitioning uses `sgdisk --pretend` and writes
  nothing until the operator explicitly sets `DRY_RUN=0`.
- Every selected disk requires the full device path to be retyped. The live
  Archiso medium is refused.
- The primary disk is removed from the optional VM-disk menu; it cannot be
  selected twice.
- Partitions are resolved through GPT partlabels, never by concatenating
  `sda1`/`nvme0n1p1` names.
- A two-disk installation is accepted only after `cryptvm` is mounted at the
  libvirt image path, Btrfs filesystem root `/` is observed and the empty
  directory carries `+C`.
- The stage-2 contract is written only after those post-conditions pass.
- The disposable two-loop gate reaps stale state only after proving that a
  mapper belongs to one of its `/tmp/bootstrap-{root,vm}.*` sparse fixtures.
  Any other existing `cryptroot` or `cryptvm` is refused and never closed.
- A teardown failure is visible and fails the gate; cleanup is part of the
  release contract rather than a best-effort courtesy.

## Primary disk layout

```text
ARCH_ESP    1 GiB       EFI System Partition → /boot
ARCH_ROOT   remainder   LUKS2 cryptroot → Btrfs
```

Inside `cryptroot`:

```text
@             /                         root and pacman database
@home         /home                     user data
@snapshots    /.snapshots               snapshot namespace
@var_log      /var/log                  survives root rollback
@var_cache    /var/cache                package and application cache
@var_tmp      /var/tmp                  persistent temporary data
@vm           /var/lib/libvirt/images   empty +C inheritance source
```

Btrfs mount options are filesystem-wide, so the project does not claim a
per-subvolume `nodatacow` option. The enforceable VM-image contract is `chattr
+C` while the target is empty, before any qcow2 exists.

## Optional dedicated VM disk

With two disks, the second selected disk is completely dedicated to VM state:

1. GPT is replaced by one `ARCH_VM` partition;
2. the partition becomes LUKS2 mapper `cryptvm`;
3. a random key is stored inside encrypted root at
   `/etc/cryptsetup-keys.d/cryptvm.key`, mode `0400`;
4. `/etc/crypttab` binds `cryptvm` to the LUKS UUID and keyfile;
5. a fresh Btrfs filesystem is mounted at `/var/lib/libvirt/images`;
6. the root-side `@vm` fstab line is removed and replaced by `cryptvm`;
7. mapper, filesystem root, Btrfs, `+C` and emptiness are verified;
8. `/etc/privatestack/bootstrap-storage.yml` records the hand-off.

The root-side `@vm` remains empty and unmounted as a fallback. All HyperLab
content created later below `/var/lib/libvirt/images/hyperlab` therefore lives
on the dedicated encrypted disk: bases, permanent/disposable VM disks,
cloud-init, NVRAM, TPM state, snapshots, exports and service backups.

The contract is deliberately small and non-secret:

```yaml
schema_version: 1
vm_store:
  topology: dedicated-disk
  mountpoint: /var/lib/libvirt/images
  mapper: /dev/mapper/cryptvm
  fstype: btrfs
  subvolume: null
  require_nocow: true
  root_partlabel: ARCH_ROOT
  vm_partlabel: ARCH_VM
```

A single-disk installation writes the same schema with `topology: single-disk`,
mapper `/dev/mapper/cryptroot`, `subvolume: "@vm"` and `vm_partlabel: null`.

## Usage

```bash
# Inspect the complete installation plan without writing partition tables.
sudo bash bootstrap

# Apply the printed plan; this erases every explicitly confirmed target disk.
sudo env DRY_RUN=0 bash bootstrap
```

The real run asks for the root LUKS passphrase, root password and optionally a
second destructive disk confirmation. Secure Boot key enrollment remains a
manual firmware step after the generated assets are reviewed.

## First boot

```bash
# Connect the new host to Wi-Fi; wired DHCP needs no iwctl command.
iwctl station wlan0 connect "YOUR-SSID"

# Verify local networking, DNS resolution and internet reachability.
ping -c1 archlinux.org

# Fetch the stage-2 automation.
git clone https://github.com/importriri/privatestack-ansible

# Enter the repository root so every relative contract path resolves correctly.
cd privatestack-ansible

# Install the exact Ansible collections declared by stage 2.
ansible-galaxy collection install -r collections/requirements.yml

# Detect the matching hardware profile without changing the host.
ansible-playbook -K playbooks/preflight.yml

# Preview the complete host target and show the managed diff.
ansible-playbook -K playbooks/lab.yml --check --diff

# Reconcile the complete host target.
ansible-playbook -K playbooks/lab.yml

# Prove idempotence; this pass must report changed=0.
ansible-playbook -K playbooks/lab.yml

# Run the complete Stage 2 software verifier.
./verify.sh
```

The preflight validates the bootstrap contract before any HyperLab image or VM
state is created. `lab.yml` then reconciles the headless foundation, Sway, VFIO
and the Looking Glass host side. The second real apply must report `changed=0`.
Image import and VM lifecycle operations remain explicit because they create or
destroy private workload state.

## Verification

Hosted CI and local verification use the same entrypoint:

```bash
# Run syntax, lint, Bats and real sparse-file LUKS2 verification.
sudo bash verify.sh
```

That command discovers every shipped shell path and runs Bash syntax,
ShellCheck, all Bats contracts and the real sparse-file LUKS2 header gate.

The remaining storage test deliberately needs an Arch-capable throwaway VM with
device-mapper, udev and mount support:

```bash
# Exercise the destructive storage path only on two disposable loop devices.
sudo VM_TEST=1 bash tests/vm-pipeline-test
```

It uses two sparse loop devices and proves:

- root and VM LUKS2 headers;
- GPT partlabels and mapper identities;
- Btrfs root subvolumes and ESP mount;
- `+C` inheritance without a false `nodatacow` mount-option claim;
- VM-key mode `0400`;
- crypttab/fstab adoption of `cryptvm`;
- exact mounted source `/dev/mapper/cryptvm` and filesystem root `/`;
- safe reruns after a verified stale test fixture;
- final stage-2 storage contract;
- complete teardown with no mapper or loop state hidden behind ignored errors.

`test-installer` remains a narrower disposable-loop partitioning harness; it is
not a substitute for the complete two-disk gate.

Release procedure: [`docs/release-gates.md`](docs/release-gates.md).
Interesting tooling failures are indexed under
[`problems/README.md`](problems/README.md).

## Roadmap

- [x] preflight, destructive gates and stable disk selection;
- [x] LUKS2 root and Btrfs subvolume layout;
- [x] headless base, networking, systemd-boot, hardened kernel and zram;
- [x] Secure Boot key generation/signing with manual enrollment;
- [x] optional encrypted dedicated VM disk;
- [x] verified stage-2 storage contract for single- and two-disk layouts;
- [x] one local/hosted verification entrypoint;
- [x] two-loop-device release gate implemented;
- [x] safe rerun and visible teardown contract implemented;
- [x] complete two-loop-device PASS evidence from the disposable Arch VM;
- [x] Nitro bootstrap-to-stage-2 host-path evidence;
- [ ] Nitro clean-install evidence on the frozen release candidate;
- [ ] Predator clean-install and portability evidence on the same candidate.

## Project context

`arch-bootstrap` builds the encrypted base host → `privatestack-ansible`
reconciles the hypervisor host and manages guest and service lifecycle →
[`arch-hypervisor-lab`](https://github.com/importriri/arch-hypervisor-lab)
records architecture and sanitized hardware evidence.

## License

MIT
