#!/usr/bin/env bash
# Mirror hosted CI locally, as a normal user: no step needs root or asks for
# privilege. Nothing here touches a block device; the real LUKS header check
# writes only a temporary file in /tmp.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$ROOT"

required=(bash shellcheck bats cryptsetup python3)
for tool in "${required[@]}"; do
	command -v "$tool" >/dev/null \
		|| { echo "missing verification dependency: $tool" >&2; exit 2; }
done
# The storage contract is read by a YAML parser, as HyperLab reads it.
python3 -c 'import yaml' 2>/dev/null \
	|| { echo "missing verification dependency: python3 yaml (PyYAML)" >&2; exit 2; }

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
bash tests/luks-header-verify.sh

printf '%s\n' 'arch-bootstrap verification: PASS'
