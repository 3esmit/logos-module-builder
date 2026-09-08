# Evaluate real builder outputs without building cross-target libraries.
{ pkgs, common, mkLogosModule, mkLogosQmlModule, logos-plugin-qt }:
let
  lib = pkgs.lib;
  core = mkLogosModule {
    src = ../templates/minimal-module;
    configFile = ../templates/minimal-module/metadata.json;
  };
  ui = mkLogosQmlModule {
    src = ../templates/ui-qml-backend;
    configFile = ../templates/ui-qml-backend/metadata.json;
  };
  check = name: condition:
    if condition then true else throw "Host codegen wiring: ${name}";
  # Literal matching supports store-path string contexts without realizing them.
  hasText = needle: haystack: builtins.replaceStrings [needle] [""] haystack != haystack;
  forSystem = system:
    let
      buildSystem = common.buildSystemFor system;
      generator = logos-plugin-qt.packages.${buildSystem}.logos-qt-host-generator;
      runtime = logos-plugin-qt.packages.${system}.logos-qt-host;
      checkModule = name: module:
        let
          generated = module.packages.${system}.generate;
          shell = module.devShells.${system}.default;
          hasTool = drv: builtins.elem (toString generator) (map toString drv.nativeBuildInputs);
        in [
          (check "${name}/${system}: generate has build-platform host generator" (hasTool generated))
          (check "${name}/${system}: generate has target runtime" (generated.LOGOS_QT_HOST_ROOT == toString runtime))
          (check "${name}/${system}: dev shell has build-platform host generator" (hasTool shell))
          (check "${name}/${system}: dev shell exports target runtime" (hasText "export LOGOS_QT_HOST_ROOT=\"${runtime}\"" shell.shellHook))
          (check "${name}/${system}: dev shell exports builder CMake" (lib.hasInfix "export LOGOS_MODULE_BUILDER_ROOT=" shell.shellHook))
        ];
    in checkModule "core" core ++ checkModule "ui" ui;
  results = lib.concatMap forSystem common.systems;
  count = builtins.deepSeq results (builtins.length results);
in pkgs.runCommand "host-codegen-wiring-tests" {} ''
  mkdir -p $out
  echo "${toString count} host codegen wiring checks passed" | tee $out/results.txt
''
