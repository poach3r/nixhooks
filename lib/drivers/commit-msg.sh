# shellcheck shell=bash

nixhooks_collect_commitmsg_files "$1"
nixhooks_generated_hooks
nixhooks_summary
