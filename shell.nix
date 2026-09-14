{pkgs ? import (import ./npins).nixpkgs {}}: let
  nixhooksLib = import ./default.nix {inherit pkgs;};

  hooks = nixhooksLib.mkHooks {
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
  };
in
  pkgs.mkShell {
    packages = [pkgs.npins pkgs.alejandra pkgs.bats];
    shellHook = ''
      ${hooks.install-hooks}/bin/install-hooks
    '';
  }
