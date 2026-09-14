{pkgs}: let
  lib = pkgs.lib;

  hookSpec = import ./hook-spec.nix {inherit lib;};
  scriptGen = import ./script-gen.nix {inherit lib;};

  runtimeLib = builtins.readFile ./hooks-runtime.sh;
  driverPreCommit = builtins.readFile ./drivers/pre-commit.sh;
  driverPrePush = builtins.readFile ./drivers/pre-push.sh;
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
    pkgs.writeShellApplication {
      inherit name;
      text = ''
        ${marker}
        ${runtimeLib}
        ${genFunction calls}
        ${driver}
      '';
    };

  # hooks: attrset of name -> hook config, see lib/hook-spec.nix for fields.
  mkHooks = {hooks}: let
    normalized = hookSpec.normalizeHooks hooks;

    preCommitHook = mkStageScript "pre-commit-hook" driverPreCommit (
      scriptGen.genStageCalls "pre-commit" normalized
    );
    prePushHook = mkStageScript "pre-push-hook" driverPrePush (
      scriptGen.genStageCalls "pre-push" normalized
    );
    runHooks = mkStageScript "run-hooks" driverRunHooks (scriptGen.genAllCalls normalized);

    installHooks = pkgs.writeShellApplication {
      name = "install-hooks";
      text = ''
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
      '';
    };
  in {
    pre-commit-hook = preCommitHook;
    pre-push-hook = prePushHook;
    run-hooks = runHooks;
    install-hooks = installHooks;
  };
in {
  inherit mkHooks;
  inherit (hookSpec) normalizeHooks normalizeHook defaultHook;
}
