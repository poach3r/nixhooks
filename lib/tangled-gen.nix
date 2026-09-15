{lib}: let
  defaultTangled = {
    enable = false;
    attr = "run-hooks";
    flake = true;
    when = [
      {
        event = ["push" "pull_request"];
        branch = ["main"];
      }
    ];
    engine = "microvm";
    image = "nixos";
  };

  validEngines = ["microvm" "nixery"];

  normalizeTangled = raw: let
    merged = defaultTangled // raw;
  in
    assert lib.assertMsg (builtins.isBool merged.enable)
    "nixhooks: tangled.enable must be a bool";
    assert lib.assertMsg (merged.attr != "")
    "nixhooks: tangled.attr must be a non-empty string";
    assert lib.assertMsg (builtins.elem merged.engine validEngines)
    "nixhooks: tangled.engine must be one of: ${builtins.concatStringsSep ", " validEngines}";
    assert lib.assertMsg (builtins.isList merged.when && merged.when != [])
    "nixhooks: tangled.when must be a non-empty list of trigger conditions"; merged;

  engineFields = cfg:
    if cfg.engine == "microvm"
    then {inherit (cfg) image;}
    else {};

  mkManifest = cfg: let
    buildCmd =
      if cfg.flake
      then "nix run .#${cfg.attr}"
      else "nix-build -A ${cfg.attr} && ./result/bin/${cfg.attr}";
  in
    {
      inherit (cfg) when engine;
    }
    // engineFields cfg
    // {
      steps = [
        {
          name = "nixhooks: ${cfg.attr}";
          command = buildCmd;
        }
      ];
    };

  # JSON is valid YAML for some fucking reason so we can just write that
  mkPipelineText = raw: let
    cfg = normalizeTangled raw;
  in
    builtins.toJSON (mkManifest cfg);
in {
  inherit defaultTangled normalizeTangled mkManifest mkPipelineText;
}
