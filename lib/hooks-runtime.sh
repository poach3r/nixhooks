# shellcheck shell=bash
# nixhooks runtime library

NIXHOOKS_FAILED=0
NIXHOOKS_FILES=()

NIXHOOKS_PARALLEL_PIDS=()
NIXHOOKS_PARALLEL_NAMES=()
NIXHOOKS_PARALLEL_LOGS=()
NIXHOOKS_PARALLEL_JOB_DIR=""

# files_re/exclude_re pair -> path of a file holding the matched filenames.
# A file, not a variable, because $(...) strips embedded NULs and the
# matches are NUL-delimited. Lets hooks that share a pattern reuse one match
# instead of re-scanning $NIXHOOKS_FILES each; see nixhooks_match_cache_file.
# Parallel arrays, not an associative array, for bash 3.2.
NIXHOOKS_MATCH_KEYS=()
NIXHOOKS_MATCH_PATHS=()
NIXHOOKS_MATCH_CACHE_DIR=""
NIXHOOKS_MATCH_FILE=""

_nixhooks_skip_list() {
	IFS=',' read -ra _nixhooks_skip <<<"${SKIP:-}"
}
_nixhooks_skip_list

should_skip() {
	local name="$1" s
	# bash < 4.4 treats an empty array as unbound under set -u
	for s in ${_nixhooks_skip[@]+"${_nixhooks_skip[@]}"}; do
		[[ "$s" == "$name" ]] && return 0
	done
	return 1
}

# Sets NIXHOOKS_MATCH_FILE to the cached NUL-delimited $NIXHOOKS_FILES
# entries matching files_re and not exclude_re ("^$" means exclude nothing).
# A global, not stdout, since a $(...) subshell would lose the cache entry.
nixhooks_match_cache_file() {
	local files_re="$1" exclude_re="$2"
	local key="${files_re}"$'\x1e'"${exclude_re}"
	local i n="${#NIXHOOKS_MATCH_KEYS[@]}"

	for ((i = 0; i < n; i++)); do
		if [[ "${NIXHOOKS_MATCH_KEYS[i]}" == "$key" ]]; then
			NIXHOOKS_MATCH_FILE="${NIXHOOKS_MATCH_PATHS[i]}"
			return 0
		fi
	done

	[[ -z "$NIXHOOKS_MATCH_CACHE_DIR" ]] && NIXHOOKS_MATCH_CACHE_DIR="$(mktemp -d)"
	local cache_file="$NIXHOOKS_MATCH_CACHE_DIR/$n"
	if ((${#NIXHOOKS_FILES[@]} == 0)); then
		: >"$cache_file"
	elif [[ "$exclude_re" != '^$' ]]; then
		printf '%s\0' "${NIXHOOKS_FILES[@]}" |
			{ grep -zE -- "$files_re" || true; } |
			{ grep -zvE -- "$exclude_re" || true; } \
				>"$cache_file"
	else
		printf '%s\0' "${NIXHOOKS_FILES[@]}" |
			{ grep -zE -- "$files_re" || true; } \
				>"$cache_file"
	fi
	NIXHOOKS_MATCH_KEYS+=("$key")
	NIXHOOKS_MATCH_PATHS+=("$cache_file")
	NIXHOOKS_MATCH_FILE="$cache_file"
}

# Warms the match cache for a pair before any hooks run, so parallel jobs
# (forked copies of this process) inherit it instead of each recomputing
# their own. Called by generated scripts; see script-gen.nix.
nixhooks_precompute_matches() {
	nixhooks_match_cache_file "$1" "$2"
}

# For `script` hooks: prints the store binary $1 if present, else $2's path
# on PATH. Fails with 127 if neither exists.
nixhooks_tool() {
	if [[ -x "$1" ]]; then
		printf '%s\n' "$1"
	elif ! command -v -- "$2"; then
		echo "nixhooks: $2 not found" >&2
		return 127
	fi
}

# Reports a failed hook. Only a required hook sets NIXHOOKS_FAILED and
# returns nonzero.
_nixhooks_hook_failed() {
	local name="$1" required="$2" reason="$3"
	if [[ "$required" == 1 ]]; then
		echo "nixhooks: FAIL  $name${reason:+ ($reason)}"
		NIXHOOKS_FAILED=1
		return 1
	fi
	echo "nixhooks: WARN  $name (${reason:-failed}, not required)"
}

# Args: name files_regex exclude_regex pass_filenames(0|1) always_run(0|1) required(0|1) fallback entry path_prefix [extra_args...]
# fallback (possibly empty) is looked up on PATH when entry can't be found.
# path_prefix (possibly empty) is prepended to PATH so entry can find sibling
# binaries it dispatches to internally. Matches against $NIXHOOKS_FILES
# populated by the caller before invocation
run_hook() {
	local name="$1" files_re="$2" exclude_re="$3" pass_filenames="$4" always_run="$5" required="$6" fallback="$7" entry="$8" path_prefix="$9"
	shift 9

	if should_skip "$name"; then
		echo "nixhooks: skip  $name (SKIP)"
		return 0
	fi

	local matched=() f
	if [[ "$always_run" != 1 ]]; then
		nixhooks_match_cache_file "$files_re" "$exclude_re"
		while IFS= read -r -d '' f; do
			matched+=("$f")
		done <"$NIXHOOKS_MATCH_FILE"
		if [[ ${#matched[@]} -eq 0 ]]; then
			echo "nixhooks: skip  $name (no matching files)"
			return 0
		fi
	fi

	if command -v -- "$entry" >/dev/null; then
		echo "nixhooks: run   $name"
	elif [[ -n "$fallback" ]] && entry="$(command -v -- "$fallback")"; then
		echo "nixhooks: run   $name (PATH: $entry)"
	else
		_nixhooks_hook_failed "$name" "$required" "${fallback:-${entry##*/}} not found"
		return
	fi

	# "$@", not a copied array: empty "$@" is safe under set -u on bash < 4.4
	local cmd=("$entry" "$@")
	if [[ "$pass_filenames" == 1 && "$always_run" != 1 ]]; then
		cmd+=("${matched[@]}")
	fi

	local run_path="$PATH"
	[[ -n "$path_prefix" ]] && run_path="$path_prefix:$PATH"

	if ! PATH="$run_path" "${cmd[@]}"; then
		_nixhooks_hook_failed "$name" "$required" ""
		return
	fi
	return 0
}

# Args: same as run_hook.
run_hook_parallel() {
	local name="$1"
	if [[ -z "$NIXHOOKS_PARALLEL_JOB_DIR" ]]; then
		NIXHOOKS_PARALLEL_JOB_DIR="$(mktemp -d)"
	fi
	local logfile="$NIXHOOKS_PARALLEL_JOB_DIR/$name.log"
	run_hook "$@" >"$logfile" 2>&1 &
	NIXHOOKS_PARALLEL_PIDS+=("$!")
	NIXHOOKS_PARALLEL_NAMES+=("$name")
	NIXHOOKS_PARALLEL_LOGS+=("$logfile")
}

# Waits for every job launched via run_hook_parallel flushing each one's
# buffered output once it finishes and folding a nonzero exit into
# NIXHOOKS_FAILED. Always exits 0.
nixhooks_wait_parallel() {
	local i st content
	for i in "${!NIXHOOKS_PARALLEL_PIDS[@]}"; do
		st=0
		wait "${NIXHOOKS_PARALLEL_PIDS[$i]}" || st=$?
		content="$(<"${NIXHOOKS_PARALLEL_LOGS[$i]}")"
		[[ -n "$content" ]] && printf '%s\n' "$content"
		[[ "$st" -ne 0 ]] && NIXHOOKS_FAILED=1
	done
	rm -f ${NIXHOOKS_PARALLEL_LOGS[@]+"${NIXHOOKS_PARALLEL_LOGS[@]}"}
	NIXHOOKS_PARALLEL_PIDS=()
	NIXHOOKS_PARALLEL_NAMES=()
	NIXHOOKS_PARALLEL_LOGS=()
	[[ -n "$NIXHOOKS_PARALLEL_JOB_DIR" ]] && rmdir "$NIXHOOKS_PARALLEL_JOB_DIR" 2>/dev/null
	NIXHOOKS_PARALLEL_JOB_DIR=""
}

nixhooks_summary() {
	[[ -n "$NIXHOOKS_MATCH_CACHE_DIR" ]] && rm -rf "$NIXHOOKS_MATCH_CACHE_DIR"
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

nixhooks_collect_commitmsg_files() {
	NIXHOOKS_FILES=("$1")
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
		done < <(git diff --name-only --diff-filter=ACM -z "$remote_sha" "$local_sha")
	fi
}

# Working-tree isolation
NIXHOOKS_WORKTREE_DIR=""
NIXHOOKS_STAGED_TREE=""
NIXHOOKS_REPO_ROOT=""

nixhooks_worktree_cleanup() {
	if [[ -n "$NIXHOOKS_WORKTREE_DIR" ]]; then
		git worktree remove --force "$NIXHOOKS_WORKTREE_DIR" 2>/dev/null || rm -rf "$NIXHOOKS_WORKTREE_DIR"
		NIXHOOKS_WORKTREE_DIR=""
	fi
}

# Checks out commit $1 into a throwaway detached worktree and cd's into it.
nixhooks_enter_worktree() {
	NIXHOOKS_REPO_ROOT="$(pwd)"

	# git invokes hooks with GIT_INDEX_FILE. Once we cd into the
	# throwaway worktree below, that stale relative path would be misresolved
	# against the new cwd/gitdir, so we save and clear them here
	NIXHOOKS_SAVED_GIT_INDEX_FILE="${GIT_INDEX_FILE-}"
	NIXHOOKS_SAVED_GIT_DIR="${GIT_DIR-}"
	NIXHOOKS_SAVED_GIT_WORK_TREE="${GIT_WORK_TREE-}"
	unset GIT_INDEX_FILE GIT_DIR GIT_WORK_TREE

	NIXHOOKS_WORKTREE_DIR="$(mktemp -d)"
	rmdir "$NIXHOOKS_WORKTREE_DIR" # git worktree add creates the dir itself
	trap nixhooks_worktree_cleanup EXIT
	git worktree add --quiet --detach "$NIXHOOKS_WORKTREE_DIR" "$1"
	cd "$NIXHOOKS_WORKTREE_DIR" || exit 1
}

nixhooks_return_to_repo() {
	cd "$NIXHOOKS_REPO_ROOT" || exit 1
	# `if`, not `&&`: a false `[[ ]]` as the last command makes this return 1,
	# which aborts the hook under `set -e`.
	if [[ -n "$NIXHOOKS_SAVED_GIT_INDEX_FILE" ]]; then export GIT_INDEX_FILE="$NIXHOOKS_SAVED_GIT_INDEX_FILE"; fi
	if [[ -n "$NIXHOOKS_SAVED_GIT_DIR" ]]; then export GIT_DIR="$NIXHOOKS_SAVED_GIT_DIR"; fi
	if [[ -n "$NIXHOOKS_SAVED_GIT_WORK_TREE" ]]; then export GIT_WORK_TREE="$NIXHOOKS_SAVED_GIT_WORK_TREE"; fi
}

nixhooks_enter_staged_worktree() {
	NIXHOOKS_STAGED_TREE="$(git write-tree)"

	local commit
	if git rev-parse --verify -q HEAD >/dev/null; then
		commit="$(git commit-tree "$NIXHOOKS_STAGED_TREE" -p HEAD -m "nixhooks: staged snapshot")"
	else
		commit="$(git commit-tree "$NIXHOOKS_STAGED_TREE" -m "nixhooks: staged snapshot")"
	fi

	nixhooks_enter_worktree "$commit"
}

nixhooks_leave_worktree() {
	nixhooks_return_to_repo
	nixhooks_worktree_cleanup
}

# Re-stages anything a hook mutated inside the isolated worktree
nixhooks_reconcile_worktree() {
	nixhooks_return_to_repo

	local f mode orig_blob new_hash real_blob
	# empty for deletion-only commits
	for f in ${NIXHOOKS_FILES[@]+"${NIXHOOKS_FILES[@]}"}; do
		orig_blob="$(git rev-parse "$NIXHOOKS_STAGED_TREE:$f" 2>/dev/null)" || continue
		new_hash="$(git hash-object "$NIXHOOKS_WORKTREE_DIR/$f" 2>/dev/null)" || continue
		[[ "$new_hash" == "$orig_blob" ]] && continue # hook didn't touch this file

		new_hash="$(git hash-object -w "$NIXHOOKS_WORKTREE_DIR/$f")"
		mode="$(git ls-tree "$NIXHOOKS_STAGED_TREE" -- "$f" | cut -d' ' -f1)"

		real_blob="$(git hash-object "$f" 2>/dev/null || true)"
		if [[ "$real_blob" == "$orig_blob" ]]; then
			cp "$NIXHOOKS_WORKTREE_DIR/$f" "$f"
		fi

		git update-index --cacheinfo "$mode,$new_hash,$f"
		echo "nixhooks: re-staged $f (modified by a hook)"
	done

	nixhooks_worktree_cleanup
}
