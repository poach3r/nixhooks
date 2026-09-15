# nixhooks
A small, fast, drop-in replacement for [git-hooks.nix](https://github.com/cachix/git-hooks.nix)
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

## Tangled pipelines
`mkHooks` can also generate a [Tangled](https://tangled.org) Spindle pipeline:

```nix
nixhooks.mkHooks {
  hooks = { /* ... */ };
  tangled = {
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

# Benchmarks
Measured against git-hooks.nix pinned to [`27555e2`](https://github.com/cachix/git-hooks.nix/commit/27555e2624241fb116b49095df4caaee85a25691)

## Evaluation 
| | nixhooks | git-hooks.nix | ratio |
|---|---:|---:|---:|
| **shellcheck+nixfmt** | | | |
| `nrFunctionCalls` | 418,967 | 899,340 | 2.15× |
| `nrLookups` | 217,953 | 474,046 | 2.17× |
| `nrThunks` | 948,777 | 2,075,768 | 2.19× |
| `values.number` | 1,867,274 | 4,366,397 | 2.34× |
| `cpuTime` | 0.499 s | 1.019 s | 2.04× |
| **no hooks** | | | |
| `nrFunctionCalls` | 45,514 | 703,210 | 15.45× |
| `nrLookups` | 26,666 | 378,436 | 14.19× |
| `nrThunks` | 135,622 | 1,797,899 | 13.26× |
| `values.number` | 585,871 | 4,066,662 | 6.94× |
| `cpuTime` | 0.083 s | 0.911 s | 11.04× |

## Hook installation
| Command | Mean | Min | Max |
|---|---:|---:|---:|
| nixhooks `-A install-hooks` | 647.7 ms ± 54.5 ms | 594.1 ms | 763.4 ms |
| git-hooks.nix (installationScript) | 1.263 s ± 0.030 s | 1.222 s | 1.321 s |

## Hook execution
| Command | Mean | Min | Max |
|---|---:|---:|---:|
| nixhooks pre-commit hook | 14.3 ms ± 1.4 ms | 12.8 ms | 23.4 ms |
| git-hooks.nix pre-commit hook | 89.4 ms ± 2.0 ms | 87.0 ms | 94.8 ms |

## Store closure size 
| | Closure size |
|---|---:|
| nixhooks `install-hooks` | 83.65 MiB |
| git-hooks.nix workflow closure | 359.03 MiB |


