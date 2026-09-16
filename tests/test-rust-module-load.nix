# Shared-library compilation permits unresolved symbols on supported platforms.
# Load the generated plugin eagerly and exercise its host-services C ABI.
{ pkgs, mkLogosModule, fixturesRoot }:
let
  module = mkLogosModule {
    src = fixturesRoot + "/rust-native-dep";
    configFile = fixturesRoot + "/rust-native-dep/metadata.json";
  };
  system = pkgs.stdenv.hostPlatform.system;
  plugin = "${module.packages.${system}.lib}/lib/rust_native_dep_module_plugin${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}";
in pkgs.runCommand "rust-module-load-tests" {
  nativeBuildInputs = [ pkgs.python3 ];
} ''
  export LOGOSCORE_CONFIG_DIR="$TMPDIR/logoscore"
  python3 - ${plugin} <<'PY'
  import ctypes, os, sys
  module = ctypes.CDLL(sys.argv[1], mode=os.RTLD_NOW | os.RTLD_LOCAL)
  grant = module.logos_module_grant_host_services
  grant.argtypes = [ctypes.c_char_p]
  grant.restype = ctypes.c_int
  keys = module.lp_token_keys
  keys.argtypes = []
  keys.restype = ctypes.c_void_p
  free = module.lp_string_free
  free.argtypes = [ctypes.c_void_p]
  free.restype = None
  def registry_open():
      pointer = keys()
      if not pointer:
          return False
      # The returned string is owned by this protocol image, not Python.
      free(pointer)
      return True
  assert not registry_open(), "ungranted module must start closed"
  # All non-null arguments are live, NUL-terminated byte strings for the call.
  for invalid in [None, b"not-json", b"{}", b"[7]", b'["unknown-service"]',
                  b'["token_registry", "unknown-service"]']:
      assert grant(invalid) != 0, "invalid grant must fail closed"
      assert not registry_open(), "invalid grant must not partially open a gate"
  assert grant(b'[]') == 0, "empty grant is valid"
  assert grant(b'["token_registry"]') == 0, "known host service must be accepted"
  assert registry_open(), "grant must reach this module image's gate"
  assert grant(b'["unknown-service"]') != 0
  assert registry_open(), "rejected replacement must preserve the previous grant"
  assert grant(b'[]') == 0
  assert not registry_open(), "empty replacement must revoke the grant"
  assert grant(b'["token_registry"]') == 0
  assert registry_open()
  assert grant(b'["token_delivery"]') == 0
  assert not registry_open(), "replacement must remove services not granted"
  assert grant(b'[]') == 0
  PY
  mkdir -p $out
  echo "generated Rust plugin load and host-service C ABI passed" > $out/results.txt
''
