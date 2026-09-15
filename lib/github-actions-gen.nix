{lib}: let
  defaultGithubActions = {
    enable = false;
    attr = "run-hooks";
    flake = true;
    on = {
      push = {branches = ["main"];};
      pull_request = {branches = ["main"];};
    };
    runsOn = "ubuntu-latest";
    cache = true; # nix-community/cache-nix-action, backed by GitHub's own actions/cache
  };

  normalizeGithubActions = raw: let
    merged = defaultGithubActions // raw;
  in
    assert lib.assertMsg (builtins.isBool merged.enable)
    "nixhooks: githubActions.enable must be a bool";
    assert lib.assertMsg (merged.attr != "")
    "nixhooks: githubActions.attr must be a non-empty string";
    assert lib.assertMsg (builtins.isBool merged.flake)
    "nixhooks: githubActions.flake must be a bool";
    assert lib.assertMsg (builtins.isAttrs merged.on && merged.on != {})
    "nixhooks: githubActions.on must be a non-empty attrset of trigger conditions";
    assert lib.assertMsg (merged.runsOn != "")
    "nixhooks: githubActions.runsOn must be a non-empty string";
    assert lib.assertMsg (builtins.isBool merged.cache)
    "nixhooks: githubActions.cache must be a bool"; merged;

  mkManifest = cfg: let
    buildCmd =
      if cfg.flake
      then "nix run .#${cfg.attr}"
      else "nix-build -A ${cfg.attr} && ./result/bin/${cfg.attr}";

    cacheStep = lib.optional cfg.cache {
      uses = "nix-community/cache-nix-action@v7";
      "with" = {
        "primary-key" = "nix-\${{ runner.os }}-\${{ hashFiles('**/*.nix', 'flake.lock', 'npins/sources.json') }}";
        "restore-prefixes-first-match" = "nix-\${{ runner.os }}-";
      };
    };
  in {
    name = "nixhooks";
    inherit (cfg) on;
    jobs.hooks = {
      runs-on = cfg.runsOn;
      steps =
        [
          {uses = "actions/checkout@v4";}
          {uses = "cachix/install-nix-action@v31";}
        ]
        ++ cacheStep
        ++ [
          {
            name = "nixhooks: ${cfg.attr}";
            run = buildCmd;
          }
        ];
    };
  };

  mkWorkflowText = raw: let
    cfg = normalizeGithubActions raw;
  in
    builtins.toJSON (mkManifest cfg);
in {
  inherit defaultGithubActions normalizeGithubActions mkManifest mkWorkflowText;
}
