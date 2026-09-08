# Exercise real builder return values; only package artifacts are substituted
# so these dependency-graph contracts require no C++ compilation.
{ assertEq, common, mkLogosModule, mkLogosQmlModule, fixturesRoot }:

let
  system = "x86_64-linux";
  leaf = {
    packages.${system}.lgx = "leaf-lgx";
    config.dependencies = [];
  };
  artifact = name: module: module // {
    packages.${system}.lgx = "${name}-lgx";
  };
  core = artifact "core" (mkLogosModule {
    src = fixturesRoot + "/core-module";
    configFile = fixturesRoot + "/core-module/metadata.json";
    configOverrides.dependencies = [ "leaf" ];
    flakeInputs = { inherit leaf; };
  });
  view = fixture: artifact "view" (mkLogosQmlModule {
    src = fixturesRoot + "/${fixture}";
    configFile = fixturesRoot + "/${fixture}/metadata.json";
    configOverrides.dependencies = [ "core" ];
    flakeInputs = { inherit core; };
  });
  qml = view "qml-module";
  backend = view "ui-qml-backend-module";
  collect = input: common.collectAllModuleDeps system { dep = input; } [ "dep" ];
  wrongLeaf = leaf // { packages.${system}.lgx = "wrong-lgx"; };
  emptyCore = mkLogosModule {
    src = fixturesRoot + "/core-module";
    configFile = fixturesRoot + "/core-module/metadata.json";
  };
  emptyView = mkLogosQmlModule {
    src = fixturesRoot + "/qml-module";
    configFile = fixturesRoot + "/qml-module/metadata.json";
  };
in [
  (assertEq "composed core retains its provider"
    (collect core) { dep = "core-lgx"; leaf = "leaf-lgx"; })
  (assertEq "composed QML retains both dependency levels"
    (collect qml) { dep = "view-lgx"; core = "core-lgx"; leaf = "leaf-lgx"; })
  (assertEq "composed backend view retains both dependency levels"
    (collect backend) { dep = "view-lgx"; core = "core-lgx"; leaf = "leaf-lgx"; })
  (assertEq "normal flake can contain a composed dependency"
    (collect {
      packages.${system}.lgx = "outer-lgx";
      config.dependencies = [ "view" ];
      inputs.view = qml;
    }) { dep = "outer-lgx"; view = "view-lgx"; core = "core-lgx"; leaf = "leaf-lgx"; })
  (assertEq "module inputs take precedence over outer flake inputs"
    (collect (core // { inputs.leaf = wrongLeaf; })).leaf "leaf-lgx")
  (assertEq "direct input still overrides composed transitive input"
    (common.collectAllModuleDeps system {
      inherit core;
      leaf = wrongLeaf;
    } [ "core" "leaf" ]).leaf "wrong-lgx")
  (assertEq "core with no inputs exports an empty map" emptyCore.moduleInputs {})
  (assertEq "QML with no inputs exports an empty map" emptyView.moduleInputs {})
]
