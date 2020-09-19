{ pkgs ? import <nixpkgs> {}, version ? "0.4.0", ghc ? "8.8.3", platform ? "Linux" }:

with pkgs;

let
hashes = builtins.fromJSON (builtins.readFile ./sources.json);

gunzip = src:
  let
  builder = writeShellScript
    "gunzip-builder"
    ''
      ${gzip}/bin/gzip -d -c ${src} > $out
    '';
  in
  builtins.derivation {
    system = "x86_64-linux";
    name = "gunzip";
    inherit builder;
  };

hls-wrapper = gunzip (fetchurl {
  curlOpts = ["-L"];
  url = "https://github.com/haskell/haskell-language-server/releases/download/${version}/haskell-language-server-wrapper-${platform}.gz";
  hash = hashes."${version}".wrapper;
});

hls-ghc = gunzip (fetchurl {
  curlOpts = ["-L"];
  url = "https://github.com/haskell/haskell-language-server/releases/download/${version}/haskell-language-server-${platform}-${ghc}.gz";
  hash = hashes."${version}"."${ghc}";
});

builder = writeShellScript
  "haskell-language-server-builder"
  ''
    ${coreutils}/bin/mkdir -p $out/bin
    ${coreutils}/bin/install ${hls-wrapper} $out/bin/haskell-language-server-wrapper
    ${coreutils}/bin/install ${hls-ghc} $out/bin/haskell-language-server
  '';
in

builtins.derivation {
  system = "x86_64-linux";
  name = "haskell-language-server-${version}-for-${ghc}-on-${platform}";

  inherit builder;
}
