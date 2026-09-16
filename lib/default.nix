{pkgs}: let
  inherit (pkgs) lib;

  hookSpec = import ./hook-spec.nix {inherit lib;};
  scriptGen = import ./script-gen.nix {inherit lib;};
  tangledGen = import ./tangled-gen.nix {inherit lib;};
  githubActionsGen = import ./github-actions-gen.nix {inherit lib;};

  # presets.<name> is built from the caller's own `pkgs` -- for plain
  # `mkHooks` use, so non-flake/single-system callers see no change.
  # presets.<system>.<name> is instead rebuilt for every other system from
  # pkgs.path
  presetSystems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];
  presets =
    (import ./presets.nix {inherit pkgs;})
    // (lib.genAttrs presetSystems
      (system: import ./presets.nix {pkgs = import pkgs.path {inherit system;};}));

  runtimeLib = builtins.readFile ./hooks-runtime.sh;
  driverPreCommit = builtins.readFile ./drivers/pre-commit.sh;
  driverPrePush = builtins.readFile ./drivers/pre-push.sh;
  driverCommitMsg = builtins.readFile ./drivers/commit-msg.sh;
  driverRunHooks = builtins.readFile ./drivers/run-hooks.sh;

  # lets install-hooks tell a nixhooks-installed hook and other hooks apart
  marker = "# managed-by: nixhooks -- do not edit directly";

  genFunction = calls: ''
    nixhooks_generated_hooks() {
    ${
      if calls == ""
      then "  :"
      else calls
    }
    }
  '';

  mkStageScript = name: driver: calls:
    pkgs.writeShellScriptBin name ''
      ${marker}
      set -euo pipefail
      ${runtimeLib}
      ${genFunction calls}
      ${driver}
    '';

  mkHooks = {
    hooks, # attrset of name -> hook config, see lib/hook-spec.nix for fields.
    tangled ? {}, # optional Tangled pipeline config, see lib/tangled-gen.nix for fields.
    githubActions ? {}, # optional GitHub Actions workflow config, see lib/github-actions-gen.nix for fields.
    parallel ? false, # optionally determines if hooks are ran in parallel
  }:
    assert lib.assertMsg (builtins.isBool parallel) "nixhooks: parallel must be a bool"; let
      normalized = hookSpec.normalizeHooks hooks;
      # resolve the top-level switch + per-hook escape hatch into one
      # effective flag before codegen so lib/script-gen.nix only ever
      # reads an already-decided hook.parallel
      scheduled = lib.mapAttrs (_: h: h // {parallel = parallel && !h.serial;}) normalized;
      tangledCfg = tangledGen.normalizeTangled tangled;
      githubActionsCfg = githubActionsGen.normalizeGithubActions githubActions;

      preCommitHook = mkStageScript "pre-commit-hook" driverPreCommit (
        scriptGen.genStageCalls "pre-commit" scheduled
      );
      prePushHook = mkStageScript "pre-push-hook" driverPrePush (
        scriptGen.genStageCalls "pre-push" scheduled
      );
      commitMsgHook = mkStageScript "commit-msg-hook" driverCommitMsg (
        scriptGen.genStageCalls "commit-msg" scheduled
      );
      runHooks = mkStageScript "run-hooks" driverRunHooks (scriptGen.genAllCalls scheduled);

      installHooks = pkgs.writeShellScriptBin "install-hooks" ''
        set -euo pipefail

        if ! git_dir=$(git rev-parse --git-dir 2>/dev/null); then
          echo "install-hooks: not inside a git repository" >&2
          exit 1
        fi

        install_one() {
          local stage="$1" src="$2"
          local dest="$git_dir/hooks/$stage"
          if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
            return 0
          fi
          if [[ -e "$dest" && ! -L "$dest" ]] && ! grep -q ${lib.escapeShellArg marker} "$dest" 2>/dev/null; then
            echo "install-hooks: $dest already exists and is not managed by nixhooks, refusing to overwrite" >&2
            exit 1
          fi
          mkdir -p "$git_dir/hooks"
          ln -sf "$src" "$dest"
          echo "install-hooks: installed $stage -> $src"
        }

        install_one "pre-commit" "${preCommitHook}/bin/pre-commit-hook"
        install_one "pre-push" "${prePushHook}/bin/pre-push-hook"
        install_one "commit-msg" "${commitMsgHook}/bin/commit-msg-hook"
      '';

      tangledPipeline = pkgs.writeText "hooks.yml" ''
        ${marker}
        ${tangledGen.mkPipelineText tangled}
      '';

      genTangledPipeline = pkgs.writeShellScriptBin "gen-tangled-pipeline" ''
        set -euo pipefail

        if ! git_root=$(git rev-parse --show-toplevel 2>/dev/null); then
          echo "gen-tangled-pipeline: not inside a git repository" >&2
          exit 1
        fi

        dest="$git_root/.tangled/workflows/hooks.yml"
        if [[ -e "$dest" ]] && ! grep -q ${lib.escapeShellArg marker} "$dest" 2>/dev/null; then
          echo "gen-tangled-pipeline: $dest already exists and is not managed by nixhooks, refusing to overwrite" >&2
          exit 1
        fi

        mkdir -p "$(dirname "$dest")"
        install -m 0644 ${tangledPipeline} "$dest"
        echo "gen-tangled-pipeline: wrote $dest"
      '';
      githubActionsWorkflow = pkgs.writeText "hooks.yml" ''
        ${marker}
        ${githubActionsGen.mkWorkflowText githubActions}
      '';

      genGithubActionsWorkflow = pkgs.writeShellScriptBin "gen-github-actions-workflow" ''
        set -euo pipefail

        if ! git_root=$(git rev-parse --show-toplevel 2>/dev/null); then
          echo "gen-github-actions-workflow: not inside a git repository" >&2
          exit 1
        fi

        dest="$git_root/.github/workflows/hooks.yml"
        if [[ -e "$dest" ]] && ! grep -q ${lib.escapeShellArg marker} "$dest" 2>/dev/null; then
          echo "gen-github-actions-workflow: $dest already exists and is not managed by nixhooks, refusing to overwrite" >&2
          exit 1
        fi

        mkdir -p "$(dirname "$dest")"
        install -m 0644 ${githubActionsWorkflow} "$dest"
        echo "gen-github-actions-workflow: wrote $dest"
      '';

      hookOutputs =
        {
          pre-commit-hook = preCommitHook;
          pre-push-hook = prePushHook;
          commit-msg-hook = commitMsgHook;
          run-hooks = runHooks;
          install-hooks = installHooks;
        }
        // lib.optionalAttrs tangledCfg.enable {
          tangled-pipeline = tangledPipeline;
          gen-tangled-pipeline = genTangledPipeline;
        }
        // lib.optionalAttrs githubActionsCfg.enable {
          github-actions-workflow = githubActionsWorkflow;
          gen-github-actions-workflow = genGithubActionsWorkflow;
        };
    in
      hookOutputs
      // {
        apps =
          builtins.mapAttrs
          (_: drv: {
            type = "app";
            program = lib.getExe drv;
          })
          (builtins.removeAttrs hookOutputs ["tangled-pipeline" "github-actions-workflow"]);
      };
in {
  inherit mkHooks presets presetSystems;
  inherit (hookSpec) normalizeHooks normalizeHook defaultHook;
  inherit (tangledGen) normalizeTangled defaultTangled;
  inherit (githubActionsGen) normalizeGithubActions defaultGithubActions;
}
