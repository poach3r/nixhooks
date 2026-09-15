{lib}: let
  hookCall = hook: let
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
  in "  run_hook ${lib.concatMapStringsSep " " lib.escapeShellArg args}";

  genCalls = hooks: lib.concatMapStringsSep "\n" hookCall (lib.attrValues hooks);

  hooksForStage = stage: hooks: lib.filterAttrs (_: h: builtins.elem stage h.stages) hooks;
in {
  # calls for a single stage
  genStageCalls = stage: hooks: genCalls (hooksForStage stage hooks);

  # calls for CI, commit-msg hooks are filtered out
  genAllCalls = hooks:
    genCalls (lib.filterAttrs (_: h: builtins.any (s: s != "commit-msg") h.stages) hooks);
}
