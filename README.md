# slopsmith/ci

Packaging and nightly builds shared by the slopsmith Mac apps
([ps5slop](https://github.com/slopsmith/ps5slop) and
[pcslop](https://github.com/slopsmith/pcslop)).

## slop-app

A flake package with the steps every app bundle needs. A project adds this
repo as a flake input and re-exports the package, so the version it uses is
pinned in its `flake.lock`:

```nix
inputs.slopsmith-ci.url = "github:slopsmith/ci";
inputs.slopsmith-ci.inputs.nixpkgs.follows = "nixpkgs";
# in outputs:
packages.aarch64-darwin.slop-app = slopsmith-ci.packages.aarch64-darwin.slop-app;
```

Its bundle script then runs `$(nix build --no-link --print-out-paths .#slop-app)/bin/slop-app`:

| Command | What it does |
| --- | --- |
| `commit` | Prints the commit to stamp the build with: `$SLOP_COMMIT`, else `git rev-parse HEAD` plus `-dirty` when tracked files differ |
| `plist APP KEY=VALUE...` | Writes `Info.plist` (executable, id, name, category, version, commit). The commit goes into `SlopCommit` |
| `nix-libs APP BINARY...` | Copies the `/nix/store` libraries the binaries need into `Contents/Frameworks`. Nix's builds of Apple's libiconv and libresolv are linked from `/usr/lib` instead |
| `licenses APP DIR [MANIFEST]` | Copies the texts in `DIR` to `Contents/Resources/Licenses` and writes the Rust crates' notices with `cargo about` |
| `sign APP ENTITLEMENTS BINARY` | Signs everything ad hoc, `BINARY` with the entitlements |
| `check APP BINARY` | The upload checks (below) |
| `zip APP OUT` | Zips the app with `ditto` |

`slop-app check` fails unless:

- `Info.plist` is valid, names an existing launcher, needs macOS 26.0 and has a commit in `SlopCommit`; the app has an icon;
- every Mach-O file is arm64 and nothing links into `/nix/store`;
- `codesign --verify --strict --deep` passes and `BINARY` has the hypervisor entitlement;
- `BINARY --version` runs from the bundle and names the same commit;
- `Contents/Resources/Licenses/README.txt` exists and names every bundled library.

## The nightly workflow

`.github/workflows/macos-nightly.yml` is a reusable workflow. A project calls it
from a scheduled workflow of its own:

```yaml
on:
  schedule:
    - cron: "0 3 * * *"
  workflow_dispatch:
permissions:
  contents: write
jobs:
  nightly:
    uses: slopsmith/ci/.github/workflows/macos-nightly.yml@main
    with:
      project: ps5slop
      app: target/ps5slop.app
      binary: Contents/MacOS/ps5slop
      bundle: scripts/bundle-app
```

It skips the run when the `nightly` tag already points at the commit (unless
`force`), runs `linux-build` on x86_64 Linux if given, then on a hosted
`macos-26` runner runs `checks` (default: `cargo fmt --check` and
`cargo test`), the bundle command with `SLOP_COMMIT` set, and `slop-app check`.
It then moves the `nightly` tag to the commit and replaces the two assets of
the rolling `nightly` release:

- `PROJECT-macos-arm64.zip`, always at `https://github.com/slopsmith/PROJECT/releases/download/nightly/PROJECT-macos-arm64.zip`;
- `nightly.json` (`commit`, `date`, `download`, `release`), which the apps read to offer updates.

Hosted macOS runners are virtual M1s with three cores: Hypervisor.framework
VMs cannot be made there (`hv_vm_create` returns `HV_UNSUPPORTED`) and Metal is
a paravirtual device without the Apple7 family, so `checks` must leave out
tests that need either.
