#!/usr/bin/env bash
# Mirror hosted CI locally. The real LUKS header check needs root; everything
# else stays host-independent and never touches a block device.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$ROOT"

required=(bash shellcheck bats cryptsetup)
for tool in "${required[@]}"; do
	command -v "$tool" >/dev/null \
		|| { echo "missing verification dependency: $tool" >&2; exit 2; }
done

shell_paths=(
	bootstrap
	installer
	test-installer
	tests/luks-header-verify.sh
	tests/vm-pipeline-test
)
while IFS= read -r path; do
	shell_paths+=("$path")
done < <(find tests -maxdepth 1 -type f -name '*.sh' ! -name 'luks-header-verify.sh' -print | sort)

printf '%s\n' '== Bash syntax =='
for path in "${shell_paths[@]}"; do
	echo "--- $path"
	bash -n "$path"
done

printf '%s\n' '== ShellCheck =='
for path in "${shell_paths[@]}"; do
	echo "--- $path"
	shellcheck -x "$path"
done

printf '%s\n' '== Bats contracts =='
bats tests/*.bats

printf '%s\n' '== Real LUKS2 header =='
if (( EUID == 0 )); then
	bash tests/luks-header-verify.sh
elif command -v sudo >/dev/null && sudo -n true 2>/dev/null; then
	sudo bash tests/luks-header-verify.sh
else
	echo "real LUKS verification needs root; run sudo bash verify.sh" >&2
	exit 2
fi

printf '%s\n' 'arch-bootstrap verification: PASS'
