# Exercise the real module builder's Cargo arguments, then its pinned importer.
# The compile boundary is replaced to isolate fetching from the module ABI.
{ pkgs, inputs }:
let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;
  builderArgs = builtins.intersectAttrs (builtins.functionArgs (import ../lib)) inputs // {
    inherit lib;
    builderRoot = ../.;
    uiBackend = inputs.logos-plugin-qt.rawLib or inputs.logos-plugin-qt.lib;
    coreBackend = inputs.logos-plugin-core.rawLib or inputs.logos-plugin-core.lib;
  };
  builder = import ../lib builderArgs;
  checksum = "12df2e0110f65b775f769bb17ef989067a1d931b2eb822bd4346631eeada89f9";
  lockContents = ''
    version = 4
    [[package]]
    name = "syn"
    version = "3.0.5"
    source = "registry+https://github.com/rust-lang/crates.io-index"
    checksum = "${checksum}"
  '';
  # Fetch probes retain every non-URL attribute and leave other registries alone.
  route = import ../lib/importCargoLock.nix {
    pkgs = pkgs // { fetchurl = args: args; };
    rustPlatform.importCargoLock.override = args: args.fetchurl;
  };
  fetchArgs = { name = "crate-syn-3.0.5.tar.gz"; sha256 = checksum; };
  urls = [
    [ "https://crates.io/api/v1/crates/syn/3.0.5/download" "https://static.crates.io/crates/syn/3.0.5/download" ]
    [ "https://registry.example/crates/syn/3.0.5/download" "https://registry.example/crates/syn/3.0.5/download" ]
    [ "https://crates.io/api/v1/crates-other/syn/3.0.5/download" "https://crates.io/api/v1/crates-other/syn/3.0.5/download" ]
  ];
  routeChecks = map (pair:
    if route (fetchArgs // { url = builtins.head pair; })
       == (fetchArgs // { url = builtins.elemAt pair 1; })
    then true else throw "rust-crate-downloads: URL routing changed hash or registry identity"
  ) urls;
  importer.override = fetchOverrides: lockArgs:
    if !(lockArgs.allowBuiltinFetchGit or false) || lockArgs ? extraRegistries then
      throw "rust-crate-downloads: Git policy or Cargo source configuration changed"
    else (pkgs.rustPlatform.importCargoLock.override fetchOverrides) (lockArgs // {
      lockFile = null; lockFileContents = lockContents;
    });
  captureRust = args:
    if args ? cargoLock || !(args ? cargoDeps) then
      throw "rust-crate-downloads: module must use the scoped Cargo importer"
    else pkgs.runCommand "rust-crate-source-config-test" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      python3 - ${args.cargoDeps}/.cargo/config.toml <<'PY'
      import sys, tomllib
      with open(sys.argv[1], "rb") as stream:
          config = tomllib.load(stream)
      assert set(config["source"]) == {"crates-io", "vendored-sources"}
      PY
      mkdir -p $out
    '';
  probePkgs = pkgs // {
    rustPlatform = pkgs.rustPlatform // { buildRustPackage = captureRust; importCargoLock = importer; };
    makeRustPlatform = _: { buildRustPackage = captureRust; importCargoLock = importer; };
    rust-bin.stable."1.96.0".default = pkgs.rustc;
  };
  moduleBuilder = import ../lib/mkLogosModule.nix
    (builtins.intersectAttrs (builtins.functionArgs (import ../lib/mkLogosModule.nix)) builderArgs // {
      inherit (builder) parseMetadata;
      common = builder.common // {
        mkPkgs = _: probePkgs;
        mkPkgsWith = _: _: probePkgs;
      };
      coreBackend.buildPlugin = args: { inherit (args) preConfigure; };
    });
  module = toolchain: moduleBuilder {
    src = ./fixtures/rust-native-dep;
    configFile = ./fixtures/rust-native-dep/metadata.json;
    configOverrides.nix_rust.toolchain = toolchain;
  };
  # String context realizes the imported crate even though compilation is mocked.
  preparations = map (toolchain: (module toolchain).packages.${system}.lib.preConfigure)
    [ null "1.96.0" ];
in builtins.deepSeq routeChecks (pkgs.runCommand "rust-crate-download-tests" {} ''
  ${lib.concatMapStringsSep "\n" (preparation: "test -n ${lib.escapeShellArg preparation}") preparations}
  mkdir -p $out
  echo "module download routing and checksum-verified syn import passed" > $out/results.txt
'')
