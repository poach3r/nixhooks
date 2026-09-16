{lib}: let
  mkArgs = hook: let
    args =
      [
        hook.name
        hook.files
        hook.exclude
        (
          if hook.pass_filenames
          then "1"
          else "0"
        )
        (
          if hook.always_run
          then "1"
          else "0"
        )
        hook.entry
        (lib.makeBinPath hook.path)
      ]
      ++ hook.args;
  in
    args;

  # serial calls are guarded with `|| true`, an ungaurded call would abort the
  # script on the first failure
  serialCall = hook: "  run_hook ${lib.concatMapStringsSep " " lib.escapeShellArg (mkArgs hook)} || true";

  # run_hook_parallel never fails, so there's nothing to guard
  parallelCall = hook: "  run_hook_parallel ${lib.concatMapStringsSep " " lib.escapeShellArg (mkArgs hook)}";

  precomputeCall = pair: "  nixhooks_precompute_matches ${lib.escapeShellArg pair.files} ${lib.escapeShellArg pair.exclude}";

  # always_run hooks skip matching entirely, so they need no precompute.
  genPrecomputeCalls = hooks: let
    pairs =
      lib.unique
      (map (h: {inherit (h) files exclude;})
        (builtins.filter (h: !h.always_run) hooks));
  in
    map precomputeCall pairs;

  # partitions an already-stage-filtered hook set into a parallel batch
  # followed by a nixhooks_wait_parallel barrier and then the serial tail
  genPartitionedCalls = hooks: let
    ordered = lib.attrValues hooks;
    parallelHooks = builtins.filter (h: h.parallel) ordered;
    serialHooks = builtins.filter (h: !h.parallel) ordered;
    lines =
      genPrecomputeCalls ordered
      ++ map parallelCall parallelHooks
      ++ lib.optional (parallelHooks != []) "  nixhooks_wait_parallel"
      ++ map serialCall serialHooks;
  in
    lib.concatStringsSep "\n" lines;

  hooksForStage = stage: hooks: lib.filterAttrs (_: h: builtins.elem stage h.stages) hooks;
in {
  # calls for a single stage
  genStageCalls = stage: hooks: genPartitionedCalls (hooksForStage stage hooks);

  # calls for CI, commit-msg hooks are filtered out
  genAllCalls = hooks:
    genPartitionedCalls (lib.filterAttrs (_: h: builtins.any (s: s != "commit-msg") h.stages) hooks);
}
