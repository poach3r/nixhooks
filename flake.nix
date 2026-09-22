{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = {
    self,
    nixpkgs,
    ...
  }: let
    systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});
    withHooks = import ./with-hooks.nix {inherit nixpkgs;};
  in
    withHooks {
      hooks = forAllSystems (_: pkgs:
        {
          inherit (self.lib.x86_64-linux.presets) commitlint;
          settings = {
            parallel = true;
            tangled.enable = true;
          };
        }
        // pkgs.lib.mapAttrs (_: h: h {stages = ["pre-push"];}) {
          inherit (self.lib.x86_64-linux.presets) shellcheck alejandra bats shfmt deadnix statix;
        });

      devShells = forAllSystems (_: pkgs: {
        default = pkgs.mkShell {
          packages = [pkgs.shfmt pkgs.alejandra pkgs.bats];
        };
      });

      lib =
        forAllSystems (_: pkgs: import ./lib {inherit pkgs;})
        // {inherit withHooks;};
    };
}
