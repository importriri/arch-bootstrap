# Release gates

The bootstrap is released as one exact pipeline, not as a generic claim that
every laptop is identical. Compatibility is recorded only against frozen
commits and sanitized M9 evidence.

## Gate 1 — software verification

Hosted CI and local verification execute the same command:

```bash
sudo bash verify.sh
```

It must pass Bash syntax, ShellCheck, all Bats contracts and real LUKS2 header
inspection. The M9 `repository-proof` gate runs this entrypoint from the frozen
checkout and records only the combined verification hash, clean-worktree state
and exact commit identity.

## Gate 2 — disposable two-disk VM

Run this inside an Arch-capable throwaway VM:

```bash
sudo VM_TEST=1 bash tests/vm-pipeline-test
```

The gate uses two sparse loop devices and real GPT, LUKS, device-mapper, Btrfs,
mount, crypttab and fstab operations. It must prove the dedicated VM disk is
mounted from `/dev/mapper/cryptvm` at filesystem root `/`, carries `+C`, uses a
`0400` keyfile and produces `/etc/privatestack/bootstrap-storage.yml`.

A rerun is part of the contract. If an earlier failed attempt left a mapper or
loop attached, the gate may reap it only after proving that the mapper resolves
to a loop backed by `/tmp/bootstrap-root.*` or `/tmp/bootstrap-vm.*`. Any other
existing `cryptroot` or `cryptvm` is refused and never closed automatically.
Teardown errors are visible and make the gate fail.

Record the complete local log and its SHA-256. A skipped test, hidden cleanup
failure or missing final marker is not a pass.

## Gate 3 — Nitro clean installation

1. verify an external backup;
2. boot the reviewed Archiso in 64-bit UEFI mode;
3. run `sudo bash bootstrap` and retain the dry-run log locally;
4. run `sudo env DRY_RUN=0 bash bootstrap` against the intended disk layout;
5. complete Secure Boot enrollment;
6. boot `linux-hardened` twice;
7. verify LUKS2, Btrfs mounts, `+C`, fstab, crypttab, keyfile mode, networking and
   the stage-2 contract;
8. run the frozen `privatestack-ansible` foundation and full Nitro campaign;
9. record reviewed scalar evidence through the M9 runner.

The Nitro PCIe power-management workaround remains part of the managed VFIO
profile. It was isolated on Nitro before being reused on Predator; routine
release testing does not deliberately remove it and reintroduce a hard freeze.

## Gate 4 — Predator portability installation

Predator must use the exact bootstrap and Ansible commits that passed Nitro.
Before a real write, confirm the menu identifies the intended primary and
dedicated VM disks and removes the primary disk from the second selection.

Repeat the Nitro sequence and additionally prove:

- the observed VM mount source and filesystem root match the declared topology;
- all Hyperlab state below `/var/lib/libvirt/images/hyperlab` is physically on
  the dedicated encrypted disk;
- reboot unlocks `cryptroot`, then keyfile-unlocks and mounts `cryptvm` without a
  second passphrase;
- absence or drift of the storage contract stops Ansible before VM-state writes;
- the Nitro-derived `pcie_port_pm=off` fix remains effective on the RTX 3070
  profile.

## Evidence and merge rule

A component fix, hosted green CI or one successful laptop does not authorize a
merge by itself. The M9 campaign receipt must bind:

```text
exact arch-bootstrap commit
exact privatestack-ansible commit
disposable two-disk proof
Nitro ordered gate result
Predator ordered gate result
sanitized publication hash
```

Only after the corresponding hardware gate passes may its reviewed milestone be
merged. Any software fix changes the frozen identity and requires the affected
hardware sequence to be repeated.
