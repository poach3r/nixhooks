# shellcheck shell=bash
# nixhooks runtime library 

NIXHOOKS_FAILED=0
NIXHOOKS_FILES=()

_nixhooks_skip_list() {
  IFS=',' read -ra _nixhooks_skip <<<"${SKIP:-}"
}
_nixhooks_skip_list

should_skip() {
  local name="$1" s
  for s in "${_nixhooks_skip[@]}"; do
    [[ "$s" == "$name" ]] && return 0
  done
  return 1
}

# Args: name files_regex exclude_regex pass_filenames(0|1) always_run(0|1) entry [extra_args...]
# Matches against $NIXHOOKS_FILES populated by the caller before invocation
run_hook() {
  local name="$1" files_re="$2" exclude_re="$3" pass_filenames="$4" always_run="$5" entry="$6"
  shift 6
  local extra_args=("$@")

  if should_skip "$name"; then
    echo "nixhooks: skip  $name (SKIP)"
    return 0
  fi

  local matched=() f
  if [[ "$always_run" != 1 ]]; then
    for f in "${NIXHOOKS_FILES[@]}"; do
      [[ "$f" =~ $files_re ]] || continue
      [[ "$exclude_re" != '^$' && "$f" =~ $exclude_re ]] && continue
      matched+=("$f")
    done
    if [[ ${#matched[@]} -eq 0 ]]; then
      echo "nixhooks: skip  $name (no matching files)"
      return 0
    fi
  fi

  echo "nixhooks: run   $name"
  local cmd=("$entry" "${extra_args[@]}")
  if [[ "$pass_filenames" == 1 && "$always_run" != 1 ]]; then
    cmd+=("${matched[@]}")
  fi

  if ! "${cmd[@]}"; then
    echo "nixhooks: FAIL  $name"
    NIXHOOKS_FAILED=1
  fi
}

nixhooks_summary() {
  if [[ "$NIXHOOKS_FAILED" -ne 0 ]]; then
    echo "nixhooks: one or more hooks failed" >&2
    exit 1
  fi
}

# File discovery 
nixhooks_collect_precommit_files() {
  local against
  if git rev-parse --verify -q HEAD >/dev/null; then
    against=HEAD
  else
    against="$(git hash-object -t tree /dev/null)"
  fi
  NIXHOOKS_FILES=()
  while IFS= read -r -d '' f; do
    NIXHOOKS_FILES+=("$f")
  done < <(git diff --cached --name-only --diff-filter=ACM -z "$against")
}

nixhooks_collect_repo_files() {
  NIXHOOKS_FILES=()
  while IFS= read -r -d '' f; do
    NIXHOOKS_FILES+=("$f")
  done < <(git ls-files -z)
}

nixhooks_collect_prepush_files() {
  local remote_sha="$1" local_sha="$2"
  NIXHOOKS_FILES=()
  if [[ "$remote_sha" =~ ^0+$ ]]; then
    # new branch / no upstream: no meaningful base to diff against
    while IFS= read -r -d '' f; do
      NIXHOOKS_FILES+=("$f")
    done < <(git ls-files -z)
  else
    while IFS= read -r -d '' f; do
      NIXHOOKS_FILES+=("$f")
    done < <(git diff --name-only -z "$remote_sha" "$local_sha")
  fi
}
