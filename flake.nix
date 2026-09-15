{
  outputs = {self}: let
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
      hooks = (import ./default.nix {inherit pkgs;}).mkHooks {
        hooks = {
          shellcheck = {
            entry = "${pkgs.shellcheck}/bin/shellcheck";
            files = "\\.sh$";
            stages = ["pre-push"];
          };

          alejandra-check = {
            entry = "${pkgs.alejandra}/bin/alejandra";
            args = ["--check"];
            files = "\\.nix$";
            stages = ["pre-push"];
          };
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
          packages = [d.pkgs.npins d.pkgs.alejandra d.pkgs.bats];
          shellHook = ''
            ${d.hooks.install-hooks}/bin/install-hooks
          '';
        };
      })
      systemsData;
  };
}
