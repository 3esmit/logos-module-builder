# Provider glue belongs to the Qt host; UI glue remains an SDK operation.
{ lib, assertBool, parseMetadata }:
let
  codegen = import ../lib/modulePreConfigure.nix { inherit lib; };
  config = fields: parseMetadata.parseModuleConfig (builtins.toJSON ({
    name = "probe_module";
    version = "1.0.0";
    interface = "universal";
  } // fields));
  universal = codegen.autoCodegen (config {});
  multi = codegen.autoCodegen (config { concurrency = "multi"; });
  cdylib = codegen.autoCodegen (config {
    interface = "cdylib";
    codegen.lidl = "probe.lidl";
  });
  ui = codegen.autoCodegen (config { type = "ui_qml"; });
in [
  (assertBool "universal uses host generator" (lib.hasInfix "logos-qt-host-generator --lidl" universal) true)
  (assertBool "universal preserves C ABI generator" (lib.hasInfix "logos-cpp-generator" universal) true)
  (assertBool "multi reaches provider generator" (lib.hasInfix "--concurrency multi" multi) true)
  (assertBool "single does not opt into multi" (lib.hasInfix "--concurrency multi" universal) false)
  (assertBool "cdylib uses host generator" (lib.hasInfix "logos-qt-host-generator --lidl" cdylib) true)
  (assertBool "cdylib preserves backend flag" (lib.hasInfix "--backend cdylib" cdylib) true)
  (assertBool "universal never uses retired SDK backend" (lib.hasInfix "logos-qt-generator --lidl" universal) false)
  (assertBool "cdylib never uses retired SDK backend" (lib.hasInfix "logos-qt-generator --lidl" cdylib) false)
  (assertBool "UI uses SDK UI generator" (lib.hasInfix "logos-qt-generator --backend ui" ui) true)
  (assertBool "UI never uses provider generator" (lib.hasInfix "logos-qt-host-generator" ui) false)
]
