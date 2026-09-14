# Unit tests for lib/hooks-runtime.sh -- the hand-written, non-generated
# bash that carries the actual git-protocol correctness (no-HEAD, zero-sha,
# file matching). The Nix-generated glue (script-gen.nix, install-hooks) is
# exercised by building the derivations instead; that's a much lower-risk
# surface (string templating) and isn't duplicated here.

setup() {
  NIXHOOKS_LIB="${NIXHOOKS_LIB:-$BATS_TEST_DIRNAME/../lib}"
  # shellcheck source=../lib/hooks-runtime.sh
  source "$NIXHOOKS_LIB/hooks-runtime.sh"

  TEST_REPO="$(mktemp -d)"
  cd "$TEST_REPO" || return 1
  git init -q
  git config user.email test@example.com
  git config user.name test

  RECORD_FILE="$TEST_REPO/.record"
  RECORDER="$TEST_REPO/.recorder.sh"
  cat >"$RECORDER" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"$RECORD_FILE"
EOF
  chmod +x "$RECORDER"
  export RECORD_FILE
}

teardown() {
  cd / || return 1
  rm -rf "$TEST_REPO"
}

# --- run_hook: file matching / exclude / always_run / pass_filenames ------

@test "run_hook passes only files matching 'files' to the entry" {
  NIXHOOKS_FILES=("a.sh" "b.txt")
  run_hook myhook '\.sh$' '^$' 1 0 "$RECORDER"
  run cat "$RECORD_FILE"
  [[ "$output" == *"a.sh"* ]]
  [[ "$output" != *"b.txt"* ]]
}

@test "run_hook excludes files matching 'exclude'" {
  NIXHOOKS_FILES=("a.sh" "vendor/b.sh")
  run_hook myhook '\.sh$' '^vendor/' 1 0 "$RECORDER"
  run cat "$RECORD_FILE"
  [[ "$output" == *"a.sh"* ]]
  [[ "$output" != *"vendor/b.sh"* ]]
}

@test "run_hook does not invoke the entry when nothing matches" {
  NIXHOOKS_FILES=("a.txt")
  run_hook myhook '\.sh$' '^$' 1 0 "$RECORDER"
  [ ! -e "$RECORD_FILE" ]
}

@test "run_hook with always_run=1 invokes the entry with no files matched" {
  NIXHOOKS_FILES=()
  run_hook myhook '.*' '^$' 1 1 "$RECORDER"
  [ -e "$RECORD_FILE" ]
  # $(...) strips the recorder's trailing newline, so this is empty iff no
  # arguments were passed (printf '%s\n' with zero args still emits one blank line).
  [ -z "$(cat "$RECORD_FILE")" ]
}

@test "run_hook with pass_filenames=0 invokes the entry without filenames" {
  NIXHOOKS_FILES=("a.sh")
  run_hook myhook '\.sh$' '^$' 0 0 "$RECORDER"
  [ -e "$RECORD_FILE" ]
  [ -z "$(cat "$RECORD_FILE")" ]
}

# --- run_hook: SKIP and failure aggregation -------------------------------

@test "run_hook honors SKIP and never invokes the entry" {
  _nixhooks_skip=("myhook")
  NIXHOOKS_FILES=("a.sh")
  run_hook myhook '\.sh$' '^$' 1 0 "$RECORDER"
  [ ! -e "$RECORD_FILE" ]
}

@test "run_hook sets NIXHOOKS_FAILED when the entry fails, without aborting" {
  NIXHOOKS_FAILED=0
  NIXHOOKS_FILES=("a.sh")
  run_hook myhook '\.sh$' '^$' 1 0 false
  [ "$NIXHOOKS_FAILED" -eq 1 ]
}

@test "run_hook leaves NIXHOOKS_FAILED untouched when the entry succeeds" {
  NIXHOOKS_FAILED=0
  NIXHOOKS_FILES=("a.sh")
  run_hook myhook '\.sh$' '^$' 1 0 true
  [ "$NIXHOOKS_FAILED" -eq 0 ]
}

@test "nixhooks_summary exits 0 when nothing failed" {
  NIXHOOKS_FAILED=0
  run nixhooks_summary
  [ "$status" -eq 0 ]
}

@test "nixhooks_summary exits 1 when a hook failed" {
  NIXHOOKS_FAILED=1
  run nixhooks_summary
  [ "$status" -eq 1 ]
}

# --- file discovery --------------------------------------------------------

@test "precommit file collection works with no HEAD yet (initial commit)" {
  echo hi >a.txt
  git add a.txt
  nixhooks_collect_precommit_files
  [ "${#NIXHOOKS_FILES[@]}" -eq 1 ]
  [ "${NIXHOOKS_FILES[0]}" = "a.txt" ]
}

@test "precommit file collection diffs against HEAD once it exists" {
  echo hi >a.txt
  git add a.txt
  git commit -q -m init
  echo bye >b.txt
  git add b.txt
  nixhooks_collect_precommit_files
  [ "${#NIXHOOKS_FILES[@]}" -eq 1 ]
  [ "${NIXHOOKS_FILES[0]}" = "b.txt" ]
}

@test "repo file collection lists every tracked file" {
  echo hi >a.txt
  echo bye >b.txt
  git add a.txt b.txt
  git commit -q -m init
  nixhooks_collect_repo_files
  [ "${#NIXHOOKS_FILES[@]}" -eq 2 ]
}

@test "prepush file collection falls back to the whole repo for a new branch (zero remote sha)" {
  echo hi >a.txt
  git add a.txt
  git commit -q -m init
  local_sha="$(git rev-parse HEAD)"
  zero_sha="0000000000000000000000000000000000000000"
  nixhooks_collect_prepush_files "$zero_sha" "$local_sha"
  [ "${#NIXHOOKS_FILES[@]}" -eq 1 ]
  [ "${NIXHOOKS_FILES[0]}" = "a.txt" ]
}

@test "prepush file collection diffs between two known shas" {
  echo hi >a.txt
  git add a.txt
  git commit -q -m init
  base_sha="$(git rev-parse HEAD)"
  echo bye >b.txt
  git add b.txt
  git commit -q -m second
  head_sha="$(git rev-parse HEAD)"
  nixhooks_collect_prepush_files "$base_sha" "$head_sha"
  [ "${#NIXHOOKS_FILES[@]}" -eq 1 ]
  [ "${NIXHOOKS_FILES[0]}" = "b.txt" ]
}
