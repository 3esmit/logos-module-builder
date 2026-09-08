# Test runner for logos-module-builder
# Unit assertions are pure Nix evaluation; validationChecks adds boundary probes.
# Usage: nix build .#checks.<system>.default
{ pkgs, lib, parseMetadata, common, mkExternalLib, fixturesRoot ? ./fixtures, validationChecks ? [] }:

let
  # Helper: assert with message. Throws on failure.
  assertEq = name: actual: expected:
    if actual == expected then true
    else builtins.throw "FAIL ${name}: expected ${builtins.toJSON expected}, got ${builtins.toJSON actual}";

  assertBool = name: actual: expected:
    if actual == expected then true
    else builtins.throw "FAIL ${name}: expected ${builtins.toString expected}, got ${builtins.toString actual}";

  assertHasAttr = name: attrset: key:
    if builtins.hasAttr key attrset then true
    else builtins.throw "FAIL ${name}: missing attribute '${key}' in ${builtins.toJSON (builtins.attrNames attrset)}";

  assertThrows = name: expr:
    let
      result = builtins.tryEval (builtins.deepSeq expr expr);
    in
      if !result.success then true
      else builtins.throw "FAIL ${name}: expected expression to throw, but it succeeded with ${builtins.toJSON result.value}";

  # Import test modules
  parseMetadataTests = import ./test-parse-metadata.nix { inherit assertEq assertBool assertHasAttr assertThrows parseMetadata; };
  commonTests = import ./test-common.nix { inherit pkgs lib assertEq assertBool assertHasAttr common; };
  externalLibTests = import ./test-external-lib.nix { inherit assertEq assertBool mkExternalLib; };
  templateTests = import ./test-templates.nix { inherit assertEq assertBool assertHasAttr parseMetadata; builderRoot = ./..; };
  collectDepsTests = import ./test-collectAllModuleDeps.nix { inherit assertEq assertBool assertHasAttr common; };
  fixtureTests = import ./test-fixtures.nix { inherit assertEq assertBool assertHasAttr parseMetadata fixturesRoot; };
  hostCodegenTests = import ./test-host-codegen.nix { inherit lib assertBool parseMetadata; };

  # Collect all test results into a list of bools (all must be true)
  allTests = parseMetadataTests ++ commonTests ++ externalLibTests ++ templateTests ++ collectDepsTests ++ fixtureTests ++ hostCodegenTests;

  # Force evaluation of all tests
  allPassed = builtins.deepSeq allTests (builtins.length allTests);

in pkgs.runCommand "logos-module-builder-tests" {} ''
  echo "Running logos-module-builder tests..."
  echo "All ${builtins.toString allPassed} tests passed."
  mkdir -p $out
  ${lib.concatMapStringsSep "\n" (check: "test -f ${check}/results.txt") validationChecks}
  echo "${builtins.toString allPassed} tests passed" > $out/results.txt
''
