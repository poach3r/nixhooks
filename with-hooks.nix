{nixpkgs}: {
  hooks ? {}, # {<system> = {...} // {settings ? {tangled, githubActions, parallel};};}
  # `hooks` is keyed by system (see lib/hook-spec.nix for per-hook fields);
  # each system's attrset may carry its own `settings`
  ...
} @ args: let
  outputs = builtins.removeAttrs args ["hooks"];
  systems = builtins.attrNames hooks;

  systemHooks = system: builtins.removeAttrs hooks.${system} ["settings"];
  systemSettings = system: hooks.${system}.settings or {};

  mergeSystem = acc: system: let
    pkgs = import nixpkgs {inherit system;};
    base = import ./lib {inherit pkgs;};

    hookResult = base.mkHooks {
      hooks = systemHooks system;
      settings = systemSettings system;
    };
    hookApps = hookResult.apps;
    hookPackages = hookResult.packages;

    mergedDefaultShell =
      hookResult.wrapShell (acc.devShells.${system}.default or (pkgs.mkShell {}));
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
in
  # deprecated: the old top-level `nixhooks = {hooks; settings;}` argument
  assert nixpkgs.lib.assertMsg (!(args ? nixhooks))
  "nixhooks: the top-level `nixhooks` argument to `withHooks` has been removed; define hooks under `hooks.<system>` instead, with settings at `hooks.<system>.settings`";
    builtins.foldl' mergeSystem outputs systems
