# Preserve the pinned importer's lock/hash and Cargo source handling, changing
# only crates.io's outdated API download base to the index-advertised CDN base.
{ pkgs, rustPlatform }:
rustPlatform.importCargoLock.override {
  fetchurl = args: pkgs.fetchurl (args // {
    url =
      let prefix = "https://crates.io/api/v1/crates/";
      in if pkgs.lib.hasPrefix prefix args.url then
        "https://static.crates.io/crates/" + pkgs.lib.removePrefix prefix args.url
      else args.url;
  });
}
