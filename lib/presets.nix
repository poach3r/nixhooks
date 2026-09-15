{pkgs}: {
  shellcheck = {
    entry = "${pkgs.shellcheck}/bin/shellcheck";
    files = "\\.sh$";
  };

  alejandra = {
    entry = "${pkgs.alejandra}/bin/alejandra";
    args = ["--check"];
    files = "\\.nix$";
  };

  statix = {
    entry = "${pkgs.statix}/bin/statix";
    args = ["check"];
    files = "\\.nix$";
    pass_filenames = false;
    always_run = true;
  };

  deadnix = {
    entry = "${pkgs.deadnix}/bin/deadnix";
    args = ["--fail"];
    files = "\\.nix$";
  };

  typos = {
    entry = "${pkgs.typos}/bin/typos";
  };

  harper = {
    entry = "${pkgs.harper}/bin/harper-cli";
    args = ["lint" "--no-color"];
    files = "\\.(md|txt)$";
  };

  shfmt = {
    entry = "${pkgs.shfmt}/bin/shfmt";
    args = ["-d"];
    files = "\\.sh$";
  };

  bats = {
    entry = "${pkgs.bats}/bin/bats";
    files = "\\.bats$";
  };

  taplo = {
    entry = "${pkgs.taplo}/bin/taplo";
    args = ["fmt" "--check"];
    files = "\\.toml$";
  };

  yamllint = {
    entry = "${pkgs.yamllint}/bin/yamllint";
    files = "\\.ya?ml$";
  };

  prettier = {
    entry = "${pkgs.prettier}/bin/prettier";
    args = ["--check"];
    files = "\\.(html|css|scss|less|js|jsx|ts|tsx)$";
  };

  eslint = {
    entry = "${pkgs.eslint}/bin/eslint";
    files = "\\.(js|jsx|ts|tsx)$";
  };

  rustfmt = {
    entry = "${pkgs.rustfmt}/bin/rustfmt";
    args = ["--check"];
    files = "\\.rs$";
  };

  clippy = {
    # cargo dispatches `clippy` to `cargo-clippy` via PATH
    entry = "${pkgs.cargo}/bin/cargo";
    args = ["clippy" "--" "-D" "warnings"];
    path = [pkgs.clippy];
    files = "\\.rs$";
    pass_filenames = false;
    always_run = true;
  };

  govet = {
    entry = "${pkgs.go}/bin/go";
    args = ["vet" "./..."];
    files = "\\.go$";
    pass_filenames = false;
    always_run = true;
  };

  zigfmt = {
    entry = "${pkgs.zig}/bin/zig";
    args = ["fmt" "--check"];
    files = "\\.zig$";
  };
}
