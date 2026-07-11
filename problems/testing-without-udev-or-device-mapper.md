# Testing disk plumbing where there is no kernel to talk to

The unit suite, the LUKS header check and the VM pipeline test were all built
inside a rootful container. Good news: most of it runs there. Bad news: the
container lies about what works, and it lies in layers.

## The symptoms (all real, all from the same afternoon)

- `/dev/mapper/control` **exists**, yet `cryptsetup open` dies with
  `Cannot initialize device-mapper. Is dm_mod kernel module loaded?` —
  the node is there, the kernel side is not.
- `sgdisk` happily **writes a real GPT** to a loop device… and
  `/dev/disk/by-partlabel/*` never appears: no udevd, no symlinks.
- `partprobe`, `udevadm`, `modprobe`: **binaries missing** until installed —
  and installing `udevadm` doesn't resurrect the daemon it needs.
- The original `test-installer` refused correctly at every step:
  `[FAIL] missing command: udevadm` (exit 1), then — with the binary
  installed — `[FAIL] cannot load the loop kernel module` (exit 1).
  The suite was right both times.

## The bug I almost filed against my own suite

First measurement said `test-installer` exits **0** after a `[FAIL]`. It
doesn't. The harness did this:

```bash
./test-installer | tail -12; echo "exit: $?"     # $? is tail's, not the suite's
```

`$?` after a pipe belongs to the **last** command. The suite exited 1 all
along. Re-measured without the pipe (or with `"${PIPESTATUS[0]}"`), the
"bug" evaporated. Verify the verifier before blaming it.

## The fix: a ladder, and gates that say why

Tests are split by what they actually need from the machine:

| Layer | Needs | Runs |
|---|---|---|
| `shellcheck` + `bats tests/unit.bats` | nothing (stubs) | anywhere, CI |
| `tests/luks-header-verify.sh` | a sparse **file** — `luksFormat`/`luksDump`/`luksAddKey` never touch device-mapper | anywhere with cryptsetup, CI |
| `tests/vm-pipeline-test` + `test-installer` | a real kernel: dm, udevd, loop | a VM, nothing less |

And the VM layer probes for the truth, not for the decoration:

```bash
[[ -e /dev/mapper/control ]]   # necessary, NOT sufficient (the node can be dead)
[[ -S /run/udev/control ]]     # the real tell: is udevd actually listening?
```

Fail closed, loudly: outside a VM the pipeline prints
`[SKIP] udevd not running (container?) — by-partlabel symlinks won't appear`
and exits 0 as a *skip*, never as a fake pass.

## The lessons (these outlast the bug)

- A device node is a promise, not a capability. Probe the behaviour
  (`cryptsetup open` on a scratch file), not the filesystem decoration.
- The most useful thing a test can do in the wrong environment is refuse
  with the reason. Gates are documentation that executes.
- `luksFormat` on a plain file needs no kernel help — which makes a 32 MiB
  sparse file the cheapest real-cryptography test bench there is.
- After a pipe, `$?` is not your program's exit code.
