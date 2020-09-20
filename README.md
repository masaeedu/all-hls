# Overview

Provides all combinations of platform, version and GHC that are available on the `haskell/haskell-language-server` releases page.


# Usage

While it is recommended that you add this project as a dependency using something like [`niv`](https://github.com/nmattia/niv) for easy updates, a quick and dirty way to get started is:

```nix
# shell.nix
with import <nixpkgs> {};

let
  all-hls = fetchFromGitHub { owner = "masaeedu"; repo = "all-hls"; rev = "155e57d7ca9f79ce293360f98895e9bd68d12355"; sha256 = "04s3mrxjdr7gmd901l1z23qglqmn8i39v7sdf2fv4zbv6hz24ydb"; };
  hls = import all-hls { platform = "Linux"; version = "0.4.0"; ghc = "8.8.3"; }; # All parameters are optional. The default values are shown here.
in
mkShell {
  buildInputs = [ hls ];
}
```

Then run:

```
➜  xyz nix-shell

[nix-shell:/tmp/xyz]$ haskell-language-server --version
haskell-language-server version: 0.4.0.0 (GHC: 8.8.3) (PATH: /nix/store/s0b9npdlyqzdw7c8lnyxkv3d98q6zwfb-haskell-language-server-0.4.0-for-8.8.3-on-Linux/bin/haskell-language-server) (GIT hash: 0a18edde24923251a148cbbc0ae993a6aac83b9c)
```
