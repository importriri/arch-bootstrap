# The bug that never shipped: a trailing newline in the LUKS passphrase

Caught during the design review of `encrypt_root`, before a single byte hit a
disk. It would have produced the worst possible failure mode: an installer
that *works*, an encrypted system that *boots to the passphrase prompt* — and
a passphrase that never matches. Locked out of your own disk, with no error
anywhere in between.

## The symptom (the one that never happened)

`sd-encrypt` asks for the passphrase at boot. You type exactly what you typed
during the install. `Invalid passphrase, please retry.` Forever.

## Diagnose it yourself, step by step

`cryptsetup --key-file -` reads the key from stdin **byte for byte**. It does
not strip anything. The interactive prompt at boot, on the other hand, gives
cryptsetup the line *without* the terminating newline. So the question is:
does your script feed the passphrase with or without a trailing `\n`?

Bash gives you both, one keystroke apart:

```bash
printf '%s' "$pass"     # exactly the bytes of $pass — nothing appended
echo "$pass"            # appends \n
cmd <<< "$pass"         # here-string: also appends \n
```

Prove it on a real header, no device-mapper needed (`luksFormat` and
`luksAddKey` work on a plain sparse file):

```bash
f=$(mktemp); truncate -s 32M "$f"
FAST=(--pbkdf argon2id --pbkdf-force-iterations 4 --pbkdf-memory 32 --batch-mode)

# format the container feeding the secret with printf — NO newline
printf 'correct horse' | cryptsetup luksFormat --type luks2 "${FAST[@]}" --key-file - "$f"

# same secret, same way: authenticates (adds a second keyslot)
printf 'correct horse' | cryptsetup luksAddKey "${FAST[@]}" --key-file - "$f" <(printf 'second')
echo $?      # 0

# same secret WITH a trailing newline: rejected
cryptsetup luksAddKey "${FAST[@]}" --key-file <(printf 'correct horse\n') "$f" <(printf 'third')
# No key available with this passphrase.
echo $?      # 2
```

Same twelve characters. One invisible byte of difference. Exit 2.

## The fix

One rule, enforced in one place: the secret only ever leaves
`read_passphrase` via `printf '%s'` — never `echo`, never a here-string. The
comment sits right on the line, because this is exactly the kind of thing a
future refactor "simplifies" back into a lockout:

```bash
#printf '%s' — deliberately NO trailing newline. cryptsetup reads a key file
#byte for byte; a newline baked in here would NOT match the interactive prompt
#sd-encrypt shows at boot, and would lock the user out of their own disk.
printf '%s' "$pass1"
```

And it stays proven, not just commented: `tests/luks-header-verify.sh`
formats a real header and asserts both directions — the `printf`-fed secret
must authenticate, the newline-fed one must be rejected. If anyone ever
breaks the rule, CI turns red before a disk turns into a brick.

## The lessons (these outlast the bug)

- `--key-file -` means *raw bytes*. The interactive prompt means *line minus
  newline*. Any script that feeds the same secret through both paths must
  strip the newline itself.
- `<<<` and `echo` are not "basically printf". The appended `\n` is real data
  to anything that reads bytes.
- A dry-run can't test everything, but it *can* test this: `encrypt_root`
  acquires and confirms the passphrase even with `DRY_RUN=1`, because the
  match logic is the one thing worth proving before `luksFormat` gets slow
  and irreversible.
- The cheapest place to catch a lockout is a 32 MiB sparse file.
