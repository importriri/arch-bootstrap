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

# Only this test interface selects a sibling; there is no implicit lookup or
# network fetch. A supplied but unusable checkout is always an error.
_storage_check() {
	if [[ ! ${HYPERLAB_ANSIBLE_REPO+x} ]]; then
		if [[ ${CROSS_REPO_STORAGE_REQUIRED:-0} == 1 ]]; then
			echo 'cross-repo storage: FAILED - required sibling is absent' >&2
			return 1
		fi
		echo 'cross-repo storage: SKIPPED - nothing cross-repository was proved'
		return 0
	fi
	[[ -n $HYPERLAB_ANSIBLE_REPO ]] \
		|| { echo 'cross-repo storage: FAILED - explicit sibling is empty' >&2; return 1; }
	_storage_compare "$SANDBOX" "$HYPERLAB_ANSIBLE_REPO" || return 1
	local producer_revision consumer_revision
	producer_revision=$(git -C "$REPO" rev-parse HEAD) || return 1
	consumer_revision=$(git -C "$HYPERLAB_ANSIBLE_REPO" rev-parse HEAD) || return 1
	printf 'Compared arch-bootstrap=%s hyperlab-ansible=%s\n' \
		"$producer_revision" "$consumer_revision"
}

_storage_compare() {
	python3 - "$@" <<'PY'
import json
import os
from pathlib import Path
import stat
import subprocess
import sys

import yaml


class NoDuplicateKeys(yaml.SafeLoader):
    pass


def mapping(loader: yaml.SafeLoader, node: yaml.nodes.MappingNode,
            deep: bool = False) -> dict:
    result = {}
    for key, value in node.value:
        key = loader.construct_object(key, deep=deep)
        if key in result:
            raise ValueError(f"duplicate YAML key: {key}")
        result[key] = loader.construct_object(value, deep=deep)
    return result


NoDuplicateKeys.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, mapping)


def regular_input(path: Path) -> str:
    # The explicitly selected checkout root is resolved once by the caller;
    # files and directories below that root must not redirect the inputs.
    for item in (path, *path.parents):
        if item.is_symlink():
            raise ValueError(f"redirected input: {item}")
    if not stat.S_ISREG(path.stat().st_mode):
        raise ValueError(f"not a regular input: {path}")
    return path.read_text(encoding="utf-8")


def compare() -> None:
    producer = Path(sys.argv[1])
    sibling = Path(sys.argv[2]).resolve(strict=True)
    variant = sys.argv[3] if len(sys.argv) > 3 else "clean"
    manifest = Path(sys.argv[4]) if len(sys.argv) > 4 else sibling / "release/acceptance.v2.yml"
    guard = sibling / "tools/bootstrap_storage_guard.py"
    regular_input(guard)
    acceptance = yaml.load(regular_input(manifest), Loader=NoDuplicateKeys)
    # These are independent findmnt fixtures, not values derived from installer
    # constants or the producer output. They are never observations of this host.
    observations = {
        "single-disk": ("/dev/mapper/cryptroot[/@vm]", "/@vm"),
        "dedicated-disk": ("/dev/mapper/cryptvm", "/"),
    }
    writer = '''
source "$1" || exit 1
install() { command mkdir -p "${*: -1}" || return 1; }
chown() { :; }
write_storage_contract "$2" >&2 || exit 1
printf '%s' "$MOUNT_ROOT$BOOTSTRAP_STORAGE_CONTRACT"
'''
    shapes = {}
    for topology, (source, fsroot) in observations.items():
        written = subprocess.run(["bash", "-euc", writer, "writer",
                                  str(producer / "bootstrap"), topology],
                                 text=True, capture_output=True, check=False)
        if written.returncode:
            raise ValueError(f"writer failed ({topology}): {written.stderr}")
        contract = Path(written.stdout)
        document = yaml.load(regular_input(contract), Loader=NoDuplicateKeys)
        if variant == "writable":
            contract.chmod(0o666)
        elif variant == "symlink":
            original = contract.with_suffix(".original")
            contract.rename(original)
            contract.symlink_to(original)
        observed = {"target": "/var/lib/libvirt/images", "source": source,
                    "fstype": "btrfs", "fsroot": fsroot, "options": "rw,noatime"}
        if variant == "mapper":
            observed["source"] = "/dev/mapper/other"
        elif variant == "fsroot":
            observed["fsroot"] = "/wrong"
        env = dict(os.environ, PRIVATESTACK_BOOTSTRAP_STORAGE_TEST="1",
                   PYTHONDONTWRITEBYTECODE="1")
        result = subprocess.run([sys.executable, "-B", str(guard), "--mode", "validate",
                                 "--contract", str(contract), "--hyperlab-root",
                                 "/var/lib/libvirt/images/hyperlab"],
                                input=json.dumps({"filesystems": [observed]}),
                                text=True, capture_output=True, env=env, check=False)
        if result.returncode:
            raise ValueError(f"consumer refused ({topology}, exit {result.returncode}): "
                             f"{result.stderr}")
        normalized = json.loads(result.stdout)
        assert normalized["topology"] == topology, normalized
        assert normalized["mapper"] == source.split("[", 1)[0], normalized
        assert normalized["fsroot"] == fsroot, normalized
        assert normalized["mountpoint"] == observed["target"], normalized
        assert normalized["subvolume"] == document["vm_store"]["subvolume"], normalized
        shapes[topology] = {key: normalized[key] for key in ("mapper", "fsroot", "subvolume")}
        print(f"guard accepted {topology}: {json.dumps(normalized, sort_keys=True)}")
    assert acceptance["allowed_storage_topologies"] == shapes, (
        "manifest storage disagreement", acceptance["allowed_storage_topologies"], shapes)
    print("cross-repo storage: OK (both actual writer outputs, guard CLI, complete manifest mapping)")


try:
    compare()
except (OSError, ValueError, KeyError, TypeError, AssertionError, yaml.YAMLError) as exc:
    print(f"cross-repo storage: FAILED - {exc}", file=sys.stderr)
    sys.exit(1)
PY
}

_storage_need_sibling() {
	if [[ ! ${HYPERLAB_ANSIBLE_REPO+x} && ${CROSS_REPO_STORAGE_REQUIRED:-0} != 1 ]]; then
		skip 'no explicit sibling; nothing cross-repository was proved'
	fi
	[[ -n ${HYPERLAB_ANSIBLE_REPO:-} ]] || return 1
}

_storage_input_case() {
	local mode="$1" path="${2:-}"
	unset HYPERLAB_ANSIBLE_REPO CROSS_REPO_STORAGE_REQUIRED
	case "$mode" in
		required) export CROSS_REPO_STORAGE_REQUIRED=1 ;;
		explicit) export HYPERLAB_ANSIBLE_REPO="$path" ;;
		standalone) ;;
		*) return 1 ;;
	esac
	_storage_check
}

@test "actual storage writer agrees with the sibling guard and manifest" {
	run _storage_check
	printf '# %s\n' "${lines[@]}" >&3
	[ "$status" -eq 0 ]
}

@test "storage comparison refuses absent required and explicit missing inputs" {
	run _storage_input_case standalone
	[ "$status" -eq 0 ]
	[[ "$output" == *'SKIPPED - nothing cross-repository was proved'* ]]
	run _storage_input_case required
	[ "$status" -ne 0 ]
	[[ "$output" == *'required sibling is absent'* ]]
	local path diagnostic
	while IFS='|' read -r path diagnostic; do
		run _storage_input_case explicit "${path/@TMP@/$BATS_TEST_TMPDIR}"
		[ "$status" -ne 0 ]
		[[ "$output" != *SKIPPED* ]]
		[[ "$output" == *"$diagnostic"* ]]
	done <<'CASES'
|explicit sibling is empty
@TMP@/missing|No such file or directory
@TMP@/repo|bootstrap_storage_guard.py
CASES
	# Exercise missing manifest and redirected/non-regular guard inputs without
	# copying or executing a replacement consumer.
	mkdir -p "$SANDBOX/tools" || return 1
	: > "$SANDBOX/tools/bootstrap_storage_guard.py"
	run _storage_input_case explicit "$SANDBOX"
	[ "$status" -ne 0 ]
	[[ "$output" == *'acceptance.v2.yml'* ]]
	rm "$SANDBOX/tools/bootstrap_storage_guard.py" || return 1
	ln -s "$SANDBOX/bootstrap" "$SANDBOX/tools/bootstrap_storage_guard.py" || return 1
	run _storage_input_case explicit "$SANDBOX"
	[ "$status" -ne 0 ]
	[[ "$output" == *'redirected input'* ]]
	rm "$SANDBOX/tools/bootstrap_storage_guard.py" || return 1
	mkdir "$SANDBOX/tools/bootstrap_storage_guard.py" || return 1
	run _storage_input_case explicit "$SANDBOX"
	[ "$status" -ne 0 ]
	[[ "$output" == *'not a regular input'* ]]
}

# Execute altered source in a fresh Bash process so readonly installer labels
# cannot also redefine the independent findmnt fixture or the guard's answer.
_storage_mutate_producer() {
	python3 - "$@" <<'PY' || return 1
from pathlib import Path
import sys

producer = Path(sys.argv[1])
mutations = {
    "root-label": ("installer", 'ROOT_LABEL="ARCH_ROOT"', 'ROOT_LABEL="RENAMED_ROOT"'),
    "vm-label": ("installer", 'VM_LABEL="ARCH_VM"', 'VM_LABEL="RENAMED_VM"'),
    "root-mapper": ("installer", 'LUKS_NAME="cryptroot"', 'LUKS_NAME="otherroot"'),
    "vm-mapper": ("installer", 'VM_LUKS_NAME="cryptvm"', 'VM_LUKS_NAME="othervm"'),
    "mountpoint": ("installer", '@vm|/var/lib/libvirt/images|nocow', '@vm|/other/images|nocow'),
    "subvolume": ("bootstrap", "expected_subvolume='\"@vm\"'", "expected_subvolume='\"@other\"'"),
}
filename, before, after = mutations[sys.argv[2]]
path = producer / filename
text = path.read_text()
assert text.count(before) == 1, (filename, before)
path.write_text(text.replace(before, after))
PY
}

@test "storage producer mutations reach the real consumer and are refused" {
	_storage_need_sibling
	local mutation diagnostic box
	while IFS='|' read -r mutation diagnostic; do
		box="$BATS_TEST_TMPDIR/$mutation"
		mkdir -p "$box" || return 1
		cp "$SANDBOX/installer" "$SANDBOX/bootstrap" "$box/" || return 1
		_storage_mutate_producer "$box" "$mutation" || return 1
		run _storage_compare "$box" "$HYPERLAB_ANSIBLE_REPO"
		printf '# producer mutation %s: expected consumer refusal\n' "$mutation" >&3
		[ "$status" -ne 0 ]
		[[ "$output" == *'consumer refused'*"$diagnostic"* ]]
	done <<'CASES'
root-label|root_partlabel must be ARCH_ROOT
vm-label|vm_partlabel differs
root-mapper|declared mapper differs
vm-mapper|declared mapper differs
mountpoint|mountpoint must be /var/lib/libvirt/images
subvolume|declared subvolume differs
CASES
}

@test "required storage comparison propagates a real consumer refusal" {
	_storage_need_sibling
	export CROSS_REPO_STORAGE_REQUIRED=1
	_storage_mutate_producer "$SANDBOX" root-label || return 1
	run _storage_check
	[ "$status" -ne 0 ]
	[[ "$output" == *'consumer refused'*'root_partlabel must be ARCH_ROOT'* ]]
	[[ "$output" != *SKIPPED* ]]
}

@test "storage observation drift and unsafe contracts remain consumer refusals" {
	_storage_need_sibling
	local variant diagnostic
	while IFS='|' read -r variant diagnostic; do
		# Symlink case runs last: no later writer should follow that fixture link.
		run _storage_compare "$SANDBOX" "$HYPERLAB_ANSIBLE_REPO" "$variant"
		[ "$status" -ne 0 ]
		[[ "$output" == *'consumer refused'*"$diagnostic"* ]]
	done <<'CASES'
mapper|observed VM-store mapper differs
fsroot|observed VM-store fsroot differs
writable|must not be group/world writable
symlink|must be one regular non-symlink file
CASES
}

@test "storage comparison checks the entire manifest mapping and refuses bad inputs" {
	_storage_need_sibling
	local manifest="$HYPERLAB_ANSIBLE_REPO/release/acceptance.v2.yml"
	local variant changed
	for variant in shape extra-topology extra-field missing-topology duplicate malformed; do
		changed="$BATS_TEST_TMPDIR/$variant.yml"
		python3 - "$manifest" "$changed" "$variant" <<'PY' || return 1
from pathlib import Path
import sys

import yaml

source, target = map(Path, sys.argv[1:3])
variant = sys.argv[3]
manifest = yaml.safe_load(source.read_text())
shapes = manifest["allowed_storage_topologies"]
if variant == "shape":
    shapes["single-disk"]["fsroot"] = "/wrong"
elif variant == "extra-topology":
    shapes["other"] = shapes["single-disk"]
elif variant == "extra-field":
    shapes["dedicated-disk"]["extra"] = True
elif variant == "missing-topology":
    del shapes["dedicated-disk"]
text = yaml.safe_dump(manifest)
if variant == "duplicate":
    text += "\nallowed_storage_topologies: {}\n"
elif variant == "malformed":
    text = "allowed_storage_topologies: [\n"
target.write_text(text)
PY
		run _storage_compare "$SANDBOX" "$HYPERLAB_ANSIBLE_REPO" clean "$changed"
		[ "$status" -ne 0 ]
		case "$variant" in
			duplicate) [[ "$output" == *'duplicate YAML key'* ]] ;;
			malformed) [[ "$output" == *'while parsing a flow node'* ]] ;;
			*) [[ "$output" == *'manifest storage disagreement'* ]] ;;
		esac
	done
	local diagnostic
	while IFS='|' read -r variant diagnostic; do
		changed="$BATS_TEST_TMPDIR/$variant.yml"
		case "$variant" in
			redirected) ln -s "$manifest" "$changed" || return 1 ;;
			directory) mkdir "$changed" || return 1 ;;
		esac
		run _storage_compare "$SANDBOX" "$HYPERLAB_ANSIBLE_REPO" clean "$changed"
		[ "$status" -ne 0 ]
		[[ "$output" != *SKIPPED* ]]
		[[ "$output" == *"$diagnostic"* ]]
	done <<'CASES'
missing|No such file or directory
redirected|redirected input
directory|not a regular input
CASES
}
