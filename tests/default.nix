{pkgs}:
pkgs.runCommand "nixhooks-tests"
{
  nativeBuildInputs = [
    pkgs.bats
    pkgs.git
    pkgs.bash
  ];
}
''
  export HOME="$TMPDIR"
  git config --global user.email test@example.com
  git config --global user.name test
  git config --global init.defaultBranch main

  NIXHOOKS_LIB=${../lib} bats ${./.}/hooks-runtime.bats
  touch "$out"
''
