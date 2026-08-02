#!/usr/bin/env bats
# Host-independent contract tests for the complete bootstrap wrapper.

setup() {
	REPO=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
	SANDBOX="$BATS_TEST_TMPDIR/repo"
	mkdir -p "$SANDBOX"
	sed -e "s|\"/mnt\"|\"$BATS_TEST_TMPDIR/mnt\"|g" \
	    -e "s|\"/mnt/.btrfs-top\"|\"$BATS_TEST_TMPDIR/mnt/.btrfs-top\"|g" \
	    "$REPO/installer" > "$SANDBOX/installer"
	cp "$REPO/bootstrap" "$SANDBOX/bootstrap"
	export DRY_RUN=0
	# shellcheck source=/dev/null
	source "$SANDBOX/bootstrap"
}

@test "the wrapper invokes installer through Bash" {
	run grep -F 'bash "$BOOTSTRAP_DIR/installer" "$@"' "$REPO/bootstrap"
	[ "$status" -eq 0 ]
}

@test "the VM mountpoint comes only from SUBVOL_LAYOUT" {
	run vm_storage_mountpoint
	[ "$status" -eq 0 ]
	[ "$output" = "/var/lib/libvirt/images" ]
}

@test "single-disk contract binds cryptroot and @vm" {
	install() { command mkdir -p "${*: -1}"; }
	chown() { :; }
	mkdir -p "$MOUNT_ROOT"

	run write_storage_contract single-disk
	[ "$status" -eq 0 ]
	contract="$MOUNT_ROOT$BOOTSTRAP_STORAGE_CONTRACT"
	[ -f "$contract" ]
	grep -q '^schema_version: 1$' "$contract"
	grep -q '^  topology: single-disk$' "$contract"
	grep -q '^  mountpoint: /var/lib/libvirt/images$' "$contract"
	grep -q '^  mapper: /dev/mapper/cryptroot$' "$contract"
	grep -q '^  subvolume: @vm$' "$contract"
	grep -q '^  vm_partlabel: null$' "$contract"
	[ "$(stat -c %a "$contract")" = 644 ]
}

@test "dedicated-disk contract binds cryptvm filesystem root" {
	install() { command mkdir -p "${*: -1}"; }
	chown() { :; }
	mkdir -p "$MOUNT_ROOT"

	run write_storage_contract dedicated-disk
	[ "$status" -eq 0 ]
	contract="$MOUNT_ROOT$BOOTSTRAP_STORAGE_CONTRACT"
	grep -q '^  topology: dedicated-disk$' "$contract"
	grep -q '^  mapper: /dev/mapper/cryptvm$' "$contract"
	grep -q '^  subvolume: null$' "$contract"
	grep -q '^  vm_partlabel: ARCH_VM$' "$contract"
}

@test "dedicated key finalization requires a regular keyfile and mode 0400" {
	mkdir -p "$(dirname "$MOUNT_ROOT$VM_KEYFILE")"
	: > "$MOUNT_ROOT$VM_KEYFILE"
	chmod 0000 "$MOUNT_ROOT$VM_KEYFILE"

	run finalize_vm_storage_key dedicated-disk
	[ "$status" -eq 0 ]
	[ "$(stat -c %a "$MOUNT_ROOT$VM_KEYFILE")" = 400 ]

	rm -f "$MOUNT_ROOT$VM_KEYFILE"
	run finalize_vm_storage_key dedicated-disk
	[ "$status" -ne 0 ]
	[[ "$output" == *"missing or redirected"* ]]
}

@test "topology detection distinguishes cryptroot @vm from cryptvm root" {
	findmnt() {
		case "$*" in
			*SOURCE*) printf '%s\n' "$OBSERVED_SOURCE" ;;
			*FSROOT*) printf '%s\n' "$OBSERVED_FSROOT" ;;
		esac
	}

	OBSERVED_SOURCE='/dev/mapper/cryptroot[/@vm]'
	OBSERVED_FSROOT='/@vm'
	run detect_vm_storage_topology
	[ "$status" -eq 0 ]
	[ "$output" = single-disk ]

	OBSERVED_SOURCE='/dev/mapper/cryptvm'
	OBSERVED_FSROOT='/'
	run detect_vm_storage_topology
	[ "$status" -eq 0 ]
	[ "$output" = dedicated-disk ]

	OBSERVED_SOURCE='/dev/mapper/other'
	OBSERVED_FSROOT='/'
	run detect_vm_storage_topology
	[ "$status" -ne 0 ]
}

@test "storage verification accepts the declared fsroot and rejects drift" {
	target="$MOUNT_ROOT/var/lib/libvirt/images"
	mkdir -p "$target"
	findmnt() {
		case "$*" in
			*SOURCE*) printf '%s\n' "$OBSERVED_SOURCE" ;;
			*FSTYPE*) printf '%s\n' btrfs ;;
			*FSROOT*) printf '%s\n' "$OBSERVED_FSROOT" ;;
		esac
	}
	lsattr() { printf '%s %s\n' '---------------C------' "$target"; }
	find() { :; }

	OBSERVED_SOURCE='/dev/mapper/cryptroot[/@vm]'
	OBSERVED_FSROOT='/@vm'
	run verify_vm_storage single-disk
	[ "$status" -eq 0 ]

	OBSERVED_FSROOT='/'
	run verify_vm_storage single-disk
	[ "$status" -ne 0 ]
	[[ "$output" == *"fsroot mismatch"* ]]
}

@test "the official entrypoint runs the engine then observed post-conditions" {
	text=$(cat "$REPO/bootstrap")
	[[ "$text" == *'bash "$BOOTSTRAP_DIR/installer" "$@"'* ]]
	[[ "$text" == *'topology=$(detect_vm_storage_topology)'* ]]
	[[ "$text" == *'finalize_vm_storage_key "$topology"'* ]]
	[[ "$text" == *'verify_vm_storage "$topology"'* ]]
	[[ "$text" == *'write_storage_contract "$topology"'* ]]
	[[ "$text" == *'arch-bootstrap complete'* ]]
}

@test "the verifier syntax-checks every discovered shell path" {
	text=$(cat "$REPO/verify.sh")
	[[ "$text" == *'for path in "${shell_paths[@]}"'* ]]
	[[ "$text" == *'bash -n "$path"'* ]]
	[[ "$text" != *'bash -n "${shell_paths[@]}"'* ]]
}

@test "the destructive gate resolves mountpoints with explicit findmnt targets" {
	text=$(cat "$REPO/tests/vm-pipeline-test")
	[[ "$text" == *'findmnt -rno OPTIONS --target "$MOUNT_ROOT"'* ]]
	[[ "$text" == *'findmnt -rno FSTYPE --target "$MOUNT_ROOT/boot"'* ]]
	[[ "$text" != *'findmnt -no OPTIONS "$MOUNT_ROOT"'* ]]
	[[ "$text" == *'observed: $root_options'* ]]
}

@test "the destructive gate reaps only verified sparse-file fixtures" {
	text=$(cat "$REPO/tests/vm-pipeline-test")
	[[ "$text" == *'mapper_fixture_loop'* ]]
	[[ "$text" == *'/tmp/bootstrap-root.'* ]]
	[[ "$text" == *'/tmp/bootstrap-vm.'* ]]
	[[ "$text" == *'it is not a verified bootstrap test fixture'* ]]
	[[ "$text" == *'unmount_mapper_mounts'* ]]
	[[ "$text" == *'findmnt -rn -S "$mapper_path" -o TARGET'* ]]
	[[ "$text" == *'[CLEANUP] unmounting verified fixture target'* ]]
	[[ "$text" == *'close_fixture_mapper'* ]]
	[[ "$text" == *'[CLEANUP-FAIL] bootstrap fixture teardown was incomplete'* ]]
	[[ "$text" == *'trap teardown EXIT'* ]]
}
