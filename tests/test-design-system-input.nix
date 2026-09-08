# A QML module can build while its lazily evaluated standalone launcher is
# broken. Force the actual host/design-system package paths without launching
# a GUI or making native compilation part of this dependency contract check.
{ pkgs, system, logos-nix, logos-design-system, logos-standalone-app }:

assert logos-design-system.inputs.logos-nix.outPath == logos-nix.outPath;
assert logos-design-system.inputs.logos-nix.lib ? forAllTargets;
builtins.deepSeq [
  logos-design-system.packages.${system}.default.drvPath
  logos-standalone-app.packages.${system}.default.drvPath
] (pkgs.runCommand "design-system-input-tests" {} ''
  mkdir -p $out
  echo passed > $out/results.txt
'')
