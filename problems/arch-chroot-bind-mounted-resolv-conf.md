# arch-chroot bind-mounts resolv.conf — so the chroot can't replace it

Found the hard way, in a VM run: `configure_system` wanted the installed
system's `/etc/resolv.conf` to be the standard symlink into systemd-resolved,
and every attempt to make that link *from inside* `arch-chroot` died with
`Device or resource busy`. The journey from there to a green badge took four
commits and tripped over three different problems wearing the same red color.

## The symptom

```
ln: failed to create symbolic link '/etc/resolv.conf': Device or resource busy
```

Same thing with `rm -f` first: `rm: cannot remove '/etc/resolv.conf': Device
or resource busy`. Splitting the `ln -sf` into `rm` + `ln` (commit `aa09665`)
changed nothing, because the problem was never the link — it was *what that
path is* while a chroot session is alive.

## Diagnose it yourself

`arch-chroot` is not a bare `chroot`: it runs `chroot_setup` and
`chroot_add_resolv_conf`, which **bind-mounts the host's resolv.conf over the
chroot's** so that DNS works inside (pacman, key refresh, anything). Look:

```bash
grep -n resolv "$(command -v arch-chroot)"     # chroot_add_resolv_conf
arch-chroot /mnt findmnt /etc/resolv.conf      # it's a mountpoint, not a file
arch-chroot /mnt rm -f /etc/resolv.conf        # EBUSY — you can't unlink a mountpoint
```

A bind-mounted file *is* a mountpoint. The kernel refuses to unlink, rename
or replace a busy mountpoint — hence EBUSY, deterministically, on every
`arch-chroot <root> ln|rm ... /etc/resolv.conf`.

## The fix

Make the link **from the host, after the last `arch-chroot` has exited** —
its bind mounts only live for the duration of each invocation. Address the
file by its host-visible path, but express the *target* as the installed
system will resolve it at boot:

```bash
rm -f "$MOUNT_ROOT/etc/resolv.conf"
ln -sf ../run/systemd/resolve/stub-resolv.conf "$MOUNT_ROOT/etc/resolv.conf" \
	|| { echo "linking resolv.conf failed" >&2; return 1; }
```

`../run/...` from `/etc` is `/run/...` in the target — the exact relative
form systemd itself ships. An absolute `/run/...` target would also resolve
correctly at boot; what must NEVER leak into the target is the
`$MOUNT_ROOT` prefix, which is only meaningful on the live host.

## Three problems, one badge color

Getting there broke CI twice, for two different reasons — worth keeping
apart, because the second one outlived the fix for the first:

1. **`5f8d91d`** moved the `ln` host-side but quoted both operands into one
   string: `ln -s "<target> <link>"`. That is `ln` with a single argument.
   shellcheck caught the real bug at a glance — **SC2226: "This ln has no
   destination"** — and run 11 went red on the lint step. (The bats suite,
   ironically, still passed: the glued string *contained* the substring the
   assertion grepped for.)
2. **`716e605`/`36092dc`** fixed the quoting and the target form. shellcheck
   went green again — and the badge stayed red, now on **bats test 19**: the
   old assertion `grep -q "stub-resolv.conf /etc/resolv.conf" "$STUB_LOG"`
   expected the link path *without* a prefix, which was only ever true while
   the command ran through `arch-chroot`. Host-side, the logged path is
   `$MOUNT_ROOT/etc/resolv.conf`, and the verbatim grep can never match
   again. The installer was correct; the assertion described code that no
   longer existed.

The repaired assertion pins the *invariant* — stub target plus link basename
— instead of the incidental full path:

```bash
grep -q "stub-resolv.conf .*/etc/resolv.conf" "$STUB_LOG"
```

## The lessons (these outlast the bug)

- Inside an `arch-chroot` session, `/etc/resolv.conf` is a **bind mount**,
  not a file. Configure it from the host, after the chroot has exited.
- Symlinks are resolved when *used*, not when created: a link written from
  the host must carry a target valid inside the installed root. Relative
  (`../run/...`) sidesteps the whole class of prefix mistakes.
- `cmd "a b"` and `cmd a b` are different programs' worth of behavior apart.
  shellcheck knew — SC2226 named the bug before any VM did.
- Stub-log assertions encode *how* a command was invoked. Move a command out
  of a stubbed wrapper (here: out of `arch-chroot`) and every STUB_LOG grep
  that mentions it must be revisited — assert on what must stay true, not on
  the path that happened to be logged.
- One red badge can be two unrelated failures back to back. Read *which step*
  failed before concluding the previous fix didn't work.
