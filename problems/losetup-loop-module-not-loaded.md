# Test suite fails at setup: cannot create a loop device

While building this repo's test suite, `losetup` refused to attach the fake
disk — on every run. This writeup is operational: each step is a command you
can run to diagnose the same failure, with the expected output. The lesson at
the end matters more than the bug.

## The symptom

The suite builds a sparse image and attaches it as a loop device. That attach
failed:

```
[OK] Root privileges confirmed
losetup: /tmp/fakedisk-big.XXXXXX: failed to set up loop device: No such file or directory
```

`No such file or directory` is misleading here — the file *is* there. The
message is ambiguous, and that ambiguity is the whole trap.

## Diagnose it yourself, step by step

**Step 1 — reproduce with a throwaway image.** Take the test suite out of the
picture and try the bare command:

```bash
truncate -s 100M /tmp/probe.img      # make a 100 MB sparse file
sudo losetup -fP --show /tmp/probe.img
#   -f  = find the first free /dev/loopN
#   -P  = scan the image for a partition table
#   --show = print the device it picked
```

If this fails with the same message, the problem is the environment, not the
suite. Good — now we isolate which part.

**Step 2 — is the loop control device there?**

```bash
ls -l /dev/loop-control      # the "give me a free loop" interface
```

If this is **missing**, `losetup` prints a *different* message
(`cannot find an unused loop device`). If it is **present** but the attach
still fails with `No such file or directory`, the problem is one layer deeper:
the `/dev/loopN` nodes themselves are not being created.

**Step 3 — is the loop module actually loaded?** This is the real question:

```bash
lsmod | grep loop            # is the loop driver in the running kernel?
sudo modprobe loop           # try to load it — DO NOT hide the error
```

If `modprobe` fails, read its message closely. In my case:

```
modprobe: FATAL: Module loop not found in directory /lib/modules/7.0.12-zen1-1-zen
```

**Step 4 — confirm the root cause.** The module is missing from the directory
of the *running* kernel:

```bash
uname -r          # kernel currently in RAM, e.g. 7.0.12-zen1-1-zen
ls /lib/modules/  # what is on disk — a NEWER version, the running one gone
```

If `uname -r` shows a version that is **not** listed in `/lib/modules/`, that
is it: the kernel was updated (`pacman -Syu`) but not rebooted. The running
kernel looks for its modules on disk; the update already replaced them with the
new version's. Same reason USB sticks stop mounting after a kernel update until
you reboot.

## The fix

```bash
reboot
```

After reboot the running kernel matches its on-disk modules, and
`sudo modprobe loop` works. The suite now loads the module itself and, crucially,
**does not silence the command that is supposed to fix things**:

```bash
modprobe loop || fail "cannot load the loop kernel module"
[[ -e /dev/loop-control ]] || fail "/dev/loop-control missing after modprobe"
```

An earlier version wrote `modprobe loop 2>/dev/null || true`. That `2>/dev/null`
swallowed the FATAL line for three runs and hid the answer in plain sight.

## The lessons (these outlast the bug)

1. **Never silence the command meant to repair state.** Hiding the output of
   the fixing step is how a one-line answer stays buried for days.
2. **An ambiguous error is resolved by reproduction, not intuition.** Two
   different causes print `No such file or directory`. The way to tell them
   apart is to reproduce each one and compare the exact wording — not to guess.
3. **Name every dependency at the door.** The suite now checks each required
   command up front, so an environment problem shows up as one clear line
   instead of a cryptic failure halfway through.
