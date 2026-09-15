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
      merged = defaultHook // rawHook // {inherit name;};
    in
      assert lib.assertMsg (
        merged.entry or "" != ""
      ) "nixhooks: hook '${name}' must set a non-empty 'entry'";
      assert lib.assertMsg (builtins.all (s: builtins.elem s validStages) merged.stages)
      "nixhooks: hook '${name}' has invalid stage(s) in ${builtins.toJSON merged.stages}; valid stages are: ${builtins.concatStringsSep ", " validStages}";
      assert lib.assertMsg (
        merged.stages != []
      ) "nixhooks: hook '${name}' must declare at least one stage";
      assert lib.assertMsg (builtins.isList merged.path)
      "nixhooks: hook '${name}' 'path' must be a list of packages"; merged;
in {
  inherit defaultHook normalizeHook;
  normalizeHooks = hooks: lib.mapAttrs normalizeHook (lib.filterAttrs (_: h: h.enable or true) hooks);
}
