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
  in {
    lib = import ./lib;
    devShells = forAllSystems (system: {
      default = import ./shell.nix {
        pkgs = import npinsSources.nixpkgs {inherit system;};
      };
    });
  };
}
