# Security policy

## Reporting a vulnerability

Report a vulnerability in `arch-bootstrap` privately, through GitHub's
private vulnerability reporting for this repository: the
**Report a vulnerability** button on
<https://github.com/importriri/arch-bootstrap/security/advisories>, which
opens the form at
<https://github.com/importriri/arch-bootstrap/security/advisories/new>.
A report goes to the repository's maintainer, named in
[`AUTHORS.md`](AUTHORS.md). Do not open a public issue, pull request or
discussion about it.

A flaw in the stage-2 automation, `hyperlab-ansible`, belongs to that
repository's own [security policy](https://github.com/importriri/hyperlab-ansible/blob/main/SECURITY.md).
When a flaw crosses the hand-off between the two, for example a storage
contract this repository writes and stage 2 accepts when it should not,
report it here and say so.

### When the form is not there

GitHub shows the button only after a repository administrator has enabled
private vulnerability reporting in the repository settings. This file does
not enable it, and its presence is not proof that the form works. If the
button is missing or the form does not open:

- keep every detail private: do not put it in an issue, a pull request, a
  discussion, a commit or a public paste;
- you may open a public issue that says only that you have a security report
  and asks for the private form to be enabled, with no description of the
  flaw, the affected code or how to trigger it;
- do not send the report to an address found elsewhere: this project
  publishes no security mailbox, team or encryption key.

## What to send

- what you found, in a few sentences;
- the exact commit you tested (`git rev-parse HEAD`);
- the smallest reproduction you have: the commands, the disk layout, and
  whether you ran `bash verify.sh`, the dry run (`DRY_RUN=1`, the default) or a
  real installation, and on which kind of machine (bare metal, VM, container);
- what an attacker gains, and what they must already have: physical access,
  a root shell on the live medium, write access to the EFI system partition,
  control of a package mirror, and so on.

## What never to send

- a LUKS passphrase, a key file such as `/etc/cryptsetup-keys.d/cryptvm.key`,
  Secure Boot private keys or any other secret;
- a disk image, a LUKS header dump or a copy of a whole partition;
- unredacted logs: remove host names, user names, serial numbers, MAC and IP
  addresses, disk serials and UUIDs before you paste any output.

Replace each secret with a placeholder and say that you did. A reproduction
on a throwaway VM or on the loop-device fixtures in `tests/` is always
preferable to data from a real machine.

## Scope

In scope: this repository's `bootstrap`, `installer`, `verify.sh`, the tests
and harnesses under `tests/` and `test-installer`, the CI workflow, and the
documentation where it states a security property that the code does not
deliver.

Out of scope: vulnerabilities in Arch Linux packages, `cryptsetup`, the
kernel, systemd-boot, `sbctl`, the Archiso live medium, firmware or
hardware. Report those upstream, and tell us if the way this installer uses
them makes things worse.

What the installer protects against, and what it does not, is in
[`docs/threat-model.md`](docs/threat-model.md). A report showing that the
code falls short of a protection that page claims is the most useful kind.
A limit that page already states (for example that the initramfs is not
signed) is known; a report is still welcome when it shows a concrete
attack the page does not describe.

## Supported versions

There is no release yet. Only the latest commit on `main` is supported;
reproduce on it before you report.
