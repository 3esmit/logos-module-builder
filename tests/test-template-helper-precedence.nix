# The generated module template must use the builder-owned helper whenever a
# Nix build supplies LOGOS_MODULE_BUILDER_ROOT, even if a stale local copy is
# present in the module source tree.
{ pkgs }:

let
  template = builtins.replaceStrings
    [ "@MODULE_NAME@" "@MODULE_SOURCES@" ]
    [ "precedence" "src/dummy.cpp" ]
    (builtins.readFile ../templates/CMakeLists.txt.template);
  builderHelper = pkgs.writeText "builder-LogosModule.cmake" ''
    message(STATUS "BUILDER_HELPER_SELECTED")
    function(logos_module)
    endfunction()
  '';
  localHelper = pkgs.writeText "local-LogosModule.cmake" ''
    message(STATUS "LOCAL_HELPER_SELECTED")
    function(logos_module)
    endfunction()
  '';
  project = pkgs.writeText "precedence-CMakeLists.txt" template;
in pkgs.runCommand "template-helper-precedence-tests" {
  nativeBuildInputs = [ pkgs.cmake pkgs.stdenv.cc ];
} ''
  set -euo pipefail
  mkdir -p project/cmake builder/cmake
  cp ${project} project/CMakeLists.txt
  cp ${localHelper} project/cmake/LogosModule.cmake
  cp ${builderHelper} builder/cmake/LogosModule.cmake

  LOGOS_MODULE_BUILDER_ROOT="$PWD/builder" cmake -S project -B build > configure.log 2>&1
  grep -q 'BUILDER_HELPER_SELECTED' configure.log
  if grep -q 'LOCAL_HELPER_SELECTED' configure.log; then
    echo "FAIL: generated template selected a stale module-local helper"
    cat configure.log
    exit 1
  fi

  mkdir -p $out
  echo "template helper precedence passed" > $out/results.txt
''
