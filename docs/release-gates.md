# Release gates

The bootstrap is released as one exact pipeline, not as a generic claim that
every laptop is identical. Compatibility is recorded only against exact
commits and sanitized hardware evidence.

## Current hardware state

- Nitro 5: bootstrap-to-stage-2 host path passed.
- Nitro frozen clean-install release evidence: pending.
- Predator clean-install and portability evidence: pending.
- Refusal of a storage contract that cannot be written: software-verified only.
  No installation has run this writer yet; the frozen clean installation in
  gate 3 is its first hardware proof and is pending.

## Gate 1: software verification

Hosted CI and local verification execute the same command:

```bash
bash verify.sh
```

It runs as a normal user and never calls sudo.

It must pass Bash syntax, ShellCheck, all Bats contracts and real LUKS2 header
inspection. The repository-proof gate runs this entrypoint from the exact checkout and
records only the combined verification hash, clean-worktree state and commit
identity.

To also compare storage with an explicit stage-2 checkout, run:

```bash
HYPERLAB_ANSIBLE_REPO=/path/to/hyperlab-ansible \
  CROSS_REPO_STORAGE_REQUIRED=1 bash verify.sh
```

This runs the actual bootstrap writer for both topologies in temporary fixtures,
then passes each file to that checkout's `tools/bootstrap_storage_guard.py`
validate CLI with independent synthetic `findmnt` JSON. Only the guard's existing
fixture ownership exception is enabled; regular-file, mode and value checks
remain active. The complete `allowed_storage_topologies` mapping in the actual
`release/acceptance.v2.yml` must equal the successful guard results projected onto
mapper, filesystem root and subvolume. Both compared Git revisions are logged.
The explicitly selected checkout root is resolved before reading its inputs;
redirected files or directories within it are refused. Python bytecode writes
are disabled for consumer execution.

Without a sibling request, standalone verification visibly reports
`SKIPPED - nothing cross-repository was proved`. Required mode without a sibling,
an explicit empty/missing path, missing or malformed inputs, a consumer refusal,
or manifest disagreement fails verification. Tests never fetch a repository.

CI retains the full standalone job and adds a required storage job on pushes
and pull requests, checking out the producer and `hyperlab-ansible` `main` into
separate directories and running the same verifier with both variables set.
Those revisions are integration inputs, not a frozen release pair. This proves
only storage agreement with the v2 manifest; it does not qualify its gate list
as v1 or prove encryption, NOCOW, keyfile unlocking or an installed mount.
The disposable installation and both physical gates below remain pending.

### A failed storage hand-off

If `/etc/privatestack/bootstrap-storage.yml` cannot be created, opened or
completely written on the target, `bootstrap` stops with
`Could not write the bootstrap storage contract` and a nonzero exit. It prints
neither `[OK] stage-2 storage contract written` nor
`[OK] arch-bootstrap complete`, and its exit cleanup unmounts the layout this
run mounted, newest first, then closes `cryptvm` (two disks) and `cryptroot`.
Nothing it did not open is touched. Directory, ownership and mode failures stop
it the same way, each with its own message.

There is no rollback and no atomic replacement: an interrupted write can leave a
partial contract on the target root filesystem, and no claim is made about a
power loss. A run that does not end with `[OK] arch-bootstrap complete` is a
failed installation, whatever file it left. `tests/bootstrap-contract.bats`
proves this for both topologies through the real writer and the real entrypoint
with stubbed storage commands; it is not a hardware observation.

## Gate 2: disposable two-disk VM

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

## Gate 3: Nitro clean installation

1. verify an external backup;
2. boot the reviewed Archiso in 64-bit UEFI mode;
3. run `sudo bash bootstrap` and retain the dry-run log locally;
4. run `sudo env DRY_RUN=0 bash bootstrap` against the intended disk layout;
5. complete Secure Boot enrollment;
6. boot `linux-hardened` twice;
7. verify LUKS2, Btrfs mounts, `+C`, fstab, crypttab, keyfile mode, networking and
   the stage-2 contract (step 4 must have ended with `[OK] arch-bootstrap
   complete`; the contract is a regular root:root 0644 file that parses and that
   the stage-2 guard accepts);
8. run the exact selected `hyperlab-ansible` host campaign;
9. record sanitized scalar evidence through the hardware runner.

The Nitro PCIe power-management workaround remains part of the managed VFIO
profile. It was isolated on Nitro before being reused on Predator; routine
release testing does not deliberately remove it and reintroduce a hard freeze.

## Gate 4: Predator portability installation

Predator must use the exact bootstrap and Ansible commits that passed Nitro.
Before a real write, confirm the menu identifies the intended primary and
dedicated VM disks and removes the primary disk from the second selection.

Repeat the Nitro sequence and additionally prove:

- the observed VM mount source and filesystem root match the declared topology;
- all HyperLab state below `/var/lib/libvirt/images/hyperlab` is physically on
  the dedicated encrypted disk;
- reboot unlocks `cryptroot`, then keyfile-unlocks and mounts `cryptvm` without a
  second passphrase;
- absence or drift of the storage contract stops Ansible before VM-state writes;
- the Nitro-derived `pcie_port_pm=off` fix remains effective on the RTX 3070
  profile.

## Licences and redistribution

[`third-party-licences.md`](third-party-licences.md) records the origin of
every tracked file and the licence of every package the installer fetches.
Installing from the Arch mirrors redistributes nothing; an image that carries
those packages does. These prerequisites are unresolved, and nothing they
cover is approved for bundling:

- U1: the exact package closure an image installs is not inventoried;
- U2: the `linux-firmware` split packages carry per-vendor licence files that
  are not reviewed, and ten `WHENCE` entries have no visible source;
- U3: `intel-ucode`: whether its early-load image is redistribution "without
  modification";
- U4: `amd-ucode`: its third-party technology clause and export
  certification;
- U5: how an image offers the corresponding source of its GPL and LGPL
  packages;
- U6: the `base` record names `GPL` without a version;
- U7: licences of what is compiled into `sbctl` and `zram-generator` and of
  the collections bundled in `ansible`;
- U8: whether the Arch `vim` build counts as unmodified under the Vim licence;
- U9: the live-medium tools an installer image would carry.

## Proposed: installer image qualification

[`adr/0001-iso-build-and-distribution.md`](adr/0001-iso-build-and-distribution.md)
proposes an installer image built from an archiso profile in this
repository. It is not accepted and nothing of it is built: no profile,
image, signature or key exists, and gates 1 to 4 above keep their meaning
and their pending status. Gate 3 still boots the reviewed upstream Archiso
until an image passes the steps below.

An image would qualify in this order, each step only after the previous one:

1. static validation of the profile, its admission list and its pinned
   inputs, in `bash verify.sh`;
2. a real build in an isolated builder, never on the operator's host;
3. two clean builds compared by the SHA-256 of the image and of the package
   manifest; a mismatch fails and is explained, and the build stays
   development-only;
4. a UEFI VM boot (OVMF, no host disk) reaching the live prompt, with no
   unexpected disk write, and refusal tests for a bad signature, a bad hash
   and a missing input;
5. a physical boot on Nitro, then on Predator with the same image, without
   installing; it does not replace gates 3 and 4.

A distributed image also needs everything it embeds admitted under the
ADR's payload rule, every package of the resolved closure at its exact
version, dependencies included (today only this repository's own files meet
the rule's evidence conditions, and nothing is admitted yet), and a detached
signature over `SHA256SUMS` by a key whose fingerprint the user obtains
through an independent channel. An unsigned build is a development
build, whatever it contains. Steps 1 to 5 are pending.

## Evidence and publication rule

A component fix, hosted green CI or one successful laptop does not authorize
publication of a runtime change by itself. The hardware campaign receipt must
bind:

```text
exact arch-bootstrap commit
exact hyperlab-ansible commit
disposable two-disk proof
Nitro ordered gate result
Predator ordered gate result
sanitized publication hash
```

Software-verified integration changes may be committed and pushed directly to
`main`; that alone is not a hardware compatibility claim. A release campaign
freezes an exact public `arch-bootstrap` commit together with an exact public
`hyperlab-ansible` commit and binds all hardware evidence to that pair. Once the
campaign is frozen, any runtime change creates a new commit identity and reopens
the affected hardware sequence. Documentation-only updates may continue when they
do not alter the frozen runtime behavior or the meaning of already-recorded
evidence.
