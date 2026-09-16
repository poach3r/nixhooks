{nixpkgs}: {
  nixhooks, # {hooks = {<system> = {...};}; settings ? {tangled, githubActions, parallel};}
  # `hooks` is keyed by system (see lib/hook-spec.nix for per-hook fields);
  # `settings` is not
  ...
} @ args: let
  inherit (nixhooks) hooks;
  outputs = builtins.removeAttrs args ["nixhooks"];
  settings = nixhooks.settings or {};
  systems = builtins.attrNames hooks;

  mergeSystem = acc: system: let
    pkgs = import nixpkgs {inherit system;};
    inherit (pkgs) lib;
    base = import ./lib {inherit pkgs;};

    hookResult = base.mkHooks {
      hooks = hooks.${system};
      inherit settings;
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
in
  builtins.foldl' mergeSystem outputs systems
