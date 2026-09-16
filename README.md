> Development takes place on [Tangled](https://tangled.org/poacher.dev/nixhooks),
  however, I do maintain a [GitHub mirror](https://github.com/poach3r/nixhooks). 
  Please make issues and PRs to the Tangled repository.

# nixhooks
A small, fast, drop-in replacement for [git-hooks.nix](https://github.com/cachix/git-hooks.nix).
No flake required, no `flake-parts`, no `systems`, no Python, no slop, just 
plain ol' Nix and Bash.

## Usage (non-flake)
```nix
{ pkgs ? import <nixpkgs> { } }:

let
  nixhooks = import (fetchTarball "https://next.tangled.org/xrpc/sh.tangled.repo.archive?repo=at%3A%2F%2Fdid%3Aplc%3Ayaryxzbwui6ejiegzysy6ipp%2Fsh.tangled.repo%2Fnixhooks&ref=main&format=tar.gz") { inherit pkgs; };
in
nixhooks.mkHooks {
  hooks = {
    shellcheck = {
      entry = "${pkgs.shellcheck}/bin/shellcheck";
      files = "\\.sh$";
      stages = [ "pre-commit" "pre-push" ];
    };

    nixfmt-check = {
      entry = "${pkgs.nixfmt}/bin/nixfmt";
      args = [ "--check" ];
      files = "\\.nix$";
    };
  };
}
```

```console
$ nix-build -A install-hooks && ./result/bin/install-hooks
```

Or, wire it into a `shellHook` so hooks install automatically on entry (see the `devShells` output in [flake.nix](./flake.nix)).

## Usage (flake)
`nixhooks.lib.<system>` is `mkHooks`/`presets` built from nixhooks' own
pinned `nixpkgs` for that system. 

```nix
{
  inputs.nixhooks.url = "git+https://tangled.org/poacher.dev/nixhooks";
  outputs = { self, nixpkgs, nixhooks }: let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    hooks = nixhooks.lib.x86_64-linux.mkHooks {
      hooks = {
        shellcheck = {
          entry = "${pkgs.shellcheck}/bin/shellcheck";
          files = "\\.sh$";
        };
      };
    };
  in {
    apps.x86_64-linux = hooks.apps; 
    devShells.x86_64-linux.default = pkgs.mkShell {
      shellHook = ''
        ${hooks.install-hooks}/bin/install-hooks
      '';
    };
  };
}
```

```console
$ nix run .#install-hooks
```

### `lib.withHooks`
`withHooks` is sugar over `mkHooks` for flakes. Pass it your hook config
alongside your regular flake outputs and it merges the generated
apps/packages and wires `install-hooks` into `devShells.<system>.default`

Everything nixhooks-specific is passed as one `nixhooks` argument, keeping it
separate from your regular flake outputs. `nixhooks.hooks` is keyed by
system, while `nixhooks.settings`is not.

```nix
{
  inputs.nixhooks.url = "git+https://tangled.org/poacher.dev/nixhooks";
  outputs = { self, nixpkgs, nixhooks }: let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
  in nixhooks.lib.withHooks {
    nixhooks = {
      hooks.x86_64-linux = { inherit (nixhooks.lib.x86_64-linux.presets) alejandra statix; };
      settings = {
        parallel = true;
        tangled = {
          enable = true;
          attr = "run-hooks";
          flake = true;
        };
      };
    };

    packages.x86_64-linux = { /* ... */ };
    apps.x86_64-linux = { /* ... */ };
    devShells.x86_64-linux.default = pkgs.mkShell {
      packages = [ pkgs.jq ];
    };
  };
}
```

## Hook spec
```nix
hooks.<name> = {
  enable = true;                     # default true; set false to disable without deleting the entry
  entry = "/nix/store/.../bin/tool"; # required: the command to run
  args = [ ];                        # extra args passed before matched filenames
  files = ".*";                      # ERE regex (bash [[ =~ ]]) tested against each candidate path
  exclude = "^$";                    # ERE regex; "^$" (default) excludes nothing
  stages = [ "pre-commit" ];         # subset of [ "pre-commit" "pre-push" "commit-msg" ]
  pass_filenames = true;             # append matched files as trailing args
  always_run = false;                # run once with no file filtering/passing 
  path = [ ];                        # packages whose bin/ dirs are prepended to PATH for entry
  serial = true;                     # if false this hook will be run in parallel; see "Parallel execution" below
};
```

`<name>` must match `[A-Za-z0-9_.-]+`

`path` is for tools that internally dispatch to a sibling binary via `PATH`
(e.g. `cargo` finding `cargo-clippy`) -- `entry` itself is always invoked by
absolute path regardless of `path`.

A `commit-msg`-staged hook receives the path to the temporary file
containing the commit message as its sole file. `files`/`exclude`/
`pass_filenames` apply to that single path the same way they apply to real
filenames in `pre-commit`/`pre-push`.

## Presets
`presets` is a small built-in catalog of common tool configs. These are 
functors which accept either no arguments, or allow for their options to be 
overriden in an attrSet.

```nix
nixhooks.mkHooks {
  hooks = {
    shellcheck = nixhooksLib.presets.shellcheck;
    alejandra = nixhooksLib.presets.alejandra { stages = [ "pre-push" ]; };
  };
}
```

See [lib/presets.nix](./lib/presets.nix) for the full list of presets.

## Parallel execution
By default every hook runs sequentially. Passing `settings.parallel = true` to
`mkHooks` enables a two-phase model where every hook not marked `serial` runs 
concurrently, then the remaining hooks run sequentially. Note that parallelism
can actually *decrease* your hook execution speed if its already fast. Only use
it when needed.

```nix
nixhooks.mkHooks {
  hooks = {inherit (nixhooksLib.presets) shellcheck alejandra statix;};
  settings.parallel = true;
}
```

Output from the concurrent batch is buffered per hook and flushed once the
entire batch finishes in the declared order. 

Only mark a hook `serial = false` if it doesn't mutate the files it's
matched against, or if it's provably safe to race against every other
`serial = false` hook in the same stage. 

## CI/CD
nixhooks can also autogenerate CI workflows based on your selected hooks.

Hooks staged only for `commit-msg` (e.g. the `commitlint` preset) are
excluded from the generated CI pipeline's `run-hooks` invocation as CI has
no commit message to check. A hook declaring multiple stages including 
`commit-msg` still runs in CI for its other stage(s).

### Tangled pipelines
```nix
nixhooks.mkHooks {
  hooks = { /* ... */ };
  settings.tangled = {
    enable = true;
    attr = "run-hooks";
    flake = true;
    engine = "microvm";
    when = [
      {
        event = ["push" "pull_request"];
        branch = ["main"];
      }
    ];
  };
}
```

```console
$ nix-build -A gen-tangled-pipeline && ./result/bin/gen-tangled-pipeline
gen-tangled-pipeline: wrote .tangled/workflows/hooks.yml
```

This writes a `.tangled/workflows/hooks.yml` in the same manner as 
`install-hooks` which you commit to the repo. Note that this isn't wired into 
`shellHook` like `install-hooks`, so you'll need to trigger it manually.

### GitHub Actions
```nix
nixhooks.mkHooks {
  hooks = { /* ... */ };
  settings.githubActions = {
    enable = true;
    attr = "run-hooks";
    flake = true;
    runsOn = "ubuntu-latest";
    cache = true; # nix-community/cache-nix-action
    on = {
      push = { branches = [ "main" ]; };
      pull_request = { branches = [ "main" ]; };
    };
  };
}
```

```console
$ nix-build -A gen-github-actions-workflow && ./result/bin/gen-github-actions-workflow
gen-github-actions-workflow: wrote .github/workflows/hooks.yml
```

Note that I don't actively used GitHub. If you find any bugs then please open 
an issue.

# Benchmarks
https://tangled.org/poacher.dev/nixhooks-benchmark
