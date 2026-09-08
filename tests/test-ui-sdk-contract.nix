# Prove each consumer/SDK edge rejects both kinds of skew, independently of
# whatever sources happen to be in the current lockfile.
{ pkgs, system }:
let
  names = [ "logos-cpp-sdk" "logos-qt-sdk" "logos-protocol" ];
  sdks = pkgs.lib.genAttrs names (name: {
    outPath = "/source/${name}";
    packages.${system}.default.drvPath = "/derivation/${name}";
  });
  inputs = sdks // {
    logos-standalone-app.inputs = sdks // { logos-liblogos.inputs = sdks; };
    logos-view-module-runtime.inputs = sdks;
  };
  paths = [
    [ "logos-standalone-app" "inputs" ]
    [ "logos-view-module-runtime" "inputs" ]
    [ "logos-standalone-app" "inputs" "logos-liblogos" "inputs" ]
  ];
  # Force the contract and derivation, not recursive derivation passthru attrs.
  accepts = candidate: (builtins.tryEval (builtins.seq
    (import ./test-ui-sdk-inputs.nix { inherit pkgs system; inputs = candidate; }).drvPath
    true)).success;
  rejected = builtins.concatLists (map (path:
    builtins.concatLists (map (name:
      map (change: !(accepts (pkgs.lib.recursiveUpdate inputs
        (pkgs.lib.setAttrByPath (path ++ [ name ]) change)))) [
          { outPath = "/wrong-source"; }
          { packages.${system}.default.drvPath = "/wrong-derivation"; }
        ]
    ) names)
  ) paths);
in
if !(accepts inputs) || !(builtins.all (value: value) rejected) then
  throw "ui-sdk-contract (${system}): positive or one of ${toString (builtins.length rejected)} negative fixtures failed"
else pkgs.runCommand "ui-sdk-contract-tests" {} ''
  mkdir -p $out
  echo "${toString (1 + builtins.length rejected)} SDK contract fixtures passed" > $out/results.txt
''
