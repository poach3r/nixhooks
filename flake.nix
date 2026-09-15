{
  outputs = {...}: let
    npinsSources = import ./npins;
    systems = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    forAllSystems = f:
      builtins.listToAttrs (
        map (system: {
          name = system;
          value = f system;
        })
        systems
      );

    perSystem = system: let
      pkgs = import npinsSources.nixpkgs {inherit system;};
      nixhooksLib = import ./default.nix {inherit pkgs;};
      hooks = nixhooksLib.mkHooks {
        hooks = {
          shellcheck = nixhooksLib.presets.shellcheck // {stages = ["pre-push"];};
          alejandra = nixhooksLib.presets.alejandra // {stages = ["pre-push"];};
          shfmt = nixhooksLib.presets.shfmt // {stages = ["pre-push"];};
          deadnix = nixhooksLib.presets.deadnix // {stages = ["pre-push"];};
        };

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
      };
    in {
      inherit pkgs hooks;
    };

    systemsData = forAllSystems perSystem;
  in {
    lib = import ./lib;
    apps = builtins.mapAttrs (_: d: d.hooks.apps) systemsData;
    packages = builtins.mapAttrs (_: d: {inherit (d.hooks) tangled-pipeline;}) systemsData;
    devShells =
      builtins.mapAttrs (_: d: {
        default = d.pkgs.mkShell {
          packages = [d.pkgs.shfmt d.pkgs.npins d.pkgs.alejandra d.pkgs.bats];
          shellHook = ''
            ${d.hooks.install-hooks}/bin/install-hooks
          '';
        };
      })
      systemsData;
  };
}
