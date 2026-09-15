# Unit tests for lib/hooks-runtime.sh 

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

# run_hook: file matching / exclude / always_run / pass_filenames ------

@test "run_hook passes only files matching 'files' to the entry" {
  NIXHOOKS_FILES=("a.sh" "b.txt")
  run_hook myhook '\.sh$' '^$' 1 0 "$RECORDER" ''
  run cat "$RECORD_FILE"
  [[ "$output" == *"a.sh"* ]]
  [[ "$output" != *"b.txt"* ]]
}

@test "run_hook excludes files matching 'exclude'" {
  NIXHOOKS_FILES=("a.sh" "vendor/b.sh")
  run_hook myhook '\.sh$' '^vendor/' 1 0 "$RECORDER" ''
  run cat "$RECORD_FILE"
  [[ "$output" == *"a.sh"* ]]
  [[ "$output" != *"vendor/b.sh"* ]]
}

@test "run_hook does not invoke the entry when nothing matches" {
  NIXHOOKS_FILES=("a.txt")
  run_hook myhook '\.sh$' '^$' 1 0 "$RECORDER" ''
  [ ! -e "$RECORD_FILE" ]
}

@test "run_hook with always_run=1 invokes the entry with no files matched" {
  NIXHOOKS_FILES=()
  run_hook myhook '.*' '^$' 1 1 "$RECORDER" ''
  [ -e "$RECORD_FILE" ]
  # $(...) strips the recorder's trailing newline, so this is empty iff no
  # arguments were passed (printf '%s\n' with zero args still emits one blank line).
  [ -z "$(cat "$RECORD_FILE")" ]
}

@test "run_hook with pass_filenames=0 invokes the entry without filenames" {
  NIXHOOKS_FILES=("a.sh")
  run_hook myhook '\.sh$' '^$' 0 0 "$RECORDER" ''
  [ -e "$RECORD_FILE" ]
  [ -z "$(cat "$RECORD_FILE")" ]
}

@test "run_hook appends the collected commit-msg file as a trailing arg" {
  NIXHOOKS_FILES=("/tmp/some/COMMIT_EDITMSG")
  run_hook commitlint '.*' '^$' 1 0 "$RECORDER" '' --edit
  run cat "$RECORD_FILE"
  [[ "$output" == *"--edit"* ]]
  [[ "$output" == *"/tmp/some/COMMIT_EDITMSG"* ]]
}

# run_hook: path_prefix 

@test "run_hook prepends path_prefix to PATH before invoking the entry" {
  local extra_bin_dir="$TEST_REPO/extra_bin"
  mkdir -p "$extra_bin_dir"
  cat >"$extra_bin_dir/sibling-tool" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$extra_bin_dir/sibling-tool"

  local checker="$TEST_REPO/checker.sh"
  cat >"$checker" <<'EOF'
#!/bin/sh
command -v sibling-tool
EOF
  chmod +x "$checker"

  NIXHOOKS_FILES=()
  run run_hook myhook '.*' '^$' 1 1 "$checker" "$extra_bin_dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$extra_bin_dir/sibling-tool"* ]]
}

@test "run_hook does not touch PATH when path_prefix is empty" {
  local checker="$TEST_REPO/checker.sh"
  cat >"$checker" <<'EOF'
#!/bin/sh
command -v sibling-tool
EOF
  chmod +x "$checker"

  NIXHOOKS_FAILED=0
  NIXHOOKS_FILES=()
  run_hook myhook '.*' '^$' 1 1 "$checker" '' || true
  [ "$NIXHOOKS_FAILED" -eq 1 ]
}

# run_hook: SKIP and failure aggregation 

@test "run_hook honors SKIP and never invokes the entry" {
  _nixhooks_skip=("myhook")
  NIXHOOKS_FILES=("a.sh")
  run_hook myhook '\.sh$' '^$' 1 0 "$RECORDER" ''
  [ ! -e "$RECORD_FILE" ]
}

@test "run_hook sets NIXHOOKS_FAILED when the entry fails, without aborting" {
  NIXHOOKS_FAILED=0
  NIXHOOKS_FILES=("a.sh")
  run_hook myhook '\.sh$' '^$' 1 0 false '' || true
  [ "$NIXHOOKS_FAILED" -eq 1 ]
}

@test "run_hook leaves NIXHOOKS_FAILED untouched when the entry succeeds" {
  NIXHOOKS_FAILED=0
  NIXHOOKS_FILES=("a.sh")
  run_hook myhook '\.sh$' '^$' 1 0 true ''
  [ "$NIXHOOKS_FAILED" -eq 0 ]
}

# run_hook: own exit status 

@test "run_hook itself returns nonzero when the entry fails" {
  NIXHOOKS_FILES=("a.sh")
  run run_hook myhook '\.sh$' '^$' 1 0 false ''
  [ "$status" -eq 1 ]
}

@test "run_hook itself returns zero when the entry succeeds" {
  NIXHOOKS_FILES=("a.sh")
  run run_hook myhook '\.sh$' '^$' 1 0 true ''
  [ "$status" -eq 0 ]
}

# run_hook_parallel / nixhooks_wait_parallel 
#
# NOTE: none of these wrap run_hook_parallel or nixhooks_wait_parallel in
# bats' `run` (or `$(...)`) helper -- both fork a subshell, and a subshell
# cannot `wait` on a background job that was started by its parent, since
# process parentage doesn't follow the fork. Output is captured via plain
# redirection instead, which doesn't fork.

@test "run_hook_parallel + nixhooks_wait_parallel runs every job to completion" {
  local recorder_b="$TEST_REPO/.recorder-b.sh"
  local record_file_b="$TEST_REPO/.record-b"
  cat >"$recorder_b" <<EOF
#!/bin/sh
printf '%s\n' "\$@" >"$record_file_b"
EOF
  chmod +x "$recorder_b"

  NIXHOOKS_FILES=("a.sh")
  run_hook_parallel jobA '\.sh$' '^$' 1 0 "$RECORDER" ''
  run_hook_parallel jobB '\.sh$' '^$' 1 0 "$recorder_b" ''
  nixhooks_wait_parallel

  run cat "$RECORD_FILE"
  [[ "$output" == *"a.sh"* ]]
  run cat "$record_file_b"
  [[ "$output" == *"a.sh"* ]]
}

@test "nixhooks_wait_parallel sets NIXHOOKS_FAILED when any job fails" {
  NIXHOOKS_FAILED=0
  NIXHOOKS_FILES=()
  run_hook_parallel jobA '.*' '^$' 1 1 true ''
  run_hook_parallel jobB '.*' '^$' 1 1 false ''
  nixhooks_wait_parallel
  [ "$NIXHOOKS_FAILED" -eq 1 ]
}

@test "nixhooks_wait_parallel does not clear a pre-existing NIXHOOKS_FAILED when every job succeeds" {
  NIXHOOKS_FAILED=1
  NIXHOOKS_FILES=()
  run_hook_parallel jobA '.*' '^$' 1 1 true ''
  nixhooks_wait_parallel
  [ "$NIXHOOKS_FAILED" -eq 1 ]
}

@test "nixhooks_wait_parallel flushes output in launch order regardless of completion order" {
  local slow="$TEST_REPO/.slow.sh"
  cat >"$slow" <<'EOF'
#!/bin/sh
sleep 0.3
echo SLOW
EOF
  chmod +x "$slow"

  local fast="$TEST_REPO/.fast.sh"
  cat >"$fast" <<'EOF'
#!/bin/sh
echo FAST
EOF
  chmod +x "$fast"

  local wait_output="$TEST_REPO/.wait-output"
  NIXHOOKS_FILES=()
  run_hook_parallel slowjob '.*' '^$' 1 1 "$slow" ''
  run_hook_parallel fastjob '.*' '^$' 1 1 "$fast" ''
  nixhooks_wait_parallel >"$wait_output" 2>&1

  run cat "$wait_output"
  [[ "$output" == *SLOW*FAST* ]]
}

@test "run_hook_parallel honors the same files/exclude matching as run_hook" {
  NIXHOOKS_FILES=("a.sh" "vendor/b.sh")
  run_hook_parallel myhook '\.sh$' '^vendor/' 1 0 "$RECORDER" ''
  nixhooks_wait_parallel
  run cat "$RECORD_FILE"
  [[ "$output" == *"a.sh"* ]]
  [[ "$output" != *"vendor/b.sh"* ]]
}

# set -e / errexit interaction 
#
# The generated scripts run under `set -euo pipefail`. This is the property
# lib/script-gen.nix's `|| true` guard on serial run_hook calls exists for:
# a failing hook must not abort the rest of the script.

@test "a failing hook does not abort a script running under set -euo pipefail" {
  run bash -c '
    set -euo pipefail
    source "'"$NIXHOOKS_LIB"'/hooks-runtime.sh"
    NIXHOOKS_FILES=("a.sh")
    run_hook first "\.sh\$" "^\$" 1 0 false "" || true
    run_hook second "\.sh\$" "^\$" 1 0 true "" || true
    nixhooks_summary
  '
  [ "$status" -eq 1 ]
  [[ "$output" == *"nixhooks: FAIL  first"* ]]
  [[ "$output" == *"nixhooks: run   second"* ]]
  [[ "$output" == *"one or more hooks failed"* ]]
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

# file discovery 

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

@test "commitmsg file collection sets NIXHOOKS_FILES to the given message file path" {
  local msg_file="$TEST_REPO/COMMIT_EDITMSG"
  echo "feat: add thing" >"$msg_file"
  nixhooks_collect_commitmsg_files "$msg_file"
  [ "${#NIXHOOKS_FILES[@]}" -eq 1 ]
  [ "${NIXHOOKS_FILES[0]}" = "$msg_file" ]
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

@test "prepush file collection excludes files deleted between the two shas" {
  echo hi >a.txt
  echo bye >deleteme.txt
  git add a.txt deleteme.txt
  git commit -q -m init
  base_sha="$(git rev-parse HEAD)"
  git rm -q deleteme.txt
  git commit -q -m "delete file"
  head_sha="$(git rev-parse HEAD)"
  nixhooks_collect_prepush_files "$base_sha" "$head_sha"
  [ "${#NIXHOOKS_FILES[@]}" -eq 0 ]
}
