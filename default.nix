{ pkgs ? import <nixpkgs> {}, version ? "0.4.0", ghc ? "8.8.3", platform ? "Linux" }:

with pkgs;

let
refs = builtins.fromJSON (builtins.readFile ./sources.json);

gunzip = src:
  let
  builder = writeShellScript
    "gunzip-builder"
    ''
      ${gzip}/bin/gzip -d -c ${src} > $out
    '';
  in
  builtins.derivation {
    system = builtins.currentSystem;
    name = "gunzip";
    inherit builder;
  };

hls-wrapper = gunzip (fetchurl {
  curlOpts = ["-L"];
  url = refs."${version}"."${platform}".wrapper.url;
  sha256 = refs."${version}"."${platform}".wrapper.hash;
});

hls-ghc = gunzip (fetchurl {
  curlOpts = ["-L"];
  url = refs."${version}"."${platform}".ghcs."${ghc}".url;
  sha256 = refs."${version}"."${platform}".ghcs."${ghc}".hash;
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
  system = builtins.currentSystem;
  name = "haskell-language-server-${version}-for-${ghc}-on-${platform}";

  inherit builder;
}
