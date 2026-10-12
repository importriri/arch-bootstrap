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

# contract_as_parsed FILE: the storage contract as a YAML parser reads it: its
# top-level keys, then one field a line in the file's order with its parsed
# value (a string quoted, null as None, true as True). A status other than 0
# when it is not valid YAML or repeats a key, which safe_load would otherwise
# resolve in silence to the last copy.
contract_as_parsed() {
	python3 - "$1" <<'PY'
import sys
import yaml


class NoDuplicateKeys(yaml.SafeLoader):
    pass


def mapping(loader, node, deep=False):
    keys = [loader.construct_object(key, deep=deep) for key, _ in node.value]
    if len(keys) != len(set(keys)):
        raise yaml.constructor.ConstructorError(
            None, None, "a key is repeated", node.start_mark)
    return loader.construct_mapping(node, deep)


NoDuplicateKeys.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, mapping)
with open(sys.argv[1], encoding="utf-8") as handle:
    contract = yaml.load(handle, Loader=NoDuplicateKeys)
print("keys=%s" % ",".join(contract))
print("schema_version=%r" % contract["schema_version"])
for key, value in contract["vm_store"].items():
    print("%s=%r" % (key, value))
PY
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
	#problems/storage-contract-was-not-valid-yaml.md: read by a YAML parser,
	#as HyperLab reads it, not compared as text
	run contract_as_parsed "$contract"
	[ "$status" -eq 0 ]
	[ "$output" = "keys=schema_version,vm_store
schema_version=1
topology='single-disk'
mountpoint='/var/lib/libvirt/images'
mapper='/dev/mapper/cryptroot'
fstype='btrfs'
subvolume='@vm'
require_nocow=True
root_partlabel='ARCH_ROOT'
vm_partlabel=None" ]
	[ "$(stat -c %a "$contract")" = 644 ]
}

@test "dedicated-disk contract binds cryptvm filesystem root" {
	install() { command mkdir -p "${*: -1}"; }
	chown() { :; }
	mkdir -p "$MOUNT_ROOT"

	run write_storage_contract dedicated-disk
	[ "$status" -eq 0 ]
	contract="$MOUNT_ROOT$BOOTSTRAP_STORAGE_CONTRACT"
	[ -f "$contract" ]
	run contract_as_parsed "$contract"
	[ "$status" -eq 0 ]
	[ "$output" = "keys=schema_version,vm_store
schema_version=1
topology='dedicated-disk'
mountpoint='/var/lib/libvirt/images'
mapper='/dev/mapper/cryptvm'
fstype='btrfs'
subvolume=None
require_nocow=True
root_partlabel='ARCH_ROOT'
vm_partlabel='ARCH_VM'" ]
	[ "$(stat -c %a "$contract")" = 644 ]
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

@test "verification runs as a normal user and never calls sudo" {
	#problems/verify-used-an-unlocked-sudo.md
	run grep -nE '\bsudo\b' "$REPO/verify.sh" "$REPO/tests/luks-header-verify.sh"
	[ "$status" -eq 1 ]
	#in CI the only sudo allowed is `sudo apt-get` as a command of its own:
	#with every `sudo apt-get` taken out, no sudo may remain anywhere, whatever
	#the key (run:, shell:), the layout (one line or a run: | block) or what
	#it follows (&&, ;)
	run bash -c "sed -E 's/(^|[^[:alnum:]_-])sudo apt-get([[:space:]]|$)/\\1\\2/g' '$REPO/.github/workflows/ci.yml' | grep -nE '(^|[^[:alnum:]_-])sudo([^[:alnum:]_-]|$)'"
	[ "$status" -eq 1 ]
	[ -z "$output" ]
	run grep -nE '^[[:space:]]*(-[[:space:]]*)?run:[[:space:]]*bash verify\.sh[[:space:]]*$' "$REPO/.github/workflows/ci.yml"
	[ "$status" -eq 0 ]
	run grep -nE '^bash tests/luks-header-verify\.sh$' "$REPO/verify.sh"
	[ "$status" -eq 0 ]
	#the grep above reads two files; a sudo reached through a helper or a
	#sourced file is caught here instead: the LUKS step runs with an unlocked
	#fake sudo first on PATH, must pass, and must leave it untouched
	mkdir -p "$BATS_TEST_TMPDIR/bin"
	printf '#!/bin/sh\ntouch "%s/sudo-was-called"\nexit 0\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/sudo"
	chmod +x "$BATS_TEST_TMPDIR/bin/sudo"
	PATH="$BATS_TEST_TMPDIR/bin:$PATH" run bash "$REPO/tests/luks-header-verify.sh"
	[ "$status" -eq 0 ]
	[[ "$output" == *"ALL LUKS VERIFICATIONS PASSED"* ]]
	[ ! -e "$BATS_TEST_TMPDIR/sudo-was-called" ]
}

@test "the README says the dry run asks for the LUKS passphrase and never uses it" {
	#problems/dry-run-asks-for-luks-passphrase.md
	run grep -F "for the root LUKS passphrase twice" "$REPO/README.md"
	[ "$status" -eq 0 ]
	run grep -F "It never uses the passphrase and writes nothing" "$REPO/README.md"
	[ "$status" -eq 0 ]
	run grep -F "acquire + confirm the passphrase in the dry-run too" "$REPO/installer"
	[ "$status" -eq 0 ]
}

# Run the whole entrypoint, as an operator would, in dry run: real bootstrap
# and installer, the logging stubs for every external tool, a lsblk that
# shows one disk, and only the root and UEFI guards neutralized in a copy.
_dry_run_bootstrap() {
	local box="$BATS_TEST_TMPDIR/box"
	mkdir -p "$box/bin"
	mkdir -p "$box/mapper"
	sed -e 's/^check_root() {$/check_root() { echo "[TEST] root guard skipped" >\&2; return 0; }\n_real_check_root() {/' \
	    -e 's/^check_uefi() {$/check_uefi() { echo "[TEST] UEFI guard skipped" >\&2; return 0; }\n_real_check_uefi() {/' \
	    -e "s|/dev/mapper/|$box/mapper/|g" \
	    "$REPO/installer" > "$box/installer"
	cp "$REPO/bootstrap" "$box/bootstrap"
	grep -q 'root guard skipped' "$box/installer"
	grep -q 'UEFI guard skipped' "$box/installer"
	grep -q "$box/mapper/" "$box/installer"
	#findmnt lists / and, when a test sets STUB_MOUNTS, those targets; with
	#STUB_FINDMNT_FAIL it fails as a broken findmnt would
	cat > "$box/bin/findmnt" <<'STUB'
#!/usr/bin/env bash
source "$STUB_DIR/_stub_lib.sh"
_log "$@"
if [[ "$*" == "-rno TARGET" ]]; then
	[[ -n ${STUB_FINDMNT_FAIL:-} ]] && { echo "findmnt: cannot read mountinfo" >&2; exit 1; }
	printf '/\n'
	[[ -n ${STUB_MOUNTS:-} ]] && printf '%s\n' $STUB_MOUNTS
	exit 0
fi
exit 1
STUB
	chmod +x "$box/bin/findmnt"
	cat > "$box/bin/lsblk" <<'STUB'
#!/usr/bin/env bash
source "$STUB_DIR/_stub_lib.sh"
_log "$@"
[[ "$*" == "-dnpo NAME,SIZE,TYPE" ]] && echo "/dev/vdz 80G disk"
exit 0
STUB
	chmod +x "$box/bin/lsblk"
	export STUB_LOG="$BATS_TEST_TMPDIR/stub.log" STUB_DIR="$REPO/tests/stubs"
	: > "$STUB_LOG"
	# disk 1, the path typed back, the passphrase twice; the second-disk
	# menu finds no other disk and asks nothing.
	run env PATH="$box/bin:$REPO/tests/stubs:$PATH" DRY_RUN=1 "$@" bash -c \
		"printf '1\n/dev/vdz\npw12345678\npw12345678\n' | bash '$box/bootstrap'"
}

@test "a dry run of the whole entrypoint changes nothing, at its exit either" {
	#problems/dry-run-asks-for-luks-passphrase.md
	_dry_run_bootstrap
	[ "$status" -eq 0 ]
	[[ "$output" == *"[DRY-RUN] real installation would write"* ]]
	grep -q '^sgdisk --pretend ' "$STUB_LOG"
	run grep -Ev '^(ping |lsblk |findmnt |sgdisk --pretend |cryptsetup --help$|cryptsetup isLuks )' "$STUB_LOG"
	[ "$status" -eq 1 ]
	[ -z "$output" ]
}

@test "a dry run stopped by sgdisk (pretend) failed changes nothing either" {
	#problems/dry-run-asks-for-luks-passphrase.md
	_dry_run_bootstrap STUB_SGDISK_RC=4
	[ "$status" -ne 0 ]
	[[ "$output" == *"sgdisk (pretend) failed"* ]]
	grep -q '^sgdisk --pretend ' "$STUB_LOG"
	run grep -Ev '^(ping |lsblk |findmnt |sgdisk --pretend |cryptsetup --help$|cryptsetup isLuks )' "$STUB_LOG"
	[ "$status" -eq 1 ]
	[ -z "$output" ]
}

@test "a run refuses to start over a mounted /mnt, and the dry run says so" {
	#problems/dry-run-asks-for-luks-passphrase.md: cleanup no longer releases
	#what an earlier run left behind, so a new run must refuse to start on it
	_dry_run_bootstrap STUB_MOUNTS="/mnt /mnt/boot"
	[ "$status" -ne 0 ]
	[[ "$output" == *"a real run would refuse"* ]]
	[[ "$output" == *"umount -R /mnt"* ]]
	run grep -c '^sgdisk ' "$STUB_LOG"
	[ "$output" = "0" ]
	run grep -Ev '^(ping |lsblk |findmnt |cryptsetup --help$|cryptsetup isLuks )' "$STUB_LOG"
	[ -z "$output" ]
}

@test "a run refuses to start over an open cryptroot or cryptvm" {
	local box="$BATS_TEST_TMPDIR/box"
	mkdir -p "$box/mapper"
	: > "$box/mapper/cryptvm"
	_dry_run_bootstrap
	[ "$status" -ne 0 ]
	[[ "$output" == *"a real run would refuse"* ]]
	[[ "$output" == *"cryptsetup close cryptvm"* ]]
	run grep -c '^sgdisk ' "$STUB_LOG"
	[ "$output" = "0" ]
}

@test "the wrapper owns what a successful installer leaves, without a side channel" {
	#problems/dry-run-asks-for-luks-passphrase.md
	run grep -nE 'mktemp|INSTALLER_OWNED_FILE' "$REPO/bootstrap" "$REPO/installer"
	[ "$status" -eq 1 ]
	local box="$BATS_TEST_TMPDIR/adopt"
	mkdir -p "$box/mapper"
	sed -e "s|\"/mnt\"|\"$BATS_TEST_TMPDIR/mnt\"|g" \
	    -e "s|\"/mnt/.btrfs-top\"|\"$BATS_TEST_TMPDIR/mnt/.btrfs-top\"|g" \
	    -e "s|/dev/mapper/|$box/mapper/|g" \
	    "$REPO/installer" > "$box/installer"
	cp "$REPO/bootstrap" "$box/bootstrap"
	run bash -c "source '$box/bootstrap'; adopt_installer_work
		printf '%s\n' \"\${OWNED_MOUNTS[@]}\"; echo root=\$OWNED_ROOT_MAPPER vm=\$OWNED_VM_MAPPER"
	[ "$status" -eq 0 ]
	m="$BATS_TEST_TMPDIR/mnt"
	[ "${lines[0]}" = "$m/" ]
	[ "${lines[1]}" = "$m/home" ]
	[ "${lines[7]}" = "$m/boot" ]
	[ "${lines[8]}" = "root=1 vm=0" ]
	: > "$box/mapper/cryptvm"
	run bash -c "source '$box/bootstrap'; adopt_installer_work; echo vm=\$OWNED_VM_MAPPER"
	[ "${lines[-1]}" = "vm=1" ]
}

@test "the refusal names the mounts actually left, not a /mnt that is not mounted" {
	_dry_run_bootstrap STUB_MOUNTS="/mnt/.btrfs-top /mnt/boot"
	[ "$status" -ne 0 ]
	[[ "$output" == *"umount -R /mnt/.btrfs-top"* ]]
	[[ "$output" == *"umount -R /mnt/boot"* ]]
	[[ "$output" != *"umount -R /mnt"$'\n'* ]]
	run grep -c '^sgdisk ' "$STUB_LOG"
	[ "$output" = "0" ]
}

@test "a run refuses to start when the mounts cannot be listed" {
	_dry_run_bootstrap STUB_FINDMNT_FAIL=1
	[ "$status" -ne 0 ]
	[[ "$output" == *"could not list the mounts"* ]]
	run grep -c '^sgdisk ' "$STUB_LOG"
	[ "$output" = "0" ]
}

@test "a run refuses to start over an open cryptroot" {
	local box="$BATS_TEST_TMPDIR/box"
	mkdir -p "$box/mapper"
	: > "$box/mapper/cryptroot"
	_dry_run_bootstrap
	[ "$status" -ne 0 ]
	[[ "$output" == *"a real run would refuse"* ]]
	[[ "$output" == *"cryptsetup close cryptroot"* ]]
	run grep -c '^sgdisk ' "$STUB_LOG"
	[ "$output" = "0" ]
}
