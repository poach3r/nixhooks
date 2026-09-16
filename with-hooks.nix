# Only defined here, not in lib/, because it merges hook-generated outputs
# into an already flake-shaped `outputs` attrset (packages/apps/devShells
# keyed by system) -- a concept that only exists for flakes. lib/default.nix
# stays importable standalone (see ./default.nix) for non-flake use, which
# never sees withHooks.
#
# Builds `pkgs` per system from nixhooks' own pinned `nixpkgs` (this repo's
# own `inputs.nixpkgs`), not the caller's -- so callers never pass `pkgs` (or
# even a `systems` list, since the systems to build are read straight off
# `hooks`'s own keys) here. If that pin drifts from a caller's own nixpkgs,
# they can pin them together with `inputs.nixhooks.inputs.nixpkgs.follows =
# "nixpkgs";` in their own flake. `mkHooks` (via `nixhooks.lib { inherit
# pkgs; }`) is unaffected and still takes a caller-supplied `pkgs` for manual
# use.
{nixpkgs}: {
  hooks, # attrset keyed by system, e.g. hooks.x86_64-linux = {...}; see lib/hook-spec.nix for per-hook fields.
  tangled ? {},
  githubActions ? {},
  parallel ? false,
  ...
} @ args: let
  outputs = builtins.removeAttrs args ["hooks" "tangled" "githubActions" "parallel"];
  systems = builtins.attrNames hooks;

  mergeSystem = acc: system: let
    pkgs = import nixpkgs {inherit system;};
    inherit (pkgs) lib;
    base = import ./lib {inherit pkgs;};

    hookResult = base.mkHooks {
      hooks = hooks.${system};
      inherit tangled githubActions parallel;
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
