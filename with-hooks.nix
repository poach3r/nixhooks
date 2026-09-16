{nixpkgs}: {
  # DEPRECATED: will be removed in a future release. Use `hooks.<system>`
  # instead, with per-system settings at `hooks.<system>.settings`.
  nixhooks ? null, # {hooks = {<system> = {...};}; settings ? {tangled, githubActions, parallel};}
  hooks ? {}, # {<system> = {...} // {settings ? {tangled, githubActions, parallel};};}
  # `hooks` is keyed by system (see lib/hook-spec.nix for per-hook fields);
  # each system's attrset may carry its own `settings`
  ...
} @ args: let
  legacy = nixhooks != null;

  rawHooks =
    if legacy
    then nixhooks.hooks or {}
    else hooks;
  legacySettings = nixhooks.settings or {};

  outputs = builtins.removeAttrs args ["nixhooks" "hooks"];
  systems = builtins.attrNames rawHooks;

  systemHooks = system:
    if legacy
    then rawHooks.${system}
    else builtins.removeAttrs rawHooks.${system} ["settings"];

  systemSettings = system:
    if legacy
    then legacySettings
    else rawHooks.${system}.settings or {};

  mergeSystem = acc: system: let
    pkgs = import nixpkgs {inherit system;};
    inherit (pkgs) lib;
    base = import ./lib {inherit pkgs;};

    hookResult = base.mkHooks {
      hooks = systemHooks system;
      settings = systemSettings system;
    };
    hookApps = hookResult.apps;
    hookPackages = builtins.removeAttrs hookResult ["apps"];

    userShell = acc.devShells.${system}.default or null;
    mergedDefaultShell = pkgs.mkShell {
      inputsFrom = lib.optional (userShell != null) userShell;
      shellHook =
        (
          if userShell != null
          then userShell.shellHook or ""
          else ""
        )
        + ''

          ${hookResult."install-hooks"}/bin/install-hooks
        '';
    };
  in
    acc
    // {
      apps =
        (acc.apps or {})
        // {${system} = (acc.apps.${system} or {}) // hookApps;};
      packages =
        (acc.packages or {})
        // {${system} = (acc.packages.${system} or {}) // hookPackages;};
      devShells =
        (acc.devShells or {})
        // {
          ${system} =
            (acc.devShells.${system} or {})
            // {default = mergedDefaultShell;};
        };
    };

  result = builtins.foldl' mergeSystem outputs systems;
in
  if legacy
  then
    nixpkgs.lib.warn
    "nixhooks: the top-level `nixhooks` argument to `withHooks` is deprecated and will be removed in a future release; define hooks under `hooks.<system>` instead, with settings at `hooks.<system>.settings`"
    result
  else result
