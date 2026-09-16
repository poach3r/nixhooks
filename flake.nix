{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = {nixpkgs, ...}: let
    systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});
    withHooks = import ./with-hooks.nix {inherit nixpkgs;};

    # nixhooks.lib is a functor called with `{pkgs}`
    lib = let
      defaultPkgs = nixpkgs.legacyPackages.${builtins.head systems};
      base = import ./lib {pkgs = defaultPkgs;};
    in
      (builtins.removeAttrs base ["mkHooks" "presets" "presetSystems"])
      // {presets = defaultPkgs.lib.getAttrs base.presetSystems base.presets;}
      // {inherit withHooks;}
      // {__functor = _self: args: import ./lib args;};
  in
    withHooks {
      hooks = forAllSystems (system: pkgs: let
        nixhooksLib = import ./lib {inherit pkgs;};
      in
        {inherit (nixhooksLib.presets) commitlint;}
        // pkgs.lib.mapAttrs (_: h: h {stages = ["pre-push"];}) {
          inherit (nixhooksLib.presets) shellcheck alejandra bats shfmt deadnix statix;
        });

      parallel = true;
      tangled = {
        enable = true;
        attr = "run-hooks";
        flake = true;
        when = [
          {
            event = ["push" "pull_request"];
            branch = ["main"];
          }
        ];
      };

      devShells = forAllSystems (_: pkgs: {
        default = pkgs.mkShell {
          packages = [pkgs.shfmt pkgs.alejandra pkgs.bats];
        };
      });
    }
    // {inherit lib;};
}
