# shellcheck shell=bash

while read -r local_ref local_sha remote_ref remote_sha; do
  # local_ref/remote_ref are part of git's pre-push stdin protocol but unused
  # here; shellcheck disable=SC2034 keeps the field positions self-documenting.
  : "$local_ref" "$remote_ref"
  # local_sha all-zero: this is a ref *deletion* (e.g. `git push origin :branch`),
  # nothing local to check.
  [[ "$local_sha" =~ ^0+$ ]] && continue

  nixhooks_collect_prepush_files "$remote_sha" "$local_sha"
  nixhooks_generated_hooks
done

nixhooks_summary
