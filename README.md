# nixhooks
A small, fast, drop-in replacement for [git-hooks.nix](https://github.com/cachix/git-hooks.nix)
No flake required, no `flake-parts`, no `systems`, no Python, no slop, just 
plain ol' Nix and Bash.

## Usage (non-flake)
```nix
# default.nix in your project
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

Or, wire it into a `shellHook` so hooks install automatically on entry (see [shell.nix](./shell.nix)).

## Usage (flake)
```nix
{
  inputs.nixhooks.url = "github:you/nixhooks";
  outputs = { self, nixpkgs, nixhooks }: let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    hooks = (nixhooks.lib { inherit pkgs; }).mkHooks {
      hooks = {
        shellcheck = {
          entry = "${pkgs.shellcheck}/bin/shellcheck";
          files = "\\.sh$";
        };
      };
    };
  in {
    apps.x86_64-linux.install-hooks = {
      type = "app";
      program = "${hooks.install-hooks}/bin/install-hooks";
    };

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

## Hook spec
```nix
hooks.<name> = {
  enable = true;                     # default true; set false to disable without deleting the entry
  entry = "/nix/store/.../bin/tool"; # required: the command to run
  args = [ ];                        # extra args passed before matched filenames
  files = ".*";                      # ERE regex (bash [[ =~ ]]) tested against each candidate path
  exclude = "^$";                    # ERE regex; "^$" (default) excludes nothing
  stages = [ "pre-commit" ];         # subset of [ "pre-commit" "pre-push" ]
  pass_filenames = true;             # append matched files as trailing args
  always_run = false;                # run once with no file filtering/passing 
};
```

`<name>` must match `[A-Za-z0-9_.-]+`

## Known v1 limitations
- **Partial staging**: hooks run against the working tree, not a stash of just the staged
  changes. A formatter hook may therefore also see/rewrite unstaged hunks in an otherwise
  partially-staged file. 
- **New-branch pre-push**: when pushing a new branch with no upstream, there's no meaningful
  remote ref to diff against, so hooks run in whole-repo mode for that ref instead of a precise
  diff.
- **No built-in presets**: every hook's `entry` is BYO — there's no curated library of ~100
  pre-wired linters like git-hooks.nix ships. This keeps the core small; a presets module can be
  layered on top later without touching the engine.

# Benchmarks
## Evaluation 
| | nixhooks | git-hooks.nix | ratio |
|---|---:|---:|---:|
| **shellcheck+nixfmt** | | | |
| `nrFunctionCalls` | 433,654 | 847,527 | 1.95× |
| `nrLookups` | 225,963 | 444,844 | 1.97× |
| `nrThunks` | 977,026 | 1,680,913 | 1.72× |
| `values.number` | 1,898,390 | 2,901,842 | 1.53× |
| `cpuTime` (evaluator only) | 3.06 s | 4.18 s | 1.37× |
| **no hooks** | | | |
| `nrFunctionCalls` | 301,187 | 651,274 | 2.16× |
| `nrLookups` | 163,404 | 349,549 | 2.14× |
| `nrThunks` | 789,079 | 1,402,928 | 1.78× |

## Hook installation
| Command | Mean | Min | Max |
|---|---:|---:|---:|
| nixhooks `-A install-hooks` | 4.195 s ± 0.556 s | 3.238 s | 5.052 s |
| git-hooks.nix (default attr) | 5.028 s ± 0.499 s | 4.445 s | 6.404 s |

## Hook execution
| Command | Mean | Min | Max |
|---|---:|---:|---:|
| nixhooks pre-commit hook | 39.0 ms ± 1.7 ms | 36.8 ms | 45.6 ms |
| git-hooks.nix pre-commit hook | 432.5 ms ± 88.6 ms | 348.7 ms | 596.7 ms |

## Store closure size (`nix path-info -S`)
| | Closure size |
|---|---:|
| nixhooks `install-hooks` | 83.6 MiB |
| git-hooks.nix workflow closure | 359.0 MiB |

