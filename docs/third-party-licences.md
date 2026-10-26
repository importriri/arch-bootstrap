# Third-party licences and file origins

This is a record of evidence, not legal advice. It accounts for every file
tracked in this repository and for every package the installer fetches, and
it says, for a possible future ISO, what each component would require and what
is still unknown. Where the evidence does not settle a question, the entry
stays unresolved; nothing unresolved is approved for bundling.

- Input commit: `fee8847df1bd383b9bcbdf2b9f1bf7305bb3c27d` (52 tracked paths).
- Package records, licence texts and PKGBUILDs retrieved: 2026-10-26.
- Machine-readable file inventory: [`file-inventory.tsv`](file-inventory.tsv).

Three questions are kept apart:

1. **This repository's files.** Shell code, tests, stubs, documents and
   configuration published under the root [`LICENSE`](../LICENSE) (MIT).
2. **What the installer installs.** At install time `installer` downloads
   packages from the Arch Linux mirrors onto the live medium and the new
   system. The repository contains none of them and redistributes nothing.
3. **What a future ISO could carry.** An image that contains packages *is* a
   redistribution of them. The dispositions below are inputs to that design;
   they are not the design.

## 1. Repository files

[`file-inventory.tsv`](file-inventory.tsv) has a header and one row per path
of `git ls-files -z` at the input commit, dotfiles, stubs and tests included.
Its columns:

| Column | Meaning |
| --- | --- |
| `path` | the tracked path |
| `sha256` | digest of the file's bytes in the commit that adds the inventory |
| `kind` | `code`, `test`, `stub`, `doc`, `config` or `legal` |
| `origin` | `written here`, `derived from a named upstream` or `unknown` |
| `evidence` | what establishes the origin: introducing commit, upstream URL and revision, or `none` |
| `licence` | the licence that applies to the file |
| `status` | `documented` or `unknown` |

The digests are of the bytes in the commit that adds the inventory. There,
`README.md` and `docs/release-gates.md` carry the link to this report; the
other 50 files are byte-identical to the input commit. The two audit files
are listed here instead of in the inventory, which cannot hold its own
digest:

- `docs/third-party-licences.md` (this report);
- `docs/file-inventory.tsv` (the inventory).

### What the history proves, and what it does not

Git history gives the commit that introduced a file, its date and the
identity recorded on that commit. It is not proof of authorship: a commit
records who added bytes, not who wrote them or where they came from. Every
commit up to the input commit is authored under the maintainer's identity
(the person named in `LICENSE` and [`AUTHORS.md`](../AUTHORS.md)); the earliest
files arrived together in `2d5fe57`, so anything that existed before that
commit has no history here.

The `written here` origin therefore rests on three things, and only these:
the introducing commit carries the maintainer's identity; the content has no
third-party copyright line, licence notice, attribution or note of a
third-party source (the tree was searched for them); and `LICENSE` and
`AUTHORS.md` declare the maintainer as author. The declaration is the maintainer's statement, not an
independent proof, and confirming it remains with the maintainer.

### Result

| Kind | Paths | Origin | Licence |
| --- | --- | --- | --- |
| `code` | 2 (`bootstrap`, `installer`) | written here | MIT (root `LICENSE`) |
| `test` | 6 (two Bats suites, LUKS header gate, two storage gates, `verify.sh`) | written here | MIT (root `LICENSE`) |
| `stub` | 28 (`tests/stubs/`) | written here | MIT (root `LICENSE`) |
| `doc` | 12 (`README.md`, `docs/release-gates.md`, `problems/`) | written here | MIT (root `LICENSE`) |
| `config` | 2 (`.gitignore`, CI workflow) | written here | MIT (root `LICENSE`) |
| `legal` | `AUTHORS.md` | written here | MIT (root `LICENSE`) |
| `legal` | `LICENSE` | derived from a named upstream | MIT licence text |

`LICENSE` is the MIT License text of the
[SPDX licence list](https://spdx.org/licenses/MIT.html) (list version 3.29.0,
retrieved 2026-10-26) with its copyright line filled in: after whitespace
normalisation the text from "Permission is hereby granted" to the end is
identical to the SPDX `MIT` text.

No row is `unknown`. No third-party code, text, image or data was found in
the tree, so the repository itself carries no third-party notice obligation
beyond keeping `LICENSE` with copies.

The CI workflow refers to the GitHub Action `actions/checkout@v4` by name.
It is fetched by the hosted runner and is not part of the repository (see
[build-time tools](#4-build-time-and-verification-tools-not-shipped)).

## 2. Packages the installer fetches

The installer pins no version. Arch Linux is a rolling distribution: an
install fetches whatever the mirrors serve that day. The versions below are
those of the official package records in the stable repositories (`core`,
`extra`) on 2026-10-26; the installer does not edit `pacman.conf`, so it
installs from the repositories the live medium enables.

Fetch points in `installer`:

- `PACSTRAP_PACKAGES`, installed into the target with
  `pacstrap -K "$MOUNT_ROOT" "${PACSTRAP_PACKAGES[@]}"` in `pacstrap_base`;
- `pacman -Sy --noconfirm archlinux-keyring` on the live medium, right
  before `pacstrap`, in `pacstrap_base`;
- `pacman -Sy --noconfirm cryptsetup` on the live medium, in `encrypt_root`,
  only on a real run and only when the live `cryptsetup --help` does not list
  `argon2id`.

`bootstrap` sources `installer` and fetches nothing of its own.

Record URLs follow `https://archlinux.org/packages/<repo>/<arch>/<name>/`;
the data was read from the JSON search API
(`https://archlinux.org/packages/search/json/?name=<name>`). The
"conditions" column paraphrases the licence named by the record; reading it
against a concrete ISO is an interpretation for the operator to confirm.

| Package | Repo, version | Arch record licence | Upstream | Purpose in the installer | Conditions on redistribution | ISO disposition |
| --- | --- | --- | --- | --- | --- | --- |
| [`base`](https://archlinux.org/packages/core/any/base/) | core 3-3 | `GPL` (no version given) | <https://www.archlinux.org> | target: minimal Arch system; its dependencies include `systemd` (`bootctl`, networkd, resolved) and `pacman` | the package installs no files; everything is in its 27 dependencies | blocked pending evidence: its closure is not inventoried (U1) |
| [`linux-hardened`](https://archlinux.org/packages/extra/x86_64/linux-hardened/) | extra 7.2.10.hardened1-3 | `GPL-2.0-only` | <https://github.com/anthraxx/linux-hardened> | target: the kernel, signed by `sbctl` | licence text with every copy; complete corresponding source of the exact build offered by whoever distributes the binary | documented conditions, source delivery undecided (U5) |
| `linux-firmware` | core 20260916-1 | `CC0-1.0` for the meta package; per-vendor terms in its dependencies | <https://gitlab.com/kernel-firmware/linux-firmware> | target: device firmware | see [firmware and microcode](#3-firmware-and-microcode) | blocked pending evidence (U2) |
| `intel-ucode` | extra 20260925-1 | `custom` | <https://github.com/intel/Intel-Linux-Processor-Microcode-Data-Files> | target: Intel CPU microcode, embedded by the mkinitcpio microcode hook | see [firmware and microcode](#3-firmware-and-microcode) | blocked pending evidence (U3) |
| `amd-ucode` | core 20260916-1 | `LicenseRef-amd-ucode` | <https://gitlab.com/kernel-firmware/linux-firmware> | target: AMD CPU microcode, embedded by the mkinitcpio microcode hook | see [firmware and microcode](#3-firmware-and-microcode) | blocked pending evidence (U4) |
| [`btrfs-progs`](https://archlinux.org/packages/core/x86_64/btrfs-progs/) | core 7.1-1 | `GPL-2.0-only` | <https://btrfs.readthedocs.io> | target: Btrfs tools for the root and VM filesystems (the live medium's own copy formats them) | licence text; corresponding source | documented conditions, source delivery undecided (U5) |
| [`cryptsetup`](https://archlinux.org/packages/core/x86_64/cryptsetup/) | core 2.8.8-1 | `GPL-2.0-or-later` | <https://gitlab.com/cryptsetup/cryptsetup/> | target: LUKS2 tools; live medium: conditional upgrade when `argon2id` is missing | licence text; corresponding source | documented conditions, source delivery undecided (U5) |
| [`dosfstools`](https://archlinux.org/packages/core/x86_64/dosfstools/) | core 4.2-5 | `GPL-3.0-or-later` | <https://github.com/dosfstools/dosfstools> | target: `fsck.vfat` for the ESP line `genfstab` writes | licence text; corresponding source | documented conditions, source delivery undecided (U5) |
| [`sbctl`](https://archlinux.org/packages/extra/x86_64/sbctl/) | extra 0.18-2 | `MIT` | <https://github.com/Foxboron/sbctl> | target: Secure Boot key creation and signing | copyright and permission notice with copies; built with `go`, and the Go modules compiled into the binary are not inventoried | blocked pending evidence (U7) |
| [`zram-generator`](https://archlinux.org/packages/extra/x86_64/zram-generator/) | extra 1.2.1-1 | `MIT` | <https://github.com/systemd/zram-generator> | target: zram swap, no swap partition | copyright and permission notice; built with `rust`, and the crates compiled into the binary are not inventoried | blocked pending evidence (U7) |
| [`iwd`](https://archlinux.org/packages/extra/x86_64/iwd/) | extra 3.12-2 | `LGPL-2.1-or-later` | <https://git.kernel.org/cgit/network/wireless/iwd.git/> | target: Wi-Fi for the stage-2 fetch | licence text; corresponding source | documented conditions, source delivery undecided (U5) |
| [`git`](https://archlinux.org/packages/extra/x86_64/git/) | extra 2.56.0-1 | `GPL-2.0-only` | <https://git-scm.com/> | target: cloning `hyperlab-ansible` at first boot | licence text; corresponding source | documented conditions, source delivery undecided (U5) |
| [`ansible`](https://archlinux.org/packages/extra/any/ansible/) | extra 14.5.0-1 | `GPL-3.0-or-later` | <https://pypi.org/project/ansible/> | target: running stage 2 | licence text; corresponding source; the record names one licence for a package that bundles many collections, whose own licences are not inventoried | blocked pending evidence (U7) |
| [`sudo`](https://archlinux.org/packages/core/x86_64/sudo/) | core 1.9.17.p2-6 | `custom` | <https://www.sudo.ws/sudo/> | target: privilege for the stage-2 playbooks (`-K`) | upstream `LICENSE.md` at `v1.9.17p2` (sha256 `41eb34d6b184c2638d6d32c6e7f70b8dd6423e68b91da959e0cf773aa01f62d7`): an ISC-style licence for sudo plus per-file ISC and BSD notices; the copyright and permission notices must appear in copies; three BSD notices forbid using their authors' names to endorse derived products | documented conditions |
| [`vim`](https://archlinux.org/packages/extra/x86_64/vim/) | extra 9.2.1178-1 | `custom:vim` | <https://www.vim.org> | target: editor on the TTY host | upstream `LICENSE` at `v9.2.1178` (sha256 `0b3f1f330cb1b179bb17c7c687d4cec601e0aa3462bc7f890ad4c3888d37d720`): unmodified copies and executables built from unmodified sources must include the licence text (section I); a modified version must meet four further conditions (section II); the PKGBUILD at `9.2.1178-1` applies no patch file but edits `src/feature.h` with `sed` to set the system vimrc path | blocked pending evidence (U8) |
| [`archlinux-keyring`](https://archlinux.org/packages/core/any/archlinux-keyring/) | core 20260909-1 | `GPL-3.0-or-later` | <https://gitlab.archlinux.org/archlinux/archlinux-keyring/> | live medium: refreshed before `pacstrap`; target: pulled in again by `base` | licence text; corresponding source | documented conditions, source delivery undecided (U5) |

`cryptsetup` appears twice in the installer: in `PACSTRAP_PACKAGES` and in the
live-medium upgrade. It is the same package; on a future ISO the second use
becomes part of the live payload.

## 3. Firmware and microcode

These three packages carry binary blobs under their vendors' terms. The
kernel's GPL does not license them, and no single licence describes them.

### `linux-firmware`

The record for [`linux-firmware`](https://archlinux.org/packages/core/any/linux-firmware/)
20260916-1 says `CC0-1.0`, but that package is a meta package: in the
PKGBUILD at tag
[`20260916-1`](https://gitlab.archlinux.org/archlinux/packaging/packages/linux-firmware/-/blob/20260916-1/PKGBUILD)
`package_linux-firmware` installs nothing and depends on twelve split
packages, which carry the firmware. (The file list the website shows for the
meta package is dated 2025-05-24, older than the split, and was not used.)
Each split package has `LicenseRef-WHENCE` plus its own identifiers and
depends on `linux-firmware-whence`, which ships the upstream `WHENCE` file as
`/usr/share/licenses/linux-firmware-whence/WHENCE`.

`WHENCE` at upstream tag `20260916`
(<https://gitlab.com/kernel-firmware/linux-firmware/-/blob/20260916/WHENCE>,
474322 bytes, sha256
`9350832c1e9afc35df50fa8b9793b31d60d78ef963152eec903fc0dbc6b4a559`; the
record of `linux-firmware-whence` 20260916-1 gives the same installed size)
documents each firmware's origin and licence. It has 262 `Driver:` entries
and 279 lines that open with `Licence:` or `License:`, in 143 distinct
wordings. Most read "Redistributable. See LICENCE.<vendor> for details";
others name
`GPLv2`, `GPLv2 or later`, `GPLv3`, `MIT`, `Apache-2.0` or "Dual GPLv2/MPL".
Ten say that no source is visible:

| `WHENCE` driver | Statement | Split package carrying its files |
| --- | --- | --- |
| `ti_usb_3410_5052` | Allegedly GPLv2+, but no source visible | `linux-firmware-ti` |
| `whiteheat` | Allegedly GPLv2, but no source visible | `linux-firmware-other` |
| `cpia2` | Allegedly GPLv2+, but no source visible | `linux-firmware-other` |
| `io_edgeport` | Allegedly GPLv2+, but no source visible | `linux-firmware-other` |
| `io_ti` | Allegedly GPLv2+, but no source visible | `linux-firmware-other` |
| `snd-sb16-csp` | Allegedly GPLv2+, but no source visible | `linux-firmware-other` |
| `cxgb3` | GPLv2 or OpenIB.org BSD license, no source visible | `linux-firmware-other` |
| `starfire` | Allegedly GPLv2, but no source visible | `linux-firmware-other` |
| `smc91c92_cs` | Allegedly GPL, but no source visible | `linux-firmware-other` |
| `snd-wavefront` | Allegedly GPLv2+, but no source visible | `linux-firmware-other` |

The split packages, their record licences and the licence files they install
under `/usr/share/licenses/<package>/` (from the PKGBUILD install lines and
the package file lists, all 20260916-1):

| Split package | Record licences (besides `LicenseRef-WHENCE`) | Licence files shipped |
| --- | --- | --- |
| `linux-firmware-amd` | `LicenseRef-amd` | 3: `LICENSE.amd-sev`, `LICENSE.amd_pmf`, `LICENSE.amdnpu` |
| `linux-firmware-amdgpu` | `LicenseRef-amdgpu`, `MIT` | 2: `LICENSE.amdgpu`, `LICENSE.amdisp` |
| `linux-firmware-atheros` | `GPL-2.0-only`, `LicenseRef-atheros` | 7: `LICENCE.atheros_firmware`, `LICENCE.open-ath9k-htc-firmware`, `LICENSE.QualcommAtheros_ar3k`, `LICENSE.QualcommAtheros_ath10k`, `LICENSE.qcom`, `NOTICE.qca`, `NOTICE.qcom` |
| `linux-firmware-broadcom` | `LicenseRef-broadcom` | 5: `LICENCE.bnx2`, `LICENCE.bnx2x`, `LICENCE.broadcom_bcm43xx`, `LICENCE.cypress`, `LICENCE.tigon` |
| `linux-firmware-cirrus` | `LicenseRef-cirrus` | 1: `LICENSE.cirrus` |
| `linux-firmware-intel` | `Apache-2.0`, `GPL-2.0-only`, `LicenseRef-intel` | 20, from `LICENCE.HP` to `LICENSE.xe` |
| `linux-firmware-mediatek` | `LicenseRef-mediatek` | 3: `LICENCE.mediatek`, `LICENCE.ralink-firmware.txt`, `LICENCE.ralink_a_mediatek_company_firmware` |
| `linux-firmware-nvidia` | `LicenseRef-nvidia` | 1: `LICENCE.nvidia` |
| `linux-firmware-other` | none | 125: every `LICENCE.*`/`LICENSE.*` of the upstream `LICENSES/` directory |
| `linux-firmware-radeon` | `LicenseRef-radeon` | 1: `LICENSE.radeon` |
| `linux-firmware-realtek` | `LicenseRef-realtek` | 1: `LICENCE.rtlwifi_firmware.txt` |
| `linux-firmware-ti` | `GPL-2.0-or-later`, `LicenseRef-ti` | 3: `LICENCE.ti-connectivity`, `LICENCE.ti-tspa`, `LICENCE.wl1251` |
| `linux-firmware-whence` | (only `LicenseRef-WHENCE`) | `WHENCE` |

None of these licence files has been read and summarised here: each is its
own vendor's terms. **Disposition: blocked pending evidence (U2).** A future
ISO that carries firmware must either review every licence file of every
split package it keeps, keep `WHENCE` and those files with the image, and
settle the ten entries without visible source, or carry a reviewed subset.

### `intel-ucode`

The record for [`intel-ucode`](https://archlinux.org/packages/extra/any/intel-ucode/)
20260925-1 says `custom`. The PKGBUILD at tag
[`20260925-1`](https://gitlab.archlinux.org/archlinux/packaging/packages/intel-ucode/-/blob/20260925-1/PKGBUILD)
installs the upstream file `license` as
`/usr/share/licenses/intel-ucode/LICENSE`, installs the microcode files under
`/usr/lib/firmware/intel-ucode/`, and builds `/boot/intel-ucode.img` with
`iucode_tool --write-earlyfw` from them.

The upstream `license` at tag `microcode-20260925`
(<https://github.com/intel/Intel-Linux-Processor-Microcode-Data-Files/blob/microcode-20260925/license>,
sha256 `03efb1491c7e899feb2665fa299363e64035e5444c1b8bc1f6ebed30de964e12`)
permits redistribution and use in binary form, without modification, if the
copyright notice and disclaimer are reproduced with the distribution, Intel's
name is not used to endorse derived products, and the software is not reverse
engineered, decompiled or disassembled.

**Disposition: blocked pending evidence (U3).** The conditions are clear, but
whether the early-load image that `iucode_tool` assembles counts as
redistribution "without modification" is an interpretation the operator must
confirm.

### `amd-ucode`

[`amd-ucode`](https://archlinux.org/packages/core/any/amd-ucode/) 20260916-1
is built from the same `linux-firmware` source; its record says
`LicenseRef-amd-ucode`. The PKGBUILD at tag `20260916-1` concatenates
`amd-ucode/microcode_amd*.bin` into `/boot/amd-ucode.img`, installs the
microcode files under `/usr/lib/firmware/amd-ucode/`, and installs
`LICENSES/LICENSE.amd-ucode` as `/usr/share/licenses/amd-ucode/LICENSE.amd-ucode`.

That file at upstream tag `20260916`
(<https://gitlab.com/kernel-firmware/linux-firmware/-/blob/20260916/LICENSES/LICENSE.amd-ucode>,
sha256 `2103bd999f77522c5ab5fd35df0579ed00e2a6b885f6f8ebd444e97ffa482991`)
permits installing, copying and distributing the microcode in binary form if
the copyright notice and the licence are reproduced with it. It forbids
implying AMD's endorsement and reverse engineering; it states that rights to
third-party technologies the microcode may implement are not conveyed; and it
requires compliance with U.S. and European export rules, including a
certification about restricted destinations.

**Disposition: blocked pending evidence (U4).** The third-party technology
clause and the export certification need the operator's review before an
image distributed to the public carries this file.

## 4. Build-time and verification tools (not shipped)

These tools build or check the repository. None of them is installed on a
target or carried by the repository, so their licences have no bearing on
what the repository or a target redistributes, and they are not audited
here.

| Tool | Where | Use |
| --- | --- | --- |
| `actions/checkout@v4` | hosted CI | checks out this repository and `hyperlab-ansible` |
| `shellcheck` | CI (`apt-get`), `verify.sh` | shell lint |
| `bats` | CI (`apt-get`), `verify.sh` | contract and unit suites |
| `cryptsetup-bin` | CI (`apt-get`), `verify.sh` as `cryptsetup` | the sparse-file LUKS2 header gate |
| `python3-yaml` | CI (`apt-get`), `verify.sh` as PyYAML | parsing the storage contract |
| `bash`, `python3`, `git` | `verify.sh` | entrypoint requirements |
| `losetup`, `sgdisk`, `cryptsetup`, `mkfs.fat`, `mkfs.btrfs`, `btrfs`, `findmnt`, `lsattr`, `stat`, `lsblk`, `readlink`, `udevadm` | `tests/vm-pipeline-test`, in a throwaway VM | the disposable two-loop storage gate |

The commands `installer` runs from the live medium (`sgdisk`, `lsblk`,
`mkfs.fat`, `mkfs.btrfs`, `pacstrap`, `genfstab`, `arch-chroot` and others)
come from the Archiso the operator boots. The
installer does not fetch them and the repository does not ship them; a future
ISO that becomes that live medium must inventory them as part of its own
payload (U9).

## 5. Transitive dependencies: not inventoried

Only the packages the installer names are listed above. pacman resolves
their dependency closure at install time, and that closure is not
inventoried here. Examples, from the records: `base` depends on
`archlinux-keyring`, `bash`, `bzip2`, `coreutils`, `file`, `filesystem`,
`findutils`, `gawk`, `gcc-libs`, `gettext`, `glibc`, `grep`, `gzip`,
`iproute2`, `iputils`, `licenses`, `pacman`, `pciutils`, `procps-ng`,
`psmisc`, `sed`, `shadow`, `systemd`, `systemd-sysvcompat`, `tar`,
`util-linux` and `xz`; `ansible` on `ansible-core` and `python`; `vim` on
`vim-runtime`; `linux-hardened` on `initramfs`, which pulls in an initramfs
generator. This is not a bill of materials. An ISO build must inventory the
closure it actually installs, with versions and the licence files under
`/usr/share/licenses/`.

## 6. Third-party notices

- Repository: no third-party material was found, so no third-party notice is
  required; `LICENSE` stays with every copy.
- Installed systems: every package installs its own licence files under
  `/usr/share/licenses/<package>/`. Nothing in `installer` or `bootstrap`
  refers to that directory, so they are installed as packaged.
- A future ISO: the notices of every component it carries must travel with
  the image; this report does not reproduce them.

## 7. Unresolved redistribution prerequisites

Nothing below is approved for bundling. Each item stays open until the
evidence it names exists.

| Id | Component | Missing evidence | Blocks |
| --- | --- | --- | --- |
| U1 | transitive closure of every installed package (`base` and all others) | an inventory of the exact closure an ISO build installs, with versions and licences | any ISO payload |
| U2 | `linux-firmware` split packages | review of each shipped licence file (`WHENCE` plus 172 files across 12 split packages, many of them duplicated between packages); a decision on the 10 `WHENCE` entries without visible source | firmware in an ISO |
| U3 | `intel-ucode` | whether the `iucode_tool` early-load image is redistribution "without modification" | Intel microcode in an ISO |
| U4 | `amd-ucode` | review of the third-party technology clause and the export certification | AMD microcode in an ISO |
| U5 | GPL and LGPL packages (`linux-hardened`, `btrfs-progs`, `cryptsetup`, `dosfstools`, `iwd`, `git`, `ansible`, `archlinux-keyring`, and the closure) | how an ISO offers the complete corresponding source of the exact builds it carries | any ISO carrying them |
| U6 | `base` record licence | `GPL` without a version; the package installs no files, so this weighs only on the record | nothing by itself; recorded for completeness |
| U7 | `sbctl`, `zram-generator`, `ansible` | licences of the Go modules and Rust crates compiled into the first two, and of the collections bundled in `ansible` | these three in an ISO |
| U8 | `vim` | whether the Arch build, whose PKGBUILD edits `src/feature.h`, is built from unmodified sources (section I) or is a modified version (section II) of the Vim licence | `vim` in an ISO |
| U9 | live-medium tools (Archiso payload) | an inventory of the live environment a future ISO would become | an installer ISO |

The repository files themselves add no open item: their origin rests on the
maintainer's declaration, as explained in section 1.
