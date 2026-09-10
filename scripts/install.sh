#!/usr/bin/env bash
# Install this checkout as a Pi package and link its canonical instructions.
set -euo pipefail

fail() {
  printf 'pi-kit install: %s\n' "$*" >&2
  exit 1
}

script_dir=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -P -- "$script_dir/.." && pwd)
canonical="$repo_dir/config/pi/AGENTS.md"

[[ -f "$canonical" ]] || fail "canonical instructions are missing: $canonical"
command -v npm >/dev/null 2>&1 || fail "npm is required but was not found in PATH"
command -v pi >/dev/null 2>&1 || fail "pi is required but was not found in PATH"
[[ -n ${HOME:-} ]] || fail "HOME is not set"

agent_dir="$HOME/.pi/agent"
dest="$agent_dir/AGENTS.md"

# Reject configuration conflicts before npm or Pi can modify any state.
if [[ -e "$agent_dir" || -L "$agent_dir" ]]; then
  [[ -d "$agent_dir" && ! -L "$agent_dir" ]] || fail "agent directory is not a directory: $agent_dir"
fi
if [[ -L "$dest" ]]; then
  [[ -e "$dest" && "$dest" -ef "$canonical" ]] || fail "refusing to replace existing AGENTS.md symlink: $dest; reconcile it manually"
elif [[ -e "$dest" ]]; then
  [[ -f "$dest" ]] || fail "refusing to replace non-regular AGENTS.md: $dest; reconcile it manually"
  cmp -s -- "$dest" "$canonical" || fail "existing AGENTS.md differs from pi-kit canonical instructions: $dest; reconcile it manually"
fi

(cd "$repo_dir" && npm ci)
pi install "$repo_dir"
mkdir -p -- "$agent_dir"

# Recheck after running external commands in case the destination changed.
if [[ -L "$dest" ]]; then
  if [[ -e "$dest" && "$dest" -ef "$canonical" ]]; then
    exit 0
  fi
  fail "refusing to replace existing AGENTS.md symlink: $dest; reconcile it manually"
elif [[ -e "$dest" ]]; then
  [[ -f "$dest" ]] || fail "refusing to replace non-regular AGENTS.md: $dest; reconcile it manually"
  cmp -s -- "$dest" "$canonical" || fail "existing AGENTS.md differs from pi-kit canonical instructions: $dest; reconcile it manually"

  timestamp=$(date -u +%Y%m%dT%H%M%SZ)
  backup="$agent_dir/AGENTS.md.pre-pi-kit.$timestamp"
  suffix=1
  while [[ -e "$backup" || -L "$backup" ]]; do
    backup="$agent_dir/AGENTS.md.pre-pi-kit.$timestamp.$suffix"
    suffix=$((suffix + 1))
  done
  mv -- "$dest" "$backup"
  if ! ln -s -- "$canonical" "$dest"; then
    mv -- "$backup" "$dest" || true
    fail "could not create AGENTS.md symlink: $dest"
  fi
else
  ln -s -- "$canonical" "$dest"
fi
