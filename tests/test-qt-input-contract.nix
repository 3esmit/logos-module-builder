# Exercise actual public builder imports, including omitted and explicit-null
# inputs. Non-Qt outputs must remain lazy and identical to the normal import.
{ pkgs, inputs }:
let
  lib = pkgs.lib;
  args = builtins.intersectAttrs (builtins.functionArgs (import ../lib)) inputs // {
    inherit lib;
    builderRoot = ../.;
    uiBackend = inputs.logos-plugin-qt.rawLib or inputs.logos-plugin-qt.lib;
    coreBackend = inputs.logos-plugin-core.rawLib or inputs.logos-plugin-core.lib;
  };
  complete = import ../lib args;
  omitted = import ../lib (builtins.removeAttrs args [ "logos-plugin-qt" ]);
  explicitNull = import ../lib (args // { logos-plugin-qt = null; });
  system = pkgs.stdenv.hostPlatform.system;
  modules = builder: {
    core = builder.mkLogosModule {
      src = ../templates/minimal-module;
      configFile = ../templates/minimal-module/metadata.json;
    };
    ui = builder.mkLogosQmlModule {
      src = ../templates/ui-qml-backend;
      configFile = ../templates/ui-qml-backend/metadata.json;
    };
    qml = builder.mkLogosQmlModule {
      src = ./fixtures/qml-module;
      configFile = ./fixtures/qml-module/metadata.json;
    };
    rust = builder.mkLogosModule {
      src = ./fixtures/rust-native-dep;
      configFile = ./fixtures/rust-native-dep/metadata.json;
    };
    tests = builder.mkLogosModuleTests {
      src = ./fixtures/test-framework-module;
      testDir = ./fixtures/test-framework-module/tests;
      configFile = ./fixtures/test-framework-module/metadata.json;
    };
  };
  normal = modules complete;
  withoutQt = [ (modules omitted) (modules explicitNull) ];
  check = name: condition: if condition then true else throw "Qt input contract: ${name}";
  rejects = name: value:
    check name (!(builtins.tryEval value.drvPath).success);
  checksFor = m: [
    (rejects "core package requires Qt host" m.core.packages.${system}.lib)
    (rejects "core generator requires Qt host" m.core.packages.${system}.generate)
    (rejects "core dev shell requires Qt host" m.core.devShells.${system}.default)
    (rejects "UI backend requires Qt host" m.ui.packages.${system}.default)
    (rejects "UI generator requires Qt host" m.ui.packages.${system}.generate)
    (rejects "UI dev shell requires Qt host" m.ui.devShells.${system}.default)
    (rejects "module tests require Qt host" m.tests.${system}.unit-tests)
    (check "QML-only package unchanged" (m.qml.packages.${system}.default.drvPath == normal.qml.packages.${system}.default.drvPath))
    (check "core LIDL unchanged" (m.core.packages.${system}.lidl.drvPath == normal.core.packages.${system}.lidl.drvPath))
    (check "Rust LIDL unchanged" (m.rust.packages.${system}.lidl.drvPath == normal.rust.packages.${system}.lidl.drvPath))
  ];
  count = builtins.deepSeq (lib.concatMap checksFor withoutQt) (builtins.length withoutQt * 10);
  preserved = builtins.head withoutQt;
in pkgs.runCommand "qt-input-contract-tests" {} ''
  # Realize the unchanged non-Qt outputs too; merely constructing an attrset
  # would not prove the optional input stays lazy through derivation creation.
  test -f ${preserved.qml.packages.${system}.default}/lib/Main.qml
  test -f ${preserved.core.packages.${system}.lidl}/minimal.lidl
  test -f ${preserved.rust.packages.${system}.lidl}/rust_native_dep_module.lidl
  mkdir -p $out
  echo "${toString count} Qt input contracts passed" | tee $out/results.txt
''
