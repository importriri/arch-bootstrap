# Contributing

`arch-bootstrap` erases disks. Every change is reviewed for what it can
destroy before what it adds, and every behaviour it claims is backed by a
test. This page says how to get a change in.

Security problems are not contributions: report them privately as
[`SECURITY.md`](SECURITY.md) says, never in an issue or a pull request.

## Repository map

| Path | What it is |
|---|---|
| `bootstrap` | The public entrypoint: runs `installer`, verifies the mounted VM store and writes the stage-2 storage contract |
| `installer` | The engine, sourceable function by function for the tests; run directly it skips the hand-off |
| `verify.sh` | The whole software battery, the same one CI runs |
| `tests/unit.bats`, `tests/bootstrap-contract.bats` | Bats contracts, run against stubbed tools in `tests/stubs/` |
| `tests/luks-header-verify.sh` | Real LUKS2 header checks on a sparse file in `/tmp`, no root needed |
| `tests/vm-pipeline-test` | The destructive two-disk gate: throwaway VM only, see below |
| `test-installer` | A narrower destructive loop-device partitioning harness: throwaway VM only |
| `docs/release-gates.md` | The release procedure and the hardware gates |
| `docs/threat-model.md` | What the installer protects, what it trusts, and what it does not do |
| `docs/third-party-licences.md`, `docs/file-inventory.tsv` | File origins and the licences of what the installer fetches |
| `docs/adr/` | Proposed and accepted decisions |
| `problems/` | Write-ups of failures that changed the code or its checks, indexed in `problems/README.md` |
| `.github/workflows/ci.yml` | CI: the standalone battery and the required storage comparison |

## Set up

`verify.sh` needs `bash`, `shellcheck`, `bats`, `cryptsetup`, `python3`,
`git` and PyYAML, and stops with "missing verification dependency" when one
is absent. On Arch Linux:

```bash
# Install the verification toolchain (Arch package names).
sudo pacman -S --needed bash shellcheck bats cryptsetup python python-yaml git
```

On Debian or Ubuntu, CI installs the same toolchain with the command
below; the runner already has `git` and `python3`:

```bash
# Install the verification toolchain (the packages CI uses).
sudo apt-get install shellcheck bats cryptsetup-bin python3-yaml
```

## Verify

Run the battery from the repository root as your normal user:

```bash
# Syntax, ShellCheck, every Bats contract and the real LUKS2 header check.
bash verify.sh
```

Nothing in it needs root or calls `sudo`, and it touches no block device.
It must end with `arch-bootstrap verification: PASS`. Do not run it with
`sudo`.

Alone, it reports that the cross-repository storage comparison was skipped
and that nothing cross-repository was proved. When a change touches the
storage contract, also run the comparison against a checkout of
[`hyperlab-ansible`](https://github.com/importriri/hyperlab-ansible), as
the required CI job does:

```bash
# Compare the storage contract with stage 2's own guard and manifest.
HYPERLAB_ANSIBLE_REPO=/path/to/hyperlab-ansible \
  CROSS_REPO_STORAGE_REQUIRED=1 bash verify.sh
```

It reads that checkout and never fetches or changes it;
[`docs/release-gates.md`](docs/release-gates.md) says exactly what it
compares.

### The destructive gates

`tests/vm-pipeline-test` and `test-installer` partition, encrypt, format
and mount real loop devices as root. Run them only inside a disposable Arch
Linux VM with device-mapper, udev and mount support, never on your
installed workstation or on any machine whose disks you care about:

```bash
# Inside a throwaway Arch VM only: the two-loop-device storage gate.
sudo VM_TEST=1 bash tests/vm-pipeline-test
```

The same goes for trying `bootstrap` itself: use a VM with blank virtual
disks. [`problems/testing-without-udev-or-device-mapper.md`](problems/testing-without-udev-or-device-mapper.md)
explains why a container is not enough.

## Make a change

- **Small and reviewable.** One concern per pull request and per commit,
  each commit keeping `bash verify.sh` green.
- **Test first.** Add or change the contract, see it fail for the right
  reason, then change the code. Prefer tests that run the real functions
  against the stubbed tools over tests that search for text.
- **Fail closed.** A missing, unreadable or unexpected input stops the run
  with a message; it never becomes a default. Every command that matters is
  checked (`|| { echo "..." >&2; return 1; }`), because `set -e` does not
  reach inside functions called from `if` or `||`.
- **The dry run stays harmless.** A new step writes nothing under
  `DRY_RUN=1` and says what a real run would do.
- **Keep the documents true.** A change of behaviour updates the README,
  `docs/release-gates.md` or `docs/threat-model.md` in the same commit. Do
  not claim a protection the code and its tests do not deliver.
- **Write it up.** A failure that taught something gets a note in
  `problems/`, in the shape of the existing ones (what was wrong, the
  unsafe assumption, the fix, the test that now catches it), and a line in
  `problems/README.md`.
- **Commit messages** follow the history: an imperative subject with a
  capital first letter, no type prefix, no final period, at most 72
  characters; the body says why.

Open a pull request against `main`. Nothing in this repository pushes, tags
or publishes on anyone's behalf; CI only runs `bash verify.sh`.

## Rights and notices

The repository is published under the [MIT licence](LICENSE). By
contributing you confirm that you have the right to submit your work under
it. There is no contributor licence agreement and no sign-off line.

If any part of a change comes from somewhere else (code, text, a test
fixture, a configuration snippet), say so in the pull request and in the
commit message: its source, the revision you took it from and its licence.
Keep every copyright line and licence notice that came with it. A change
whose origin or licence cannot be stated is not accepted.
[`docs/third-party-licences.md`](docs/third-party-licences.md) records the
origin of every tracked file at one commit; third-party material a
contribution brings in must be recorded there too.

## Hardware claims

A green `verify.sh` is software evidence, not a hardware result. Do not add
"works on this laptop" to this repository. Hardware compatibility is
recorded, sanitized, through the separate process in
[`arch-hypervisor-lab`](https://github.com/importriri/arch-hypervisor-lab/blob/main/hardware/README.md),
against exact commits, and only after the gates in
[`docs/release-gates.md`](docs/release-gates.md) pass.
