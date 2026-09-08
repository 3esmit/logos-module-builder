# Shared C++ types cross all three linked consumers. Source equality alone
# misses a same-revision SDK rebuilt with different transitive inputs.
{ pkgs, system, inputs }:
let
  consumers = {
    standalone = inputs.logos-standalone-app.inputs;
    view-runtime = inputs.logos-view-module-runtime.inputs;
    core = inputs.logos-standalone-app.inputs.logos-liblogos.inputs;
  };
  sdkNames = [ "logos-cpp-sdk" "logos-qt-sdk" "logos-protocol" ];
  checks = builtins.concatLists (map (consumer:
    map (sdk:
      let
        expected = inputs.${sdk};
        actual = consumers.${consumer}.${sdk};
      in
      if actual.outPath != expected.outPath then
        throw "ui-sdk-inputs (${system}): ${consumer}/${sdk} must share the builder's source"
      else if actual.packages.${system}.default.drvPath != expected.packages.${system}.default.drvPath then
        throw "ui-sdk-inputs (${system}): ${consumer}/${sdk} must share the builder's package inputs"
      else true
    ) sdkNames
  ) (builtins.attrNames consumers));
in builtins.deepSeq checks (pkgs.runCommand "ui-sdk-input-tests" {} ''
  mkdir -p $out
  echo "9 shared SDK/protocol contracts passed" > $out/results.txt
'')
