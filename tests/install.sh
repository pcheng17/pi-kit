#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
installer="$repo_dir/scripts/install.sh"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/pi-kit-install-test.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
fake_bin="$tmp/bin"
mkdir -p -- "$fake_bin"

command_log="$tmp/external-commands"
export PI_KIT_TEST_COMMAND_LOG="$command_log"

cat > "$fake_bin/npm" <<'EOF'
#!/bin/sh
printf 'npm\n' >> "$PI_KIT_TEST_COMMAND_LOG"
[ "$1" = ci ] || exit 64
printf '%s\n' "$PWD" >> "$HOME/npm-ci-cwds"
EOF
cat > "$fake_bin/pi" <<'EOF'
#!/bin/sh
printf 'pi\n' >> "$PI_KIT_TEST_COMMAND_LOG"
[ "$1" = install ] || exit 64
repo=$2
mkdir -p "$HOME/.pi/agent"
settings="$HOME/.pi/agent/settings.json"
touch "$settings"
grep -Fqx "$repo" "$settings" || printf '%s\n' "$repo" >> "$settings"
EOF
chmod +x "$fake_bin/npm" "$fake_bin/pi"

run_install() {
  HOME=$1 PATH="$fake_bin:$PATH" "$installer"
}
assert_canonical_link() {
  dest=$1/.pi/agent/AGENTS.md
  test -L "$dest"
  test "$dest" -ef "$repo_dir/config/pi/AGENTS.md"
}
expect_failure() {
  set +e
  "$@" >"$tmp/failure-output" 2>&1
  status=$?
  set -e
  test "$status" -ne 0
}
expect_preflight_failure() {
  : > "$command_log"
  expect_failure "$@"
  test ! -s "$command_log"
}

# An absent destination is linked; a rerun leaves one Pi registration.
home_absent="$tmp/home-absent"
mkdir -p "$home_absent"
run_install "$home_absent"
assert_canonical_link "$home_absent"
run_install "$home_absent"
test "$(grep -Fxc "$repo_dir" "$home_absent/.pi/agent/settings.json")" -eq 1
test "$(wc -l < "$home_absent/npm-ci-cwds" | tr -d ' ')" -eq 2
test "$(grep -Fxc "$repo_dir" "$home_absent/npm-ci-cwds")" -eq 2

# A matching regular file is retained as a visible backup before linking.
home_matching="$tmp/home-matching"
mkdir -p "$home_matching/.pi/agent"
cp "$repo_dir/config/pi/AGENTS.md" "$home_matching/.pi/agent/AGENTS.md"
run_install "$home_matching"
assert_canonical_link "$home_matching"
backup_count=$(find "$home_matching/.pi/agent" -maxdepth 1 -name 'AGENTS.md.pre-pi-kit.*' -type f | wc -l | tr -d ' ')
test "$backup_count" -eq 1
cmp -s "$repo_dir/config/pi/AGENTS.md" "$(find "$home_matching/.pi/agent" -maxdepth 1 -name 'AGENTS.md.pre-pi-kit.*' -type f)"

# A differing file is not modified.
home_different="$tmp/home-different"
mkdir -p "$home_different/.pi/agent"
printf 'different instructions\n' > "$home_different/.pi/agent/AGENTS.md"
expect_preflight_failure env HOME="$home_different" PATH="$fake_bin:$PATH" "$installer"
test ! -L "$home_different/.pi/agent/AGENTS.md"
test "$(cat "$home_different/.pi/agent/AGENTS.md")" = 'different instructions'
test ! -e "$home_different/.pi/agent/settings.json"

# Incorrect and broken links are not replaced.
home_link="$tmp/home-link"
mkdir -p "$home_link/.pi/agent"
printf 'other\n' > "$tmp/other-instructions"
ln -s "$tmp/other-instructions" "$home_link/.pi/agent/AGENTS.md"
link_before=$(readlink "$home_link/.pi/agent/AGENTS.md")
expect_preflight_failure env HOME="$home_link" PATH="$fake_bin:$PATH" "$installer"
test "$(readlink "$home_link/.pi/agent/AGENTS.md")" = "$link_before"
test ! -e "$home_link/.pi/agent/settings.json"

home_broken="$tmp/home-broken"
mkdir -p "$home_broken/.pi/agent"
ln -s "$tmp/missing-instructions" "$home_broken/.pi/agent/AGENTS.md"
link_before=$(readlink "$home_broken/.pi/agent/AGENTS.md")
expect_preflight_failure env HOME="$home_broken" PATH="$fake_bin:$PATH" "$installer"
test "$(readlink "$home_broken/.pi/agent/AGENTS.md")" = "$link_before"
test ! -e "$home_broken/.pi/agent/settings.json"

# Missing HOME fails before invoking npm or Pi.
expect_preflight_failure env -u HOME PATH="$fake_bin:$PATH" "$installer"

printf 'install.sh tests passed\n'
