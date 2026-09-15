{pkgs}: {
  shellcheck = {
    entry = "${pkgs.shellcheck}/bin/shellcheck";
    files = "\\.sh$";
    serial = false;
  };

  alejandra = {
    entry = "${pkgs.alejandra}/bin/alejandra";
    args = ["--check"];
    files = "\\.nix$";
    serial = false;
  };

  statix = {
    entry = "${pkgs.statix}/bin/statix";
    args = ["check"];
    files = "\\.nix$";
    pass_filenames = false;
    always_run = true;
    serial = false;
  };

  deadnix = {
    entry = "${pkgs.deadnix}/bin/deadnix";
    args = ["--fail"];
    files = "\\.nix$";
    serial = false;
  };

  typos = {
    entry = "${pkgs.typos}/bin/typos";
    serial = false;
  };

  betterleaks = {
    entry = "${pkgs.betterleaks}/bin/betterleaks";
    args = ["dir" "--no-banner" "--no-color"];
    serial = false;
  };

  harper = {
    entry = "${pkgs.harper}/bin/harper-cli";
    args = ["lint" "--no-color"];
    files = "\\.(md|txt)$";
    serial = false;
  };

  commitlint = {
    entry = "${pkgs.commitlint}/bin/commitlint";
    args = ["--edit"];
    stages = ["commit-msg"];
    serial = false;
  };

  shfmt = {
    entry = "${pkgs.shfmt}/bin/shfmt";
    args = ["-d"];
    files = "\\.sh$";
    serial = false;
  };

  bats = {
    entry = "${pkgs.bats}/bin/bats";
    files = "\\.bats$";
    serial = false;
  };

  stylua = {
    entry = "${pkgs.stylua}/bin/stylua";
    args = ["--check"];
    files = "\\.lua$";
    serial = false;
  };

  selene = {
    entry = "${pkgs.selene}/bin/selene";
    files = "\\.lua$";
    serial = false;
  };

  taplo-fmt = {
    entry = "${pkgs.taplo}/bin/taplo";
    args = ["fmt" "--check"];
    files = "\\.toml$";
    serial = false;
  };

  taplo-lint = {
    entry = "${pkgs.taplo}/bin/taplo";
    args = ["lint"];
    files = "\\.toml$";
    serial = false;
  };

  yamllint = {
    entry = "${pkgs.yamllint}/bin/yamllint";
    files = "\\.ya?ml$";
    serial = false;
  };

  prettier = {
    entry = "${pkgs.prettier}/bin/prettier";
    args = ["--check"];
    files = "\\.(html|css|scss|less|js|jsx|ts|tsx)$";
    serial = false;
  };

  eslint = {
    entry = "${pkgs.eslint}/bin/eslint";
    files = "\\.(js|jsx|ts|tsx)$";
    serial = false;
  };

  rustfmt = {
    entry = "${pkgs.rustfmt}/bin/rustfmt";
    args = ["--check"];
    files = "\\.rs$";
    serial = false;
  };

  clippy = {
    # cargo dispatches `clippy` to `cargo-clippy` via PATH
    entry = "${pkgs.cargo}/bin/cargo";
    args = ["clippy" "--" "-D" "warnings"];
    path = [pkgs.clippy];
    files = "\\.rs$";
    pass_filenames = false;
    always_run = true;
    serial = false;
  };

  gofmt = let
    check = pkgs.writeShellScriptBin "gofmt-check" ''
      unformatted="$(${pkgs.go}/bin/gofmt -l "$@")"
      if [ -n "$unformatted" ]; then
        echo "$unformatted"
        exit 1
      fi
    '';
  in {
    entry = "${check}/bin/gofmt-check";
    files = "\\.go$";
    serial = false;
  };

  govet = {
    entry = "${pkgs.go}/bin/go";
    args = ["vet" "./..."];
    files = "\\.go$";
    pass_filenames = false;
    always_run = true;
    serial = false;
  };

  zigfmt = {
    entry = "${pkgs.zig}/bin/zig";
    args = ["fmt" "--check"];
    files = "\\.zig$";
    serial = false;
  };
}
