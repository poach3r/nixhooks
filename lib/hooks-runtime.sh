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

# Args: name files_regex exclude_regex pass_filenames(0|1) always_run(0|1) entry path_prefix [extra_args...]
# path_prefix (possibly empty) is prepended to PATH so entry can find sibling
# binaries it dispatches to internally. Matches against $NIXHOOKS_FILES
# populated by the caller before invocation
run_hook() {
	local name="$1" files_re="$2" exclude_re="$3" pass_filenames="$4" always_run="$5" entry="$6" path_prefix="$7"
	shift 7
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

	local run_path="$PATH"
	[[ -n "$path_prefix" ]] && run_path="$path_prefix:$PATH"

	if ! PATH="$run_path" "${cmd[@]}"; then
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
		done < <(git diff --name-only -z "$remote_sha" "$local_sha")
	fi
}

# partial-staging isolation
# Hooks run against a throwaway worktree checked out from what's staged
NIXHOOKS_WORKTREE_DIR=""
NIXHOOKS_STAGED_TREE=""
NIXHOOKS_REPO_ROOT=""

nixhooks_worktree_cleanup() {
	if [[ -n "$NIXHOOKS_WORKTREE_DIR" ]]; then
		git worktree remove --force "$NIXHOOKS_WORKTREE_DIR" 2>/dev/null || rm -rf "$NIXHOOKS_WORKTREE_DIR"
		NIXHOOKS_WORKTREE_DIR=""
	fi
}

# Must run after nixhooks_collect_precommit_files (uses the real repo's index/HEAD).
nixhooks_enter_staged_worktree() {
	NIXHOOKS_REPO_ROOT="$(pwd)"
	NIXHOOKS_STAGED_TREE="$(git write-tree)"

	local commit
	if git rev-parse --verify -q HEAD >/dev/null; then
		commit="$(git commit-tree "$NIXHOOKS_STAGED_TREE" -p HEAD -m "nixhooks: staged snapshot")"
	else
		commit="$(git commit-tree "$NIXHOOKS_STAGED_TREE" -m "nixhooks: staged snapshot")"
	fi

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
	git worktree add --quiet --detach "$NIXHOOKS_WORKTREE_DIR" "$commit"
	cd "$NIXHOOKS_WORKTREE_DIR" || exit 1
}

# Re-stages anything a hook mutated inside the isolated worktree. If the real
# working tree file was identical to what was staged beforehand also updates
# the real working tree file
nixhooks_reconcile_worktree() {
	cd "$NIXHOOKS_REPO_ROOT" || exit 1
	[[ -n "$NIXHOOKS_SAVED_GIT_INDEX_FILE" ]] && export GIT_INDEX_FILE="$NIXHOOKS_SAVED_GIT_INDEX_FILE"
	[[ -n "$NIXHOOKS_SAVED_GIT_DIR" ]] && export GIT_DIR="$NIXHOOKS_SAVED_GIT_DIR"
	[[ -n "$NIXHOOKS_SAVED_GIT_WORK_TREE" ]] && export GIT_WORK_TREE="$NIXHOOKS_SAVED_GIT_WORK_TREE"

	local f mode orig_blob new_hash real_blob
	for f in "${NIXHOOKS_FILES[@]}"; do
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
