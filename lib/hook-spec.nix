{lib}: let
  defaultHook = {
    enable = true;
    args = [];
    files = ".*";
    exclude = "^$"; # matches only the empty string, i.e. excludes nothing
    stages = ["pre-commit"];
    pass_filenames = true;
    always_run = false;
    path = []; # extra packages whose bin/ dirs are prepended to PATH for entry
    serial = true;
    required = true; # if false a failing hook warns instead of blocking the git action
    script = null; # bash body run in place of entry, see lib/script-gen.nix
  };

  validStages = [
    "pre-commit"
    "pre-push"
    "commit-msg"
  ];

  # names are passed through as shell-escaped string arguments but must exclude ',' and whitespace/control characters
  isValidName = name: builtins.match "[A-Za-z0-9_.-]+" name != null;

  normalizeHook = name: rawHook:
    assert lib.assertMsg (isValidName name)
    "nixhooks: hook name '${name}' must match [A-Za-z0-9_.-]+ (no commas or whitespace)"; let
      # fallback defaults to the entry's filename, looked up on PATH when entry is missing
      merged =
        defaultHook
        // {
          fallback =
            if rawHook ? entry
            then baseNameOf rawHook.entry
            else null;
        }
        // rawHook
        // {inherit name;};
      hasEntry = merged.entry or "" != "";
      hasScript = merged.script != null;
    in
      assert lib.assertMsg (hasEntry != hasScript)
      "nixhooks: hook '${name}' must set exactly one of a non-empty 'entry' or 'script'";
      assert lib.assertMsg (!hasScript || (builtins.isString merged.script && merged.script != ""))
      "nixhooks: hook '${name}' 'script' must be a non-empty string";
      assert lib.assertMsg (!hasScript || merged.fallback == null)
      "nixhooks: hook '${name}' 'fallback' doesn't apply to 'script' hooks, use nixhooks_tool instead";
      assert lib.assertMsg (builtins.all (s: builtins.elem s validStages) merged.stages)
      "nixhooks: hook '${name}' has invalid stage(s) in ${builtins.toJSON merged.stages}; valid stages are: ${builtins.concatStringsSep ", " validStages}";
      assert lib.assertMsg (
        merged.stages != []
      ) "nixhooks: hook '${name}' must declare at least one stage";
      assert lib.assertMsg (builtins.isList merged.path)
      "nixhooks: hook '${name}' 'path' must be a list of packages";
      assert lib.assertMsg (builtins.isBool merged.serial)
      "nixhooks: hook '${name}' 'serial' must be a bool";
      assert lib.assertMsg (builtins.isBool merged.required)
      "nixhooks: hook '${name}' 'required' must be a bool";
      assert lib.assertMsg (merged.fallback == null || (builtins.isString merged.fallback && merged.fallback != ""))
      "nixhooks: hook '${name}' 'fallback' must be null or a non-empty string"; merged;
in {
  inherit defaultHook normalizeHook;
  normalizeHooks = hooks: lib.mapAttrs normalizeHook (lib.filterAttrs (_: h: h.enable or true) hooks);
}
