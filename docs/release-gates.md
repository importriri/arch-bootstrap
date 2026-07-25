# Release gates

The installer is published as a pipeline, not as a promise that every laptop is
identical. A machine is added to the compatibility list only after all gates
below are recorded against exact repository commits.

## Gate 1 — static and unit verification

- `bash -n` and ShellCheck are clean.
- `bats tests/unit.bats` is green.
- `sudo bash tests/luks-header-verify.sh` verifies a real LUKS2 header.

## Gate 2 — disposable VM

Run `sudo tests/vm-pipeline-test` on an Arch-capable disposable VM. The test is
kept out of hosted CI because it needs nested virtualization, loop devices,
device mapper, partition rereads and mounts. Record the log and commit hash.

## Gate 3 — laptop clean install

For each hardware profile:

1. back up and verify the backup;
2. run the default dry-run;
3. install to the intended disk layout;
4. boot Hardened twice;
5. verify LUKS, Btrfs mounts, Secure Boot state, network and Ansible availability;
6. hand the machine to `privatestack-ansible` and complete its host validation.

A component-level fix does not equal a pipeline pass. The compatibility matrix
in `arch-hypervisor-lab` distinguishes those states explicitly.
