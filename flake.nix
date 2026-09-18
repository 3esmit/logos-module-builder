{
  description = "Logos Module Builder - Shared library for building Logos modules with minimal boilerplate";

  inputs = {
    logos-nix.url = "github:logos-co/logos-nix";
    # Optional newer rustc for crates whose deps out-pace the nixpkgs rustc
    # (opt-in per module via metadata `nix.rust.toolchain`).
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    # SDK and module deps — owned by this builder, injected into backends.
    #
    # Keep the maintained SDK fork pinned until its compatibility changes land
    # upstream.
    logos-cpp-sdk.url = "github:3esmit/logos-cpp-sdk?rev=a4b7550470b0ad874bb7c20ed95df8e5a7bdd8c8";
    logos-cpp-sdk.inputs.logos-nix.follows = "logos-nix";
    logos-cpp-sdk.inputs.logos-protocol.follows = "logos-protocol";
    # Protocol layer (transports + lp_* C ABI + the protocol semver every
    # module gets stamped with) and the Qt developer layer modules link.
    #
    # Keep protocol ABI and host-service additions aligned with the SDK fork.
    logos-protocol.url = "github:3esmit/logos-protocol?rev=3f307064aea1a7a6747f0374b8216c0549d1aceb";
    logos-protocol.inputs.logos-nix.follows = "logos-nix";
    # Match the Qt generator to the maintained SDK and protocol revisions.
    logos-qt-sdk.url = "github:3esmit/logos-qt-sdk?rev=3b68867920c89d54edbc8fca39340dcc8efe4cd8";
    logos-qt-sdk.inputs.logos-protocol.follows = "logos-protocol";
    logos-qt-sdk.inputs.logos-cpp-sdk.follows = "logos-cpp-sdk";
    # The Qt generator compiles the C++ SDK's shared backend helpers, which
    # include the canonical identity API. Use the same logos-lidl revision as
    # the SDK instead of letting the transitive Qt input drift independently.
    logos-qt-sdk.inputs.logos-lidl.follows = "logos-cpp-sdk/logos-lidl";
    # And its logos-plugin-qt, for the same reason the two follows above exist,
    # with a sharper failure mode. logos-qt-sdk carries its OWN logos-plugin-qt;
    # without this it built at a different rev from ours while being FED our
    # logos-protocol by the follows above. That is not a stale-pin annoyance —
    # logos_consumer.h upper-bounds the protocol MINOR it admits consumers
    # against, so a plugin-qt older than our protocol is a COMPILE ERROR, and the
    # closure carries two logos-qt-host builds besides. Measured on protocol 0.9:
    # ours resolved to the raised bound while this one stayed three revs back and
    # failed the build.
    logos-qt-sdk.inputs.logos-plugin-qt.follows = "logos-plugin-qt";
    logos-module.url = "github:logos-co/logos-module";
    # UI modules (type: ui, ui_qml) always use Qt.
    #
    # This backend also owns the Qt HOST RUNTIME every plugin links
    # (packages.<sys>.logos-qt-host), so its logos-protocol input is now
    # load-bearing and must be the SAME logos-protocol the module links —
    # exactly the reason logos-qt-sdk above carries the same `follows`. Two
    # protocol builds on one link line means two TokenManager singletons.
    #
    # Keep the host runtime and generator revision used by the forked SDKs.
    # The maintained fork carries explicit target-instance routing required by
    # capability-module when one host exposes multiple instances of a module.
    logos-plugin-qt.url = "github:3esmit/logos-plugin-qt?rev=49d9bcfa840cc9d0eaeafc46cee76e51cddef40b";
    logos-plugin-qt.inputs.logos-nix.follows = "logos-nix";
    logos-plugin-qt.inputs.logos-lidl.follows = "logos-cpp-sdk/logos-lidl";
    logos-plugin-qt.inputs.logos-protocol.follows = "logos-protocol";
    # Core modules use the exact same backend closure as UI modules.
    logos-plugin-core.follows = "logos-plugin-qt";
    nix-bundle-lgx.url = "github:logos-co/nix-bundle-lgx";
    nix-bundle-logos-module-install.url = "github:logos-co/nix-bundle-logos-module-install";
    nix-bundle-logos-module-install.inputs.nix-bundle-lgx.follows = "nix-bundle-lgx";
    # Host shell used by `nix run` / integration tests for ui_qml modules.
    # Design system + view-module-runtime are pinned HERE (not only inside
    # standalone's lock) so a bump for module testing is one lock update on
    # this flake — no standalone release required.
    logos-design-system.url = "github:logos-co/logos-design-system";
    logos-design-system.inputs.logos-nix.follows = "logos-nix";
    logos-view-module-runtime.url = "github:3esmit/logos-view-module-runtime?rev=6925d8bc2c5fa9da60ee30b32c036c2e3e1bcb4b";
    logos-view-module-runtime.inputs.logos-cpp-sdk.follows = "logos-cpp-sdk";
    logos-view-module-runtime.inputs.logos-protocol.follows = "logos-protocol";
    # The MODULE side of that same pair, and the ui_qml authoring flavour as a
    # whole: LogosViewModule.cmake, the four LogosView*.in templates
    # logos_module(REP_FILE ...) instantiates, and the view glue generator.
    # They used to live in logos-plugin-qt; that backend is now exclusively
    # what makes a cdylib module loadable by logos-module-loader-qt, so the
    # authoring half moved to the repo that owns it end to end.
    #
    # Two things here consume it, and they want the SAME bytes: the
    # `view-interface-abi` check below reads
    # packages.<sys>.logos-view-templates/LogosView*.h.in directly, and
    # lib/{mkLogosModule,buildCppPlugin}.nix hand that same store path to
    # every plugin build as LOGOS_VIEW_TEMPLATE_DIR (cmake flag + env var),
    # because cmake/LogosModule.cmake here refuses to guess.
    #
    # ACYCLIC: logos-view-module is a LEAF — its only input is logos-nix, so it
    # cannot reach back to this builder. That is the property that let the
    # templates move at all; logos-plugin-qt could not host both consumers
    # without one of them depending on the other the wrong way round.
    #
    # Rev-pinned for the same reason logos-plugin-qt is: `nix flake update` must
    # not be able to walk this back to a commit without
    # packages.<sys>.logos-view-templates, which `view-interface-abi` and every
    # ui_qml plugin build need. UNPINNED: 1f95a75 (the #2 merge that moved the
    # templates in) IS this repo's master tip, so the pin was already a no-op.
    # Keep the parser fix in the maintained fork until upstream incorporates it.
    logos-view-module.url = "github:3esmit/logos-view-module?rev=732a43472f18aa8ec4f8cff0cf10c0a0b3086ffd";
    logos-view-module.inputs.logos-nix.follows = "logos-nix";
    logos-liblogos.url = "github:3esmit/logos-liblogos?rev=8952610416c758fbb33f8eee7eac5074a506e361";
    logos-liblogos.inputs.logos-cpp-sdk.follows = "logos-cpp-sdk";
    logos-liblogos.inputs.logos-qt-sdk.follows = "logos-qt-sdk";
    logos-liblogos.inputs.logos-protocol.follows = "logos-protocol";
    # Keep the standalone host on the maintained fork while its consumer
    # admission fix is carried downstream. UI doc-tests rely on that host
    # registering each in-process view identity with capability_module before
    # the generated backend makes its first dependency call.
    logos-standalone-app.url = "github:3esmit/logos-standalone-app?rev=fdc5ff120a7e493749d7969af6b9f8cd137a0f71";
    logos-standalone-app.inputs.logos-cpp-sdk.follows = "logos-cpp-sdk";
    logos-standalone-app.inputs.logos-protocol.follows = "logos-protocol";
    logos-standalone-app.inputs.logos-liblogos.follows = "logos-liblogos";
    logos-standalone-app.inputs.logos-design-system.follows = "logos-design-system";
    logos-standalone-app.inputs.logos-view-module-runtime.follows = "logos-view-module-runtime";
    # Test framework for module unit tests.
    #
    logos-test-framework.url = "github:logos-co/logos-test-framework/5f75c9418b7c842f1750bfde31accf3d0cba283d";
    logos-test-framework.inputs.logos-cpp-sdk.follows = "logos-cpp-sdk";
    logos-test-framework.inputs.logos-qt-sdk.follows = "logos-qt-sdk";
    logos-test-framework.inputs.logos-plugin-qt.follows = "logos-plugin-qt";
    logos-test-framework.inputs.logos-protocol.follows = "logos-protocol";
    # The Rust SDK provides logos-lidl-gen (the generator the builder runs for
    # codegen.rust modules) and the SDK source the crate links. logos-rust-sdk
    # depends BACK on this builder for its own integration tests, so its
    # logos-module-builder input is cut with `follows` to break the cycle — we
    # only consume its lidl-gen package + source tree, never its tests. The other
    # branch-pinned test-only inputs are cut too so they aren't fetched.
    #
    logos-rust-sdk.url = "github:logos-co/logos-rust-sdk/b572e8172ca512b41c102d555f00258b859629c0";
    logos-rust-sdk.inputs.logos-nix.follows = "logos-nix";
    logos-rust-sdk.inputs.logos-lidl.follows = "logos-cpp-sdk/logos-lidl";
    logos-rust-sdk.inputs.logos-module-builder.follows = "logos-cpp-sdk";
    logos-rust-sdk.inputs.logos-logoscore-cli.follows = "logos-cpp-sdk";
    logos-rust-sdk.inputs.logos-protocol.follows = "logos-protocol";
    nixpkgs.follows = "logos-nix/nixpkgs";
  };

  outputs = inputs@{ self, nixpkgs, logos-nix, logos-cpp-sdk, logos-protocol, logos-qt-sdk, logos-module, logos-plugin-qt, logos-plugin-core, logos-view-module, logos-view-module-runtime, logos-liblogos, logos-design-system, nix-bundle-logos-module-install, nix-bundle-lgx, logos-standalone-app, logos-test-framework, logos-rust-sdk, rust-overlay ? null, ... }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f {
        inherit system;
        pkgs = import nixpkgs { inherit system; };
      });

      # Import the library functions
      # Use rawLib from backends — we inject logos-cpp-sdk/logos-module ourselves
      lib = import ./lib {
        inherit nixpkgs nix-bundle-lgx nix-bundle-logos-module-install logos-standalone-app;
        inherit logos-nix;
        inherit logos-cpp-sdk logos-protocol logos-qt-sdk logos-module logos-test-framework logos-rust-sdk;
        # The FLAKE, not its lib: the cdylib glue generator is a package of it.
        inherit logos-plugin-qt;
        # Likewise a FLAKE, for packages.<sys>.logos-view-templates — the
        # LOGOS_VIEW_TEMPLATE_DIR every ui_qml plugin build is handed.
        inherit logos-view-module;
        inherit rust-overlay;
        inherit (nixpkgs) lib;
        uiBackend = logos-plugin-qt.rawLib or logos-plugin-qt.lib;
        coreBackend = logos-plugin-core.rawLib or logos-plugin-core.lib;
        builderRoot = ./.;
      };
    in
    {
      # Export the library functions for use by modules
      lib = lib;

      # The logos-rust-sdk source tree at the rev this builder pins — exposed so a
      # codegen.rust module can stage it as `../logos-rust-sdk-src` to generate its
      # Cargo.lock against the SAME SDK the builder links, without needing a
      # logos-rust-sdk input in the module's own flake.
      packages = forAllSystems ({ pkgs, ... }: {
        rust-sdk-src = pkgs.runCommand "logos-rust-sdk-src" {} "cp -r ${logos-rust-sdk} $out";
      });

      # Also expose as an overlay for convenience
      overlays.default = final: prev: {
        logosModuleBuilder = lib;
      };

      # Templates for scaffolding new modules
      templates = {
        default = {
          path = ./templates/minimal-module;
          description = "Minimal Logos module template";
        };

        with-external-lib = {
          path = ./templates/external-lib-module;
          description = "Logos module template with external library";
        };

        ui-qml-backend = {
          path = ./templates/ui-qml-backend;
          description = "Logos ui_qml module with C++ backend (process-isolated) and QML view";
        };

        ui-qml = {
          path = ./templates/ui-qml;
          description = "Logos ui_qml module (QML-only, no C++ backend)";
        };

        rust = {
          path = ./templates/rust-module;
          description = "Minimal Logos module written in Rust";
        };

        rust-with-external-lib = {
          path = ./templates/rust-external-lib-module;
          description = "Logos module written in Rust, linking an external C library";
        };
      };

      # Tests — mostly pure Nix evaluation, but NOT entirely: test-platform-triples
      # instantiates five package sets (including the mingw cross) to assert the
      # os/architecture/abi table against reality rather than against itself.
      checks = forAllSystems ({ pkgs, system, ... }: {
        rust-crate-downloads = import ./tests/test-rust-crate-downloads.nix {
          inherit pkgs inputs;
        };
        design-system-input = import ./tests/test-design-system-input.nix {
          inherit pkgs system logos-nix logos-design-system logos-standalone-app;
        };
        ui-sdk-inputs = import ./tests/test-ui-sdk-inputs.nix {
          inherit pkgs system inputs;
        };
        ui-sdk-contract = import ./tests/test-ui-sdk-contract.nix {
          inherit pkgs system;
        };
        rust-module-load = import ./tests/test-rust-module-load.nix {
          inherit pkgs;
          mkLogosModule = lib.mkLogosModule;
          fixturesRoot = ./tests/fixtures;
        };
        default = import ./tests {
          inherit pkgs;
          inherit (nixpkgs) lib;
          inherit (lib) parseMetadata common mkExternalLib mkLogosModule mkLogosQmlModule;
          validationChecks = [
            self.checks.${system}.rust-crate-downloads
            self.checks.${system}.ui-sdk-inputs
            self.checks.${system}.ui-sdk-contract
            self.checks.${system}.qt-host-repoint
            self.checks.${system}.host-codegen-wiring
            self.checks.${system}.doctest-source
            self.checks.${system}.template-helper-precedence
            self.checks.${system}.rust-module-load
          ];
        };
        # Integration test: actually builds a QML module from a fixture
        qml-integration = import ./tests/test-qml-integration.nix {
          inherit pkgs;
          mkLogosQmlModule = lib.mkLogosQmlModule;
          mkLogosModule = lib.mkLogosModule;
          fixturesRoot = ./tests/fixtures;
        };
        # Integration test: builds and runs unit tests via logos-test-framework
        test-framework-integration = import ./tests/test-framework-integration.nix {
          inherit pkgs;
          mkLogosModuleTests = lib.mkLogosModuleTests;
          inherit (lib) parseMetadata;
          fixturesRoot = ./tests/fixtures;
        };
        # Unit tests linking two shared external libraries: one rpath entry per lib dir.
        external-lib-rpath = import ./tests/test-external-lib-rpath.nix {
          inherit pkgs;
          mkLogosModuleTests = lib.mkLogosModuleTests;
          fixturesRoot = ./tests/fixtures;
        };
        # #lgx and #install carry the runtime closure of the plugin they package.
        install-closure = import ./tests/test-install-closure.nix {
          inherit pkgs;
          mkLogosModule = lib.mkLogosModule;
          fixturesRoot = ./tests/fixtures;
          runtimeLib = (lib.common.mkPkgs system).jansson.out;
        };
        # Integration test: verifies static library (.a) support in EXTERNAL_LIBS
        static-extlib = import ./tests/test-static-extlib.nix {
          inherit pkgs;
        };
        # A flake-input library with nested headers and lib/cmake/, staged the
        # same way for the module build and for mkLogosModuleTests.
        external-lib-flake = import ./tests/test-external-lib-flake.nix {
          inherit pkgs;
          inherit (lib) mkLogosModule mkLogosModuleTests;
          fixturesRoot = ./tests/fixtures;
        };
        # WHICH Qt host runtime logos_module() links, and that a root with no
        # host runtime in it is a hard error rather than a silent skip.
        qt-host-repoint = import ./tests/test-qt-host-repoint.nix {
          inherit pkgs;
        };
        host-codegen-wiring = import ./tests/test-host-codegen-wiring.nix {
          inherit pkgs logos-plugin-qt;
          inherit (lib) common mkLogosModule mkLogosQmlModule;
        };
        template-helper-precedence = import ./tests/test-template-helper-precedence.nix {
          inherit pkgs;
        };
        doctest-source = pkgs.runCommand "doctest-source-tests" {
          nativeBuildInputs = [ pkgs.python3 ];
        } ''
          export PYTHONDONTWRITEBYTECODE=1
          python3 -m unittest discover -s ${./.}/tests -p 'test_prepare_doctests.py'
          mkdir -p $out
          echo passed > $out/results.txt
        '';
        # The module-side and host-side declarations of the view plugin
        # interfaces must agree. Two copies that cannot be merged, bound only
        # by an IID string, where a mismatch is silent — see the file header.
        # This repo is the only one that sees both sides.
        view-interface-abi = import ./tests/test-view-interface-abi.nix {
          inherit pkgs;
          viewTemplates =
            logos-view-module.packages.${system}.logos-view-templates
              or (throw ("logos-module-builder: the pinned logos-view-module "
                + "predates packages.<sys>.logos-view-templates, so the "
                + "LogosView*.in templates cannot be located. Bump the "
                + "logos-view-module input — the templates moved OUT of "
                + "logos-plugin-qt into it, so neither logos-plugin-qt nor "
                + "logos-protocol is the pin to touch."));
          viewRuntime = logos-view-module-runtime;
        };
        # Integration test: a Rust cdylib module with an external system build dep
        # declared via the `nix.rust` block — proves pkg-config/openssl-style deps
        # reach the crate's buildRustPackage compile.
        rust-native-dep = import ./tests/test-rust-native-dep.nix {
          inherit pkgs;
          mkLogosModule = lib.mkLogosModule;
          fixturesRoot = ./tests/fixtures;
        };
        # Ground truth for the module-impl C ABI: BUILD a module per language
        # backend and read the resulting plugin's symbol table. The per-backend
        # source checks (logos-cpp-sdk#144, logos-rust-sdk#46) validate each
        # EMITTER; only this repo sees the carrier that hands the emitter its
        # protocol version, and only an artifact shows what actually compiled
        # in. See the file header.
        # A universal module with optional_dependencies, through the whole
        # writer -> reader universal glue (logos-plugin-qt#37).
        universal-optional-deps = import ./tests/test-universal-optional-deps.nix {
          inherit pkgs;
          mkLogosModule = lib.mkLogosModule;
          fixturesRoot = ./tests/fixtures;
          templatesRoot = ./templates;
        };
        module-impl-abi-nm =
          let
            moduleImplAbi = logos-protocol.packages.${system}.module-impl-abi or null;
          in
            if moduleImplAbi == null then
              pkgs.runCommand "module-impl-abi-nm-skipped" {} ''
                echo "logos-protocol does not publish module-impl-abi; ABI artifact check skipped"
                mkdir -p "$out"
                echo "skipped: module-impl-abi unavailable" > "$out/results.txt"
              ''
            else
              import ./tests/test-module-impl-abi-nm.nix {
                inherit pkgs moduleImplAbi;
                mkLogosModule = lib.mkLogosModule;
                fixturesRoot = ./tests/fixtures;
                templatesRoot = ./templates;
              };
      });

      # Development shell for working on the builder itself
      devShells = forAllSystems ({ pkgs, system, ... }:
        let
          logosSdk = logos-cpp-sdk.packages.${system}.default;
          logosModule = logos-module.packages.${system}.default;
          uiLib = logos-plugin-qt.rawLib or logos-plugin-qt.lib;
          backendShell = uiLib.devShellInputs pkgs { inherit logosModule; };
        in {
          default = pkgs.mkShell {
            nativeBuildInputs = backendShell.nativeBuildInputs ++ [
              logosSdk
              pkgs.yq  # For YAML parsing in scripts
            ];
            buildInputs = backendShell.buildInputs;
            shellHook = ''
              ${backendShell.shellHook}
              export LOGOS_CPP_SDK_ROOT="${logosSdk}"
              # The backend stopped exporting this when the templates left it.
              # Text files with no platform dimension, so plain `${system}`
              # here is fine — this flake's `systems` list is native-only.
              export LOGOS_VIEW_TEMPLATE_DIR="${logos-view-module.packages.${system}.logos-view-templates}"
              echo "Logos Module Builder development environment"
            '';
          };
        }
      );
    };
}
