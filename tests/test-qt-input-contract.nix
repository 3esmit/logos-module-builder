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
  viewOmitted = import ../lib (builtins.removeAttrs args [ "logos-view-module" ]);
  viewExplicitNull = import ../lib (args // { logos-view-module = null; });
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
  check = name: condition: if condition then true else throw "Qt input contract: ${name}";
  force = builder: moduleName: output:
    builtins.tryEval (
      let module = (modules builder).${moduleName};
      in module.packages.${system}.${output}.drvPath
    );
  forceDevShell = builder: moduleName:
    builtins.tryEval ((modules builder).${moduleName}.devShells.${system}.default.drvPath);
  forceTests = builder:
    builtins.tryEval ((modules builder).tests.${system}.unit-tests.drvPath);
  rejects = name: result: check name (!result.success);
  preserves = name: result: expected:
    check name (result.success && result.value == expected);
  normalQml = force complete "qml" "default";
  normalCoreLidl = force complete "core" "lidl";
  normalRustLidl = force complete "rust" "lidl";
  withoutQt = [ omitted explicitNull ];
  qtChecks = builder: [
    (rejects "core package requires Qt host" (force builder "core" "lib"))
    (rejects "core generator requires Qt host" (force builder "core" "generate"))
    (rejects "core dev shell requires Qt host" (forceDevShell builder "core"))
    (rejects "UI backend requires Qt host" (force builder "ui" "default"))
    (rejects "UI generator requires Qt host" (force builder "ui" "generate"))
    (rejects "UI dev shell requires Qt host" (forceDevShell builder "ui"))
    (rejects "module tests require Qt host" (forceTests builder))
    (preserves "QML-only package unchanged" (force builder "qml" "default") normalQml.value)
    (preserves "core LIDL unchanged" (force builder "core" "lidl") normalCoreLidl.value)
    (preserves "Rust LIDL unchanged" (force builder "rust" "lidl") normalRustLidl.value)
  ];
  viewChecks = builder: [
    (rejects "core package requires view templates" (force builder "core" "lib"))
    (rejects "UI backend requires view templates" (force builder "ui" "default"))
    (preserves "QML-only package unchanged without view module"
      (force builder "qml" "default") normalQml.value)
    (preserves "core LIDL unchanged without view module"
      (force builder "core" "lidl") normalCoreLidl.value)
    (preserves "Rust LIDL unchanged without view module"
      (force builder "rust" "lidl") normalRustLidl.value)
  ];
  count = builtins.deepSeq
    ((lib.concatMap qtChecks withoutQt) ++ (lib.concatMap viewChecks [ viewOmitted viewExplicitNull ]))
    ((builtins.length withoutQt * 10) + 10);
  preserved = modules (builtins.head withoutQt);
in pkgs.runCommand "qt-input-contract-tests" {} ''
  # Realize the unchanged non-Qt outputs too; merely constructing an attrset
  # would not prove the optional input stays lazy through derivation creation.
  test -f ${preserved.qml.packages.${system}.default}/lib/Main.qml
  test -f ${preserved.core.packages.${system}.lidl}/minimal.lidl
  test -f ${preserved.rust.packages.${system}.lidl}/rust_native_dep_module.lidl
  mkdir -p $out
  echo "${toString count} Qt input contracts passed" | tee $out/results.txt
''
