# ADR 0001 - An installer image: how it is built, what it carries, how it is verified

Status: Proposed

Nothing in this record is built. No profile, build script, image, signature
or key exists; every path under `iso/` below is a proposed new file. The
operator accepts or rejects the decision; the name, the signing key, its
custodian and the download host stay the operator's to choose.

## Context

Today the pipeline starts from the upstream Arch Linux live medium: the
operator boots it, clones this repository and runs `bootstrap`, which runs
the `installer` engine, verifies the mounted VM store and writes the stage-2
storage contract. The installed host then clones
[`hyperlab-ansible`](https://github.com/importriri/hyperlab-ansible) and
runs stage 2. The intended main distribution is one bootable image; Ansible
from the upstream medium stays the second way.

What the existing code already fixes, and an image must keep:

- `DRY_RUN=1` is the default of `installer`; a real run needs `DRY_RUN=0`;
- every selected disk is confirmed by retyping its full path
  (`confirm_wipe`), and the disk holding `/run/archiso/bootmnt` is refused;
- `check_uefi` refuses a machine not booted in UEFI mode or whose
  `fw_platform_size` is not `64`;
- `check_network` refuses without a reply from `archlinux.org`;
- `pacstrap_base` refreshes `archlinux-keyring` on the live medium and
  installs `PACSTRAP_PACKAGES` from the mirrors; `encrypt_root` upgrades
  `cryptsetup` on the live medium only when it does not list `argon2id`;
- `bootstrap` writes `/etc/privatestack/bootstrap-storage.yml` only after
  the storage post-conditions pass; stage 2 checks it independently
  (hyperlab-ansible ADR 0013).

[`../third-party-licences.md`](../third-party-licences.md) separates three
questions: this repository's files (MIT, origin documented), what the
installer fetches (redistributes nothing), and what an image would carry,
which *is* a redistribution. It leaves nine prerequisites open, U1 to U9.
None of them is approved for bundling.

Upstream inputs read for this record:

- archiso at tag `v91`, commit `723da192226e1c9d5def9168f13332793c82a85e`
  (<https://gitlab.archlinux.org/archlinux/archiso>, changelog entry
  2026-09-27): `README.rst`, `docs/README.profile.rst`, `archiso/mkarchiso`,
  `scripts/run_archiso.sh` and the `configs/releng` profile. The matching
  Arch package is `archiso` 91-1 (`extra`, `GPL-3.0-or-later`).
- The Arch Linux trademark policy, version 2021-04-18
  (<https://terms.archlinux.org/docs/trademark-policy/>, read in full on
  2026-10-26; its source is `content/docs/trademark-policy.adoc` in
  <https://gitlab.archlinux.org/archlinux/service-agreements> at commit
  `4afc727f6d33f2311e838e50a07691eb2051a677`).

## Options

**A. An archiso profile in this repository (recommended).** The live medium
is the stage-1 environment: it runs the destructive disk work this
repository owns. The image embeds this repository at one exact commit, so
the profile, the bootstrap it carries and the tests that check both move in
one commit and one review. It needs no new cross-repository pin beyond the
stage-2 revision the image names.

**B. A separate image repository.** It would have to pin this repository and
`hyperlab-ansible`, adding a third identity to every release freeze and a
second place where the stage-1 payload is decided. Rejected: more pins, no
gain in separation, since the image can only carry what this repository
already owns.

**C. The image in `hyperlab-ansible`.** Stage 2 would carry stage 1, against
the ownership boundary of ADR 0013 (stage 1 owns disks, encryption and
mounts; stage 2 owns the HyperLab tree). Rejected.

**D. No image: keep only the upstream medium.** This is the current path and
stays documented as the second way. Rejected as the main way only because
the operator wants one artefact whose payload and inputs are pinned.

## Recommendation

Option A. The rest of this record is its design.

### Ownership

| Repository | Owns in the image design |
| --- | --- |
| `arch-bootstrap` | the profile, the build, the live payload, the embedded bootstrap, the release records and their verification |
| `hyperlab-ansible` | stage 2, unchanged; the image names one exact commit of it and carries none of its files |
| `arch-hypervisor-lab` | sanitized evidence of the VM and physical boots; no build input |

The image never copies stage-2 roles, playbooks, themes or assets into a
second installer. Embedding a stage-2 tree would also embed files whose
provenance is open (see [payload admission](#payload-admission)); it is not
a way around the rule.

### Proposed new files

None of these exists. The implementation unit creates them.

```text
iso/README.md                 build, compare and verify instructions
iso/build-inputs.yml          pinned inputs: archiso version, archive date,
                              stage-2 repository and commit, build mode
iso/admission.yml             one entry per live-payload package: decision
                              and the audit entry it rests on
iso/build                     refuses unpinned or dirty input, runs mkarchiso,
                              writes the build records
iso/compare                   compares two build records and their images
iso/sign-release              signs SHA256SUMS; refuses anything not eligible
iso/verify-download           user-side check of signature, fingerprint, digest
iso/profile/LICENSE           GPL-3.0-or-later text, for the profile only
iso/profile/ORIGIN.tsv        origin of every profile file
iso/profile/profiledef.sh
iso/profile/packages.x86_64
iso/profile/pacman.conf
iso/profile/efiboot/loader/loader.conf
iso/profile/efiboot/loader/entries/01-live.conf
iso/profile/airootfs/...      motd, hostname, locale, mkinitcpio and pacman
                              hook overlays derived from releng
tests/iso-profile.bats        static validation of the profile
tests/iso-release.bats        refusal tests: records, signing, verification
```

`verify.sh` and the CI workflow would gain the tools these tests need
(`gpg`); that is part of the implementation, not of this record.

### Profile licence, tracked apart from MIT

archiso is `GPL-3.0-or-later` (its `README.rst`, "License"). In the `releng`
profile at `v91`, three files carry an `SPDX-License-Identifier:
GPL-3.0-or-later` header (`choose-mirror`, `livecd-sound`,
`Installation_guide` under `airootfs/usr/local/bin/`); the others carry none,
so the repository licence applies to them. Every file copied or adapted from
`releng` is therefore treated as `GPL-3.0-or-later`. `iso/profile/` carries
that licence text in
its own `LICENSE`, and `iso/profile/ORIGIN.tsv` records each file's origin:
the `releng` path and the SHA-256 of the file at `v91`, or `written here`.
The root MIT `LICENSE` keeps covering everything outside `iso/profile/`.
The `mkarchiso` tool runs only on the builder and is not shipped; the
`mkinitcpio-archiso` hooks it relies on are an ordinary package of the live
payload and follow the admission rule.

### What the profile keeps, drops and changes from `releng`

- **Boot modes:** `bootmodes=('uefi.systemd-boot')` only. No
  `bios.syslinux`, so no `syslinux/` directory and no `splash.png`; no
  `uefi.grub`. archiso adds IA32 mixed-mode booting for systemd-boot on
  x86_64; `check_uefi` already refuses such a machine, because its
  `fw_platform_size` is not `64`. Supported: x86_64 with 64-bit UEFI.
- **Nothing runs by itself:** dropped `airootfs/root/.automated_script.sh`
  and its call in `.zlogin` (it fetches and executes a `script=` URL from
  the kernel command line), `cloud-init` (it reads user data from an
  attached medium), `etc/ssh/sshd_config.d/10-archiso.conf` and `openssh`
  (root login by password), `livecd-talk`, `livecd-alsa-unmuter`,
  `choose-mirror` and `reflector`. Kept: the tty1 autologin to a root
  shell, `pacman-init.service` (the live keyring) and the networkd and
  resolved configuration.
- **Branding:** every `releng` text naming Arch Linux as the medium's
  identity is replaced: `iso_name`, `iso_label`, `iso_publisher`,
  `iso_application`, `install_dir`, the boot entry title and `motd`
  (see [naming](#naming-and-trademarks)). `/run/archiso/bootmnt` stays: it
  is the mount point of the `mkinitcpio-archiso` hooks that `confirm_wipe`
  reads.
- **Kept upstream behaviour:** the `archiso` initramfs hooks without the
  PXE hooks, `squashfs` root image, `xz` compression and `pacman-mirrorlist`
  with releng's hook that uncomments its entries at build time.

### Live payload

`iso/profile/packages.x86_64` lists exactly what the live medium needs to
run `bootstrap` and to recover a host:

```text
base linux mkinitcpio mkinitcpio-archiso
arch-install-scripts gptfdisk parted
cryptsetup btrfs-progs dosfstools e2fsprogs
iwd
```

`gptfdisk` gives `sgdisk`, `parted` gives `partprobe`, `e2fsprogs` gives
`chattr` and `lsattr`, `arch-install-scripts` gives `pacstrap`, `genfstab`
and `arch-chroot`; `base` brings `systemd`, `util-linux`, `iputils`,
`pacman` and `archlinux-keyring`. The live kernel is `linux`, as on the
upstream medium the installer was tested from; `linux-hardened` is the
target's kernel and is fetched at install time. No firmware and no
microcode are on the live payload (see [admission](#payload-admission)), so
the first image targets machines whose network works without loadable
firmware (and VMs). Adding a reviewed firmware subset is a separate
admission decision. The payload carries no editor, no `sudo` and no
accessibility entry; these are deliberate omissions to keep the
redistributed set small.

### What is embedded, what is fetched, and how each is authenticated

| Item | Where it comes from | Authenticated by |
| --- | --- | --- |
| live packages | embedded at build time from the Arch Linux Archive snapshot | package signatures, required (`SigLevel = Required`), checked against the `archlinux-keyring` of the same snapshot; digests in the package manifest |
| this repository at commit `C` | embedded: `git archive C` under `/root/arch-bootstrap/` | the release signature over `SHA256SUMS`, which covers the image; `C` is in the build record |
| stage-2 pin | embedded: `/usr/local/share/hyperlab-installer/release.json` with `C`, the stage-2 repository URL and its 40-character commit `S`, the archive date, `SOURCE_DATE_EPOCH` and the build mode | the same release signature |
| `archlinux-keyring` refresh on the live medium | fetched by `pacstrap_base` from the mirrors | its package signature, against the image's keyring |
| target packages (`PACSTRAP_PACKAGES` and their closure) | fetched by `pacstrap` from the current mirrors | package signatures against the refreshed keyring, as today |
| live `cryptsetup` upgrade | not expected: the build refuses a live `cryptsetup` that does not list `argon2id` | — |
| `hyperlab-ansible` | fetched on the installed host with `git clone` over HTTPS, then `git checkout --detach S` | TLS to the host, then `git rev-parse HEAD` must equal `S`; Git object identity is SHA-1 with collision detection, a stated limit |
| Ansible collections | fetched by stage 2 as today | stage 2's own concern, unchanged |

The image pins its own build inputs, not the install: the target is
installed from the current mirrors, exactly as on the second way, so both
ways produce the same kind of host and a fresh install is not frozen to an
old snapshot. An offline install is out of scope: it would embed the whole
target payload, firmware and microcode included, which U2 to U4 block.

`release.json` is a JSON object the tests read with a parser. A release
image names a pair (`C`, `S`) that is a frozen pair of the release campaign
of hyperlab-ansible ADR 0013; recording the image digest in that campaign
is a stage-2 change and is not decided here. The storage contract is
unchanged and carries no image data.

### Install sequence

1. The firmware boots the medium in 64-bit UEFI mode; systemd-boot shows one
   entry, titled with the working name and the build mode.
2. The live system reaches a root shell on tty1. `motd` prints the build
   mode, `C`, `S` and the two commands below. No service, script or hook
   starts the installer, opens a disk or writes one.
3. The operator connects: wired DHCP through systemd-networkd, Wi-Fi with
   `iwctl`.
4. `bash /root/arch-bootstrap/bootstrap` runs the dry run (the live shell is
   already root, so no `sudo`). The disk confirmation, the passphrase prompts
   and the refusals are the ones of this repository, unchanged.
5. `env DRY_RUN=0 bash /root/arch-bootstrap/bootstrap` runs the real
   installation, which ends with `[OK] arch-bootstrap complete` or is a
   failed installation, as documented in
   [`../release-gates.md`](../release-gates.md).
6. Reboot, manual Secure Boot enrollment, first boot as in the
   [README](../../README.md), with `git checkout --detach S` after the
   clone. `S` is in `release.json` on the medium and in the signed release
   records, so it is still available after the medium is removed.

### Recovery

The medium is read-only and is also the recovery environment: it carries
`cryptsetup`, `btrfs-progs`, `dosfstools`, `e2fsprogs` and
`arch-install-scripts`, so a host can be opened by its partlabels
(`ARCH_ROOT`, `ARCH_ESP`, `ARCH_VM`), mounted and entered with
`arch-chroot`. A failed `bootstrap` run is retried from a fresh boot of the
same medium; its exit cleanup and its refusal of a busy `/mnt`,
`cryptroot` or `cryptvm` are unchanged.

### The second way

Booting the upstream Arch Linux medium, cloning this repository and running `bootstrap`, then stage 2, stays documented in the
README. It needs no image, no signature and no admission decision, because
it redistributes nothing.

## Payload admission

**Rule.** A component may be embedded in an image that is distributed only
when all of these hold:

1. the audit names its licence or licences and where every licence and
   notice text it requires is found;
2. those terms permit redistribution in the form the image carries;
3. its notices travel with the image, on the medium and in the notices
   artefact;
4. where its licence requires source, the source arrangement for the exact
   build exists;
5. the operator accepted the entry in `iso/admission.yml`.

Anything else is excluded. `unknown`, `blocked pending evidence` and
`source delivery undecided` never default to admitted. Being already
published in a repository, carrying the repository's MIT licence, or having
stripped metadata is not evidence of provenance. A development build that is
never distributed may contain components that are not admitted; it is
labelled as such and cannot become a release (see
[signing](#artefacts-signing-and-verification)).

**Applied to the dispositions of
[`../third-party-licences.md`](../third-party-licences.md):**

| Component | On the live image | Today |
| --- | --- | --- |
| this repository's files (`bootstrap`, `installer`, `LICENSE`, ...) | yes | documented, MIT (section 1): meets conditions 1 to 4, the only component that does; condition 5 waits for `iso/admission.yml` |
| profile files derived from `releng` | yes | `GPL-3.0-or-later`, tracked in `iso/profile/`; pending `ORIGIN.tsv` and the source arrangement (U5) |
| `base` and its closure | yes | blocked: the closure is not inventoried (U1), source delivery undecided (U5), record licence without a version (U6) |
| `cryptsetup`, `btrfs-progs`, `dosfstools`, `iwd`, `archlinux-keyring` | yes | documented conditions, source delivery undecided (U5) |
| `linux`, `mkinitcpio`, `mkinitcpio-archiso`, `arch-install-scripts`, `gptfdisk`, `parted`, `e2fsprogs` | yes | not in the audit: the live payload is not inventoried (U9) |
| `linux-firmware` and its split packages | no | blocked (U2); a reviewed subset needs its own admission |
| `intel-ucode`, `amd-ucode` | no | not needed to boot the medium; the target fetches them from the mirrors, so U3 and U4 do not apply to the image |
| `linux-hardened`, `sbctl`, `zram-generator`, `git`, `ansible`, `sudo`, `vim` | no | target only, fetched at install time; the image redistributes none of them |
| NVIDIA components | no | nothing NVIDIA is on the live image: no driver, no `nvidia-utils`, no `linux-firmware-nvidia`. Stage 2 installs `nvidia-open-dkms`, `nvidia-utils`, `nvidia-settings` and related packages inside guests, from the Arch repositories, on the user's machine |
| Looking Glass | no | stage 2 builds it from source at a pinned commit on the user's host and guests; never embedded |
| fonts | only what the package closure carries (console fonts of `kbd`, part of U1) | no font package is added; stage 2 installs its desktop fonts from the repositories |
| themes, wallpapers, icons | none | the profile adds no artwork and drops `splash.png`; stage-2 assets stay in `hyperlab-ansible` |

The 22 PNG files of `hyperlab-ansible` under
`themes/assets/hyperlab-symbols-v1/images/` (10) and
`themes/assets/hyperlab-trust-v2/images/` (12) are excluded from any image
until their provenance is resolved. They are not on the live payload, and
the image never embeds a stage-2 tree that would carry them.

Consequence: today no image can be distributed. Every build is a development
build until U1, U5, U6 and U9 are settled for the live payload and each entry
of `iso/admission.yml` is accepted.

## Reproducibility

**Pinned inputs**, all in `iso/build-inputs.yml` and copied into the build
record:

- archiso: the `archiso` package of the snapshot, whose version must equal
  the pin (91-1 for tag `v91`, commit
  `723da192226e1c9d5def9168f13332793c82a85e`); a different version refuses;
- packages: one Arch Linux Archive date. The build `pacman.conf` points every
  repository at `https://archive.archlinux.org/repos/YYYY/MM/DD/$repo/os/$arch`
  for that date and nothing else. For the snapshot checked (2026/10/25, on
  2026-10-26) the archive serves `core.db` without a `.sig`, so the database
  is not signed: authenticity rests on the required package signatures and
  on the package digests the manifest records;
- keyring: the builder's `archlinux-keyring` is the one of the same
  snapshot, recorded by version and digest;
- source: this repository at a clean commit `C`; a dirty tree or an
  untracked file refuses, in development mode too;
- stage 2: `S`, 40 hexadecimal characters; a branch name or short id refuses;
- `SOURCE_DATE_EPOCH`: the commit time of `C` (`git log -1 --format=%ct C`),
  never the wall clock;
- environment: `LC_ALL=C.UTF-8`, `TZ=UTC`, `umask 022`; the live image keeps
  `LANG=C.UTF-8` and no time zone.

**Recorded closure.** Besides archiso's own `pkglist.x86_64.txt`, the build
writes a package manifest: one row per installed package with name, version,
package file name and the SHA-256 of the package file used. Its rows must
equal the installed closure; a package listed but not installed, or
installed but not listed, refuses.

**Known nondeterminism, not yet measured.** `SOURCE_DATE_EPOCH` alone proves
nothing: it fixes the dates archiso derives from it (`iso_version`, the ISO
UUID, the ext4 hash seed, the clock epoch file) but not the content.
Candidates to examine: initramfs generation (file order, timestamps,
compression), the squashfs image (file order and timestamps), install-time
caches and databases generated in the image (`ldconfig`, `hwdb`, `man-db`,
pacman's local database), the uncommented mirror list, Python bytecode if
any package compiles it, and anything a pacman hook writes with the current
time. `machine-id` is already written as `uninitialized` by mkarchiso.

**Two-build comparison.** Two builds from the same inputs, each in a fresh
isolated builder with an empty work directory and an empty package cache,
are compared by the SHA-256 of the image and of the package manifest:

- equal manifests and equal images: the build is reproducible for those
  inputs, and only then is it eligible for signing;
- different manifests: the inputs were not the same; the comparison fails;
- equal manifests, different images: the comparison fails; the difference is
  explained (for example with `diffoscope`, package `diffoscope` in `extra`)
  and written up under `problems/`. The build stays development-only until a
  fix gives equal digests.

No bit-for-bit result exists yet: no build has run.

## Artefacts, signing and verification

**Artefacts of one build**, with `<stem>` the working name, version and
architecture, followed by `-dev-unsigned` for a development build:

- `<stem>.iso`, the image;
- `<stem>.packages.tsv`, the package manifest;
- `<stem>.build.json`, the build record: inputs, tool versions, the digests
  of the image and manifest, the build mode, the result of `verify.sh` at `C`;
- `<stem>.notices.tar`, the licence and notice files of every embedded
  package as installed in the image, the root `LICENSE` and
  `iso/profile/LICENSE`;
- the corresponding source of the GPL and LGPL packages, in a form U5 has
  yet to decide; no image carrying them is published without it, from the
  same place and for as long as the image;
- `SHA256SUMS`, over every file above;
- `SHA256SUMS.sig`, a detached OpenPGP signature over `SHA256SUMS`, for a
  release only.

**Integrity is not authentication.** A hash downloaded from the same place
as the image proves only that the download matches that hash: whoever can
replace the image can replace the hash. Only the signature, checked against
a key the user trusts for a reason other than the download host, says who
published the files.

**Build modes.** `iso/build` defaults to `development`: names end in
`-dev-unsigned`, the boot entry and `motd` say "development build, unsigned,
not a release", and `build.json` says `"mode": "development"`. A
`release-candidate` build refuses unless every `iso/admission.yml` entry is
admitted and (`C`, `S`) is a frozen campaign pair. `iso/build` never signs.

**Signing.** `iso/sign-release` is the only path to `SHA256SUMS.sig`. It
refuses, writing nothing, when the build is a development build; when the
two-build comparison is missing or not equal; when no release-key
fingerprint is recorded in the repository; when the key in the signer's
keyring does not have that fingerprint; or when the key is absent. A missing
key therefore leaves a release candidate unsigned and never called a signed
release. The key is a dedicated signing key, not a commit identity; its
custodian, storage, revocation certificate, rotation and the announcement of
a new key (signed by the old one while it is valid) are the operator's.

**User verification**, before writing any medium:

1. Obtain the full 40-hexadecimal primary-key fingerprint from two channels,
   at least one of which does not depend on the download host or on the
   account that publishes the image: this repository's README at the
   release tag, and one more channel the operator names. A short key id is
   not accepted, and two channels that disagree stop the verification.
2. Download the image, `SHA256SUMS`, `SHA256SUMS.sig` and the public key.
3. In an empty temporary `GNUPGHOME`, import the key and check
   `gpg --status-fd 1 --verify SHA256SUMS.sig SHA256SUMS`: the primary-key
   fingerprint on the `VALIDSIG` line must equal the published one. A missing
   `.sig`, a bad signature or another key stops here.
4. `sha256sum --check SHA256SUMS`, without `--ignore-missing`, so that a
   missing or altered file fails.

`iso/verify-download` performs the same steps and refuses on the first
failure; the manual commands remain the reference. No media-write command is
prescribed here.

### Three separate things called signing

- **Live-medium Secure Boot.** archiso `v91` builds no shim or vendor-signed
  boot path; its changelog notes that GRUB's shim_lock verifier is disabled
  so the binaries can be re-signed when repacking with custom keys. The
  proposed image is unsigned for firmware: it boots where Secure Boot is
  disabled or where the user arranges their own signing. No promise is made
  about any firmware.
- **Installed-host enrolment.** `setup_secureboot` creates the host's own
  keys with `sbctl` inside the target and signs its boot files; enrolment
  stays manual (`sbctl enroll-keys` in Setup Mode). Those keys are generated
  on each host and have nothing to do with the release key.
- **Release signature.** The OpenPGP signature over `SHA256SUMS`
  authenticates the download to the user. Firmware never sees it.

## Naming and trademarks

The policy (version 2021-04-18, read 2026-10-26) says:

- section 1: the trademarks include "ARCHLINUX", "ARCH LINUX" and the logo,
  and "Any mark beginning with the letters ARCH is sufficiently similar ...
  that permission will be needed in order to use it";
- section 2, "Derived works": a remix may use the trademarks only if its
  changes are minimal and there is no commercial intent; a product with more
  substantial changes may say it is "based on Arch Linux" but may not use the
  trademarks to refer to itself; and "once a project has left the open source
  project phase or otherwise become a commercial project, this policy does
  not authorize any use of the Trademarks in connection to that project";
- section 3: "Any commercial use" and use "in relation to a software product
  that includes or is built on top of a product supplied by us, if there is
  any commercial intent" need explicit permission from the Arch Linux Project
  Lead (trademarks@archlinux.org); combined marks and implied endorsement are
  very unlikely to be approved;
- section 4: logos keep their ™ declaration and proportions.

The project intends commercial activity, so this record does not rely on the
non-commercial remix permission of section 2. The proposal:

- the working name is descriptive: "HyperLab installer image", file stem
  `hyperlab-installer`, `install_dir` `hyperlab`. It does not start with
  "Arch", and it is a placeholder until the operator chooses the public name;
- no Arch logo, no `splash.png`, no Arch name in the boot entry, `motd`,
  `iso_name`, `iso_label`, `iso_publisher` or `iso_application`;
- nothing in the image or around it says or suggests that it is Arch Linux,
  official, certified or affiliated with Arch Linux;
- what stays is factual and needed to work or to comply: package names,
  mirror and archive URLs, licence notices, and the unmodified files of
  Arch packages, such as `/usr/lib/os-release` of `filesystem`;
- whether distribution material may say "based on Arch Linux", and whether
  this repository's own name, which starts with "arch", needs permission for
  a commercial product, are open questions for the operator, who decides
  whether to ask for permission.

## Counterexamples

| Case | Answer |
| --- | --- |
| No signing key | `iso/sign-release` refuses before writing; the build stays a release candidate, unsigned, never called signed |
| A package changed between builds | the manifests differ, the comparison fails, the build is not eligible for signing |
| An asset of unknown provenance | not admitted; a release-candidate build refuses while any entry is not admitted; a development build may carry it and stays development-only |
| Two clean builds with different digests | the comparison fails, the difference is explained under `problems/`, the build stays development-only |
| A checksum file without a signature | the user verification stops at step 3; `iso/verify-download` refuses; a hash is integrity, not authentication |

## Next implementation unit

One unit: "Build an unsigned development image of the proposed profile". It
creates the proposed files, builds, compares and boots in a VM; it does not
sign, publish, write a medium or boot hardware. Acceptance:

1. **Static validation** in `verify.sh`, through `tests/iso-profile.bats`,
   reading the files with a parser where they have structure:
   `bootmodes` is exactly `uefi.systemd-boot`; `arch` is `x86_64`;
   `iso_name`, `iso_label`, `iso_publisher`, `iso_application`,
   `install_dir`, the boot entry title and `motd` contain neither "Arch
   Linux" nor a word starting with "arch" (case-insensitive), except the
   paths and hook names archiso itself defines; `packages.x86_64` equals the package set of `iso/admission.yml`
   and contains none of `openssh`, `cloud-init`, `reflector`, `syslinux`,
   firmware or microcode packages; no `syslinux/`, `splash.png`,
   `.automated_script.sh` or sshd overlay exists; every `pacman.conf`
   repository uses only the archive date of `iso/build-inputs.yml` and
   `SigLevel = Required`; `ORIGIN.tsv` lists every profile file exactly once
   and nothing else; `iso/profile/LICENSE` is the GPL-3.0 text;
   `build-inputs.yml` has a 40-character `S`. Each check has a mutation that
   turns it red.
2. **Real build** with `iso/build` in an isolated builder: a disposable Arch
   VM or the nested lab host, never the operator's host and never with the
   operator's privilege, with the archiso and keyring of the snapshot. It
   refuses a dirty tree, an unpinned or malformed input, an archiso version
   other than the pin, a package signature failure and a live `cryptsetup`
   without `argon2id`, and it writes the development artefacts named above.
3. **Two-build comparison** with `iso/compare` on two fresh builders: both
   digests are recorded; a mismatch is written up under `problems/` with its
   cause, and the build stays development-only. Equality is not required to
   finish the unit; an honest record is.
4. **UEFI VM smoke test** with QEMU and OVMF (`edk2-ovmf`): the image as a
   read-only CD-ROM, one fresh scratch disk image and no host disk. The live
   prompt and the `motd` marker of the build must appear on the serial
   console; `release.json` parses and names `C` and `S`; every command
   `installer` and `bootstrap` call resolves with `command -v`; the embedded
   `bootstrap` started with closed input refuses in dry-run mode before any
   disk is selected. The scratch disk's SHA-256 before and after the run is identical:
   no unexpected disk write.
5. **Refusal tests** in `tests/iso-release.bats`, with a throwaway key made in
   a temporary `GNUPGHOME`: `iso/verify-download` accepts a good signature by
   the expected fingerprint and a matching hash, and refuses a bad
   signature, a good signature by another key, a missing `.sig`, a missing
   `SHA256SUMS`, a missing image, a changed image and a `SHA256SUMS` that
   lists a file twice; `iso/sign-release` refuses a development build, a
   missing or unequal comparison, a missing fingerprint record and a missing
   key, and writes nothing in each case.
6. Both verifier modes pass; the README and
   [`../release-gates.md`](../release-gates.md) describe the result as
   software-verified only.

## What this does not cover

- choosing the public name, a logo, a domain, the signing key, its custodian
  or the download host; asking anyone for permission;
- changing `installer`, `bootstrap` or the storage contract;
- an offline install, BIOS boot, other architectures, netboot;
- settling U1 to U9; the firmware subset;
- extending the ADR 0013 campaign with the image digest.

## Hardware test

After the implementation unit, and only with an audited, verified build and
its VM result: boot the image on Nitro, then on Predator with the same
image, in UEFI mode, without starting the installation. Observe that the
documented prompt appears, that `release.json` and the package manifest
match the build record, that keyboard and display work, that the target
disks are listed by `lsblk`, that no disk was written and what the firmware's
Secure Boot state was. This boot does not replace the clean installation
gates of [`../release-gates.md`](../release-gates.md).
