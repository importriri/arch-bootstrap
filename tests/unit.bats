#!/usr/bin/env bats
# Unit tests for the installer — no root, no real disks, no device-mapper.
# They run the REAL functions (sourced), stubbing only the external tools whose
# side effects we cannot have in CI (cryptsetup open, sgdisk, mkfs, bootctl, ...).
#
#   bats tests/unit.bats
#
# Three source strategies:
#   source_real     — the shipped installer, verbatim (pure-logic tests)
#   source_mutable  — readonly arrays relaxed to declare, so a test can inject
#                     a malformed SUBVOL_LAYOUT and watch validate_layout reject it
#   source_sandbox  — device paths and MOUNT_ROOT redirected into $BATS_TEST_TMPDIR,
#                     so real-branch code writes into a throwaway tree we can grep

setup() {
	REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	INSTALLER="$REPO/installer"
	export STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
	: > "$STUB_LOG"
	PATH="$REPO/tests/stubs:$PATH"
}


_have() { declare -F "$1" >/dev/null; }

source_real() {
	export DRY_RUN="${DRY_RUN:-1}"
	# shellcheck source=/dev/null
	source "$INSTALLER"
}

source_mutable() {
	local patched="$BATS_TEST_TMPDIR/installer.mutable"
	sed 's/^readonly -a /declare -a /' "$INSTALLER" > "$patched"
	export DRY_RUN="${DRY_RUN:-1}"
	# shellcheck source=/dev/null
	source "$patched"
}

source_sandbox() {
	local sb="$BATS_TEST_TMPDIR"
	mkdir -p "$sb/dev" "$sb/mnt"
	local patched="$sb/installer.sandbox"
	sed -e "s|/dev/disk/by-partlabel|$sb/dev|g" \
	    -e "s|\"/mnt\"|\"$sb/mnt\"|g" \
	    -e "s|\"/mnt/.btrfs-top\"|\"$sb/mnt/.btrfs-top\"|g" \
	    "$INSTALLER" > "$patched"
	export DRY_RUN=0
	# shellcheck source=/dev/null
	source "$patched"
}

# ---- validate_layout ---------------------------------------------------------

@test "validate_layout accepts the shipped layout" {
	source_real
	_have validate_layout || skip "validate_layout not in this milestone"
	run validate_layout
	[ "$status" -eq 0 ]
}

@test "validate_layout rejects an empty field" {
	source_mutable
	_have validate_layout || skip "validate_layout not in this milestone"
	SUBVOL_LAYOUT=("@|/|" "|/home|")
	run validate_layout
	[ "$status" -eq 1 ]
	[[ "$output" == *"empty field"* ]]
}

@test "validate_layout rejects a subvol not starting with @" {
	source_mutable
	_have validate_layout || skip "validate_layout not in this milestone"
	SUBVOL_LAYOUT=("home|/home|")
	run validate_layout
	[ "$status" -eq 1 ]
	[[ "$output" == *"must start with"* ]]
}

@test "validate_layout rejects a relative mountpoint" {
	source_mutable
	_have validate_layout || skip "validate_layout not in this milestone"
	SUBVOL_LAYOUT=("@home|home|")
	run validate_layout
	[ "$status" -eq 1 ]
	[[ "$output" == *"must be absolute"* ]]
}

@test "validate_layout rejects duplicate mountpoints" {
	source_mutable
	_have validate_layout || skip "validate_layout not in this milestone"
	SUBVOL_LAYOUT=("@a|/x|" "@b|/x|")
	run validate_layout
	[ "$status" -eq 1 ]
	[[ "$output" == *"Duplicate mountpoint"* ]]
}

@test "validate_layout rejects an unknown flag" {
	source_mutable
	_have validate_layout || skip "validate_layout not in this milestone"
	SUBVOL_LAYOUT=("@vm|/vm|nofsck")
	run validate_layout
	[ "$status" -eq 1 ]
	[[ "$output" == *"Unknown layout flag"* ]]
}

@test "shipped layout: @vm is the only nocow record, /var/lib/pacman has no subvol" {
	source_real
	_have validate_layout || skip "validate_layout not in this milestone"
	local record subvol mount extra nocow_count=0 pacman_subvol=0 nocow_subvol=""
	for record in "${SUBVOL_LAYOUT[@]}"; do
		IFS='|' read -r subvol mount extra <<< "$record"
		if [[ $extra == "nocow" ]]; then
			nocow_count=$(( nocow_count + 1 ))
			nocow_subvol="$subvol"
		fi
		[[ $mount == "/var/lib/pacman" ]] && pacman_subvol=1
	done
	[ "$nocow_count" -eq 1 ]
	[ "$nocow_subvol" = "@vm" ]
	[ "$pacman_subvol" -eq 0 ]
}

# ---- read_passphrase ---------------------------------------------------------

@test "read_passphrase prints the secret with no trailing newline" {
	source_real
	# stderr carries the prompts; keep only stdout (the secret) in $output
	run bash -c "printf 'abcABC123\nabcABC123\n' | { source '$INSTALLER'; read_passphrase 2>/dev/null; }"
	[ "$status" -eq 0 ]
	[ "$output" = "abcABC123" ]
	[ "${#output}" -eq 9 ]
}

@test "read_passphrase rejects a mismatch" {
	source_real
	run bash -c "printf 'aaa\nbbb\n' | { source '$INSTALLER'; read_passphrase; }"
	[ "$status" -eq 1 ]
}

@test "read_passphrase rejects empty" {
	source_real
	run bash -c "printf '\n\n' | { source '$INSTALLER'; read_passphrase; }"
	[ "$status" -eq 1 ]
}

# ---- encrypt_root dry-run ----------------------------------------------------

@test "encrypt_root dry-run describes luksFormat and writes nothing" {
	source_real
	local fakepart="$BATS_TEST_TMPDIR/fakepart"
	head -c 4096 /dev/zero > "$fakepart"
	local before; before=$(sha256sum "$fakepart")
	run bash -c "printf 'pw12345678\npw12345678\n' | { export DRY_RUN=1; source '$INSTALLER'; encrypt_root '$fakepart'; }"
	[ "$status" -eq 0 ]
	[[ "$output" == *"luksFormat"* ]]
	[[ "$output" == *"argon2id"* ]]
	[[ "$output" == *"no header written"* ]]
	local after; after=$(sha256sum "$fakepart")
	[ "$before" = "$after" ]
}

@test "encrypt_root warns when the target already holds a LUKS header" {
	source_real
	local fakepart="$BATS_TEST_TMPDIR/fakepart"
	: > "$fakepart"
	STUB_ISLUKS=0 run bash -c "printf 'pw12345678\npw12345678\n' | { export DRY_RUN=1 STUB_ISLUKS=0; source '$INSTALLER'; encrypt_root '$fakepart'; }"
	[ "$status" -eq 0 ]
	[[ "$output" == *"already holds a LUKS header"* ]]
}

@test "encrypt_root (real) fails when the partition path is missing" {
	source_real
	run bash -c "printf 'pw12345678\npw12345678\n' | { export DRY_RUN=0; source '$INSTALLER'; encrypt_root '/no/such/part'; }"
	[ "$status" -eq 1 ]
	[[ "$output" == *"not found"* ]]
}

@test "encrypt_root dry-run continues with a note when the target does not exist yet" {
	source_real
	run bash -c "printf 'pw12345678\npw12345678\n' | { export DRY_RUN=1; source '$INSTALLER'; encrypt_root '/no/such/part'; }"
	[ "$status" -eq 0 ]
	[[ "$output" == *"does not exist yet"* ]]
	[[ "$output" == *"no header written"* ]]
}

@test "encrypt_root dry-run refuses when cryptsetup cannot argon2id" {
	source_real
	#a rehearsal must not "pass" on a box that can't argon2id, and must not shell
	#out to the package manager. refuse, mutate nothing.
	run bash -c "printf 'pw12345678\npw12345678\n' | { export DRY_RUN=1 STUB_NO_ARGON2ID=1; source '$INSTALLER'; encrypt_root '/no/such/part'; }"
	[ "$status" -eq 1 ]
	[[ "$output" == *"does not list argon2id"* ]]
	[[ "$output" != *"no header written"* ]]
	run grep -q "^pacman " "$STUB_LOG"
	[ "$status" -ne 0 ]
}

@test "encrypt_root (real) updates cryptsetup for argon2id, aborts if still missing" {
	source_real
	local fakepart="$BATS_TEST_TMPDIR/fakepart"; : > "$fakepart"
	#regression guard: the old code printed "Installing argon2", ran
	#"pacman -Sy argon2" (wrong package — argon2id lives inside cryptsetup) and then
	#fell through to luksFormat anyway. now it must UPDATE CRYPTSETUP and, if
	#argon2id is still absent, abort BEFORE any header is written.
	run bash -c "printf 'pw12345678\npw12345678\n' | { export DRY_RUN=0 STUB_NO_ARGON2ID=1; source '$INSTALLER'; encrypt_root '$fakepart'; }"
	[ "$status" -eq 1 ]
	[[ "$output" == *"still cannot argon2id"* ]]
	#it updated cryptsetup, not the argon2 CLI package ...
	grep -q "pacman .*cryptsetup" "$STUB_LOG"
	[[ "$(cat "$STUB_LOG")" != *"pacman -Sy argon2"* ]]
	#... and it never reached luksFormat
	run grep -q "luksFormat" "$STUB_LOG"
	[ "$status" -ne 0 ]
}

@test "dry-run pipeline: every phase after the gate succeeds before any partition exists" {
	source_real
	#the property the demo depends on: 'sudo ./installer' on a blank machine must
	#be able to rehearse the WHOLE pipeline. sequencing checks belong to the real
	#branches; only capability checks may stop a dry-run.
	for fn in encrypt_root make_filesystems create_subvolumes mount_layout \
	          pacstrap_base generate_fstab configure_system \
	          install_bootloader configure_zram setup_secureboot encrypt_vm_disk; do
		_have "$fn" || skip "$fn not in this milestone"
	done
	run bash -c "printf 'pw12345678\npw12345678\n' | {
		export DRY_RUN=1; source '$INSTALLER'
		encrypt_root '/no/such/part' && make_filesystems && create_subvolumes \
		&& mount_layout && pacstrap_base && generate_fstab && configure_system \
		&& install_bootloader && configure_zram && setup_secureboot \
		&& encrypt_vm_disk '/no/such/disk'
	}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"no header written"* ]]
	[[ "$output" == *"no filesystems written"* ]]
	[[ "$output" == *"nothing mounted"* ]]
	[[ "$output" == *"passwd (interactive, root)"* ]]
	[[ "$output" == *"rd.luks.name"* ]]
	[[ "$output" == *"enroll-keys"* ]]
}

# ---- confirm_wipe (the destruction gate) -------------------------------------

@test "confirm_wipe accepts the exact path" {
	source_real
	local d="$BATS_TEST_TMPDIR/disk"; : > "$d"
	run bash -c "source '$INSTALLER'; confirm_wipe '$d' <<< '$d'"
	[ "$status" -eq 0 ]
}

@test "confirm_wipe rejects a wrong path" {
	source_real
	local d="$BATS_TEST_TMPDIR/disk"; : > "$d"
	run bash -c "source '$INSTALLER'; confirm_wipe '$d' <<< '/dev/wrong'"
	[ "$status" -eq 1 ]
	[[ "$output" == *"mismatch"* ]]
}

# ---- real branch: install_bootloader injects the LUKS UUID -------------------

@test "install_bootloader writes rd.luks.name with the real LUKS UUID" {
	source_sandbox
	_have install_bootloader || skip "install_bootloader not in this milestone"
	local sb="$BATS_TEST_TMPDIR"
	# make the preconditions real in the sandbox
	touch "$sb/dev/ARCH_ROOT"
	mkdir -p "$sb/mnt/boot/loader/entries" "$sb/mnt/boot/EFI"
	export STUB_LUKS_UUID="deadbeef-0000-1111-2222-333344445555"

	run install_bootloader
	[ "$status" -eq 0 ]

	local entry="$sb/mnt/boot/loader/entries/arch-hardened.conf"
	[ -f "$entry" ]
	grep -q "rd.luks.name=deadbeef-0000-1111-2222-333344445555=cryptroot" "$entry"
	grep -q "rootflags=subvol=@" "$entry"
	# and NEVER the legacy cryptdevice= syntax (run+status: bats ignores a bare !)
	run grep -q "cryptdevice=" "$entry"
	[ "$status" -ne 0 ]
	# bootctl install was actually invoked
	grep -q "^arch-chroot .*bootctl install" "$STUB_LOG" || grep -q "^bootctl install" "$STUB_LOG"
}

# ---- real branch: configure_system writes the sd-encrypt HOOKS ---------------

@test "configure_system sets HOOKS with sd-encrypt and never the legacy encrypt hook" {
	source_sandbox
	_have configure_system || skip "configure_system not in this milestone"
	local sb="$BATS_TEST_TMPDIR"
	mkdir -p "$sb/mnt/etc"
	printf 'HOOKS=(base udev autodetect modconf block filesystems fsck)\n' > "$sb/mnt/etc/mkinitcpio.conf"
	: > "$sb/mnt/etc/locale.gen"

	run configure_system
	[ "$status" -eq 0 ]

	grep -q "sd-encrypt" "$sb/mnt/etc/mkinitcpio.conf"
	grep -q "systemd" "$sb/mnt/etc/mkinitcpio.conf"
	# the legacy 'encrypt' hook must not survive as a standalone word
	run grep -Eq 'HOOKS=.*[( ]encrypt[ )]' "$sb/mnt/etc/mkinitcpio.conf"
	[ "$status" -ne 0 ]
	[ "$(cat "$sb/mnt/etc/hostname")" = "hypervisor-01" ]
	# the TTY network stack, exactly as enabled
	grep -q "EnableNetworkConfiguration=true" "$sb/mnt/etc/iwd/main.conf"
	grep -q "DHCP=yes" "$sb/mnt/etc/systemd/network/20-wired.network"
	grep -q "systemctl enable iwd systemd-networkd systemd-resolved" "$STUB_LOG"
	# resolv.conf is repointed at the systemd-resolved stub. the link is now made
	# host-side (not through arch-chroot) to dodge EBUSY on the chroot's bind-mounted
	# /etc/resolv.conf, so match the stub target + link basename, not the exact path.
	grep -q "stub-resolv.conf .*/etc/resolv.conf" "$STUB_LOG"
	# a TTY host has no business with NetworkManager, anywhere in the script
	run grep -q "NetworkManager" "$INSTALLER"
	[ "$status" -ne 0 ]
}

# ---- real branch: encrypt_vm_disk wires crypttab by keyfile ------------------

@test "encrypt_vm_disk adds a keyfile-based crypttab entry and adopts the fstab line" {
	source_sandbox
	_have encrypt_vm_disk || skip "encrypt_vm_disk not in this milestone"
	local sb="$BATS_TEST_TMPDIR"
	touch "$sb/dev/ARCH_VM"
	mkdir -p "$sb/mnt/etc"
	export STUB_LUKS_UUID="aaaa1111-bbbb-2222-cccc-333344445555"
	# the line genfstab wrote for the root-side @vm: it must NOT survive
	printf 'UUID=root-fs-uuid /var/lib/libvirt/images btrfs rw,noatime,nodatacow,subvol=/@vm 0 0\n' \
		> "$sb/mnt/etc/fstab"

	run encrypt_vm_disk "$sb/dev/seconddisk"
	[ "$status" -eq 0 ]

	grep -q "cryptvm UUID=aaaa1111-bbbb-2222-cccc-333344445555 .* luks" "$sb/mnt/etc/crypttab"
	# the keyfile path must be the crypttab's 3rd field (unlock by keyfile, not prompt)
	grep -q "/etc/cryptsetup-keys.d/cryptvm.key luks" "$sb/mnt/etc/crypttab"
	# adoption: the old root-container line is gone, the mapper line is in
	run grep -q "UUID=root-fs-uuid" "$sb/mnt/etc/fstab"
	[ "$status" -ne 0 ]
	grep -q "^/dev/mapper/cryptvm /var/lib/libvirt/images btrfs rw,noatime,nodatacow 0 0$" \
		"$sb/mnt/etc/fstab"
	# leftover signatures are killed on the new partition, like on the root disk
	grep -q "^wipefs" "$STUB_LOG"
}

# ---- dry-run of the later phases is honest (touches nothing) -----------------

@test "install_bootloader dry-run names rd.luks.name and writes no files" {
	source_real
	_have install_bootloader || skip "install_bootloader not in this milestone"
	export DRY_RUN=1
	run install_bootloader
	[ "$status" -eq 0 ]
	[[ "$output" == *"rd.luks.name"* ]]
	[[ "$output" == *"luksUUID"* ]]
}

@test "setup_secureboot dry-run signs nothing and defers enrollment to the user" {
	source_real
	_have setup_secureboot || skip "setup_secureboot not in this milestone"
	export DRY_RUN=1
	run setup_secureboot
	[ "$status" -eq 0 ]
	[[ "$output" == *"create-keys"* ]]
	[[ "$output" == *"enroll-keys"* ]]
	[[ "$output" == *"Setup Mode"* ]]
}

@test "configure_zram dry-run mentions no swap partition" {
	source_real
	_have configure_zram || skip "configure_zram not in this milestone"
	export DRY_RUN=1
	run configure_zram
	[ "$status" -eq 0 ]
	[[ "$output" == *"zram"* ]]
}
