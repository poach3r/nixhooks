{pkgs}: let
  mkPreset = attrs: attrs // {__functor = self: args: self // args;};
in {
  shellcheck = mkPreset {
    entry = "${pkgs.shellcheck}/bin/shellcheck";
    files = "\\.sh$";
    serial = false;
  };

  alejandra = mkPreset {
    entry = "${pkgs.alejandra}/bin/alejandra";
    args = ["--check"];
    files = "\\.nix$";
    serial = false;
  };

  statix = mkPreset {
    entry = "${pkgs.statix}/bin/statix";
    # statix scans the whole tree itself so nixhooks' own `exclude` field never
    # applies here
    args = ["check" "--ignore" "npins/**"];
    files = "\\.nix$";
    pass_filenames = false;
    always_run = true;
    serial = false;
  };

  deadnix = mkPreset {
    entry = "${pkgs.deadnix}/bin/deadnix";
    args = ["--fail"];
    files = "\\.nix$";
    serial = false;
  };

  typos = mkPreset {
    entry = "${pkgs.typos}/bin/typos";
    serial = false;
  };

  betterleaks = mkPreset {
    entry = "${pkgs.betterleaks}/bin/betterleaks";
    args = ["dir" "--no-banner" "--no-color"];
    pass_filenames = false;
    always_run = true;
    serial = false;
  };

  harper = mkPreset {
    entry = "${pkgs.harper}/bin/harper-cli";
    args = ["lint" "--no-color"];
    files = "\\.(md|txt)$";
    serial = false;
  };

  commitlint = mkPreset {
    entry = "${pkgs.commitlint}/bin/commitlint";
    args = ["--edit"];
    stages = ["commit-msg"];
    serial = false;
  };

  commitizen = mkPreset {
    entry = "${pkgs.commitizen}/bin/cz";
    args = ["check" "--commit-msg-file"];
    stages = ["commit-msg"];
    serial = false;
  };

  shfmt = mkPreset {
    entry = "${pkgs.shfmt}/bin/shfmt";
    args = ["-d"];
    files = "\\.sh$";
    serial = false;
  };

  bats = mkPreset {
    entry = "${pkgs.bats}/bin/bats";
    files = "\\.bats$";
    serial = false;
  };

  ruff-lint = mkPreset {
    entry = "${pkgs.ruff}/bin/ruff";
    args = ["check" "--no-fix"];
    files = "\\.(py|pyi|pyw|ipynb)$";
    pass_filenames = false;
    serial = false;
  };

  ruff-fmt = mkPreset {
    entry = "${pkgs.ruff}/bin/ruff";
    args = ["format" "--check"];
    files = "\\.(py|pyi|pyw|ipynb)$";
    serial = false;
  };

  stylua = mkPreset {
    entry = "${pkgs.stylua}/bin/stylua";
    args = ["--check"];
    files = "\\.lua$";
    serial = false;
  };

  selene = mkPreset {
    entry = "${pkgs.selene}/bin/selene";
    files = "\\.lua$";
    serial = false;
  };

  taplo-fmt = mkPreset {
    entry = "${pkgs.taplo}/bin/taplo";
    args = ["fmt" "--check"];
    files = "\\.toml$";
    serial = false;
  };

  taplo-lint = mkPreset {
    entry = "${pkgs.taplo}/bin/taplo";
    args = ["lint"];
    files = "\\.toml$";
    serial = false;
  };

  yamlfmt = mkPreset {
    entry = "${pkgs.yamlfmt}/bin/yamlfmt";
    args = ["-lint"];
    files = "\\.ya?ml$";
    serial = false;
  };

  yamllint = mkPreset {
    entry = "${pkgs.yamllint}/bin/yamllint";
    files = "\\.ya?ml$";
    serial = false;
  };

  xmllint-lint = mkPreset {
    entry = "${pkgs.libxml2}/bin/xmllint";
    args = ["--noout"];
    files = "\\.xml$";
    serial = false;
  };

  xmllint-fmt = let
    # xmllint --format always prepends an <?xml ...?> declaration to its
    # output, even when the input has none
    check = pkgs.writeShellScriptBin "xmllint-fmt-check" ''
      unformatted=()
      for f in "$@"; do
        if ! diff -q \
          <(sed '1{/^<?xml /d}' "$f") \
          <(${pkgs.libxml2}/bin/xmllint --format "$f" | sed '1{/^<?xml /d}') \
          >/dev/null; then
          unformatted+=("$f")
        fi
      done
      if [ "''${#unformatted[@]}" -gt 0 ]; then
        printf '%s\n' "''${unformatted[@]}"
        exit 1
      fi
    '';
  in
    mkPreset {
      entry = "${check}/bin/xmllint-fmt-check";
      files = "\\.xml$";
      serial = false;
    };

  prettier = mkPreset {
    entry = "${pkgs.prettier}/bin/prettier";
    args = ["--check"];
    files = "\\.(html|css|scss|less|js|jsx|ts|tsx|json)$";
    serial = false;
  };

  eslint = mkPreset {
    entry = "${pkgs.eslint}/bin/eslint";
    files = "\\.(js|jsx|ts|tsx)$";
    serial = false;
  };

  rustfmt = mkPreset {
    entry = "${pkgs.rustfmt}/bin/rustfmt";
    args = ["--check"];
    files = "\\.rs$";
    serial = false;
  };

  clippy = mkPreset {
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
  in
    mkPreset {
      entry = "${check}/bin/gofmt-check";
      files = "\\.go$";
      serial = false;
    };

  govet = mkPreset {
    entry = "${pkgs.go}/bin/go";
    args = ["vet" "./..."];
    files = "\\.go$";
    pass_filenames = false;
    always_run = true;
    serial = false;
  };

  zigfmt = mkPreset {
    entry = "${pkgs.zig}/bin/zig";
    args = ["fmt" "--check"];
    files = "\\.zig$";
    serial = false;
  };

  scalafmt = let
    # scalafmt --check exits 0 on invalid scala so we need to wrap it to exit 1
    check = pkgs.writeShellScriptBin "scalafmt-check" ''
      out="$(${pkgs.scalafmt}/bin/scalafmt --check "$@" 2>&1)"
      status=$?
      if [ "$status" -ne 0 ] || printf '%s\n' "$out" | grep -q 'error:'; then
        printf '%s\n' "$out"
        exit 1
      fi
    '';
  in
    mkPreset {
      entry = "${check}/bin/scalafmt-check";
      files = "\\.scala$";
      serial = false;
    };

  google-java-format = mkPreset {
    entry = "${pkgs.google-java-format}/bin/google-java-format";
    args = ["--set-exit-if-changed"];
    files = "\\.java$";
    serial = false;
  };
}
