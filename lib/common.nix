# Common utilities shared across all builder functions (backend-agnostic)
# Qt-specific build deps and cmake flags now live in the plugin backend.
{ lib, nix-bundle-lgx ? null, nixpkgs ? null, logos-nix ? null }:

let
  # Recursively collect all module dependencies (direct + transitive) from flake
  # inputs, using each module's exported config.dependencies to walk the tree.
  # Returns a flat attrset: { moduleName = lgxDerivation; ... }
  # Uses the LGX package output (packages.lgx) which bundles the plugin plus
  # any external libraries it depends on.  When a dependency lacks packages.lgx,
  # it is automatically bundled into an LGX package using nix-bundle-lgx.
  #
  # system:   target system string (e.g. "x86_64-linux")
  # inputs:   flake inputs attrset to search for dependency modules
  # depNames: list of dependency name strings to resolve
  collectAllModuleDeps = system: inputs: depNames:
    let
      depInputs = lib.filterAttrs (n: _: builtins.elem n depNames) inputs;

      # Bundle a derivation into LGX on the fly using nix-bundle-lgx.
      # Fails fast if nix-bundle-lgx is unavailable — a silent fallback would
      # cause mkStandaloneApp to silently omit the dependency at runtime.
      autoBundleLgx = drv:
        if nix-bundle-lgx == null then
          builtins.throw "collectAllModuleDeps: dependency lacks packages.${system}.lgx and nix-bundle-lgx is not available to auto-bundle it. Either add an lgx output to the dependency or ensure nix-bundle-lgx is passed to common.nix."
        else if !(nix-bundle-lgx ? bundlers.${system}.default) then
          builtins.throw "collectAllModuleDeps: nix-bundle-lgx does not provide a bundler for system ${system}."
        else
          nix-bundle-lgx.bundlers.${system}.default drv;

      direct = lib.mapAttrs (depName: input:
        if input ? packages.${system}.lgx
        then input.packages.${system}.lgx
        else if input ? packages.${system}.lib
        then autoBundleLgx input.packages.${system}.lib
        else if input ? packages.${system}.default
        then autoBundleLgx input.packages.${system}.default
        # A flake that publishes `packages` but nothing usable for THIS system is
        # an error, not a fallback -- the same hazard the autoBundleLgx throws
        # above already guard against, one level out. Falling through to `input`
        # puts the dependency's SOURCE TREE into the app bundle where an LGX
        # package belongs: mkStandaloneApp then ships a directory of .cpp files
        # in place of a module and the failure only shows up at runtime, as a
        # module that never loads.
        #
        # Only a genuinely bare-derivation input (no `packages` attr at all) may
        # take the fallback below.
        else if input ? packages then
          builtins.throw ''
            collectAllModuleDeps: dependency '${depName}' publishes no usable package for ${system}.

            It exposes systems: ${lib.concatStringsSep ", " (builtins.attrNames input.packages)}
            ${lib.optionalString (input.packages ? ${system})
              "and for ${system}: ${lib.concatStringsSep ", " (builtins.attrNames input.packages.${system})} (none of lgx / lib / default)"}

            Fix: give '${depName}' a ${system} target and re-pin it, or publish an
            `lgx`/`lib`/`default` output for it. For a cross target that is usually
            a one-line change to the systems list its flake folds `packages` over.
          ''
        else input
      ) depInputs;

      transitive = builtins.foldl' (acc: name:
        let
          input = depInputs.${name};
          # `configFor.<system>` is the dependency's PLATFORM-RESOLVED config;
          # `config` is its system-agnostic one, which cannot answer for a
          # platform-keyed `dependencies` and throws when asked. Prefer the
          # resolved output when the dependency publishes one, and fall back
          # to `config` for a dependency pinned to a builder that predates it.
          tdeps =
            if input ? configFor && input.configFor ? ${system}
            then input.configFor.${system}.dependencies or []
            else (input.config or {}).dependencies or [];
          # Composed modules expose their graph through moduleInputs; older
          # flakes still use the raw inputs attrset.
          tinputs = input.moduleInputs or (input.inputs or {});
        in
          if tdeps == [] then acc
          else acc // (collectAllModuleDeps system tinputs tdeps)
      ) {} (builtins.attrNames depInputs);
    in
      # direct overrides transitive so the closest (most specific) dep wins
      transitive // direct;

  # Supported target systems. "x86_64-windows" is a PSEUDO-system: a cross
  # derivation's `system` attribute is its BUILD platform, so this evaluates
  # anywhere but only realises on x86_64-linux.
  systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ]
    ++ lib.optional (logos-nix != null) "x86_64-windows";

  # Native sets carry logos-nix's own overlays. These include the crates.io
  # mirror fixes required by Rust modules; keep them in one place so callers
  # cannot accidentally evaluate a native package set without them.
  nativeOverlays =
    if logos-nix == null then [ ]
    else if logos-nix ? lib.nativeOverlays then logos-nix.lib.nativeOverlays
    else throw ("logos-module-builder: the pinned logos-nix predates "
                + "lib.nativeOverlays, so Rust modules would vendor crates from "
                + "an endpoint crates.io 403s. Bump the logos-nix input.");

  # THE package-set constructor. Every module's pkgs comes from here, which is
  # what lets ~40 modules target Windows without each re-deriving the cross
  # plumbing.
  #
  # x86_64-windows cannot be produced by `import nixpkgs { system = ...; }` --
  # it needs localSystem/crossSystem plus logos-nix's mingw overlays, which is
  # exactly what logos-nix.lib.mkWindowsPkgs wraps.
  mkPkgsWith = extraOverlays: system:
    if system != "x86_64-windows" then
      import nixpkgs { inherit system; overlays = nativeOverlays ++ extraOverlays; }
    else if logos-nix == null then
      throw ("logos-module-builder: targeting x86_64-windows requires the "
             + "logos-nix input to be threaded into the builder lib.")
    else if extraOverlays != [ ] then
      # Rather than silently drop them and hand back a package set that is not
      # what the caller asked for. mkWindowsPkgs owns its overlay list (the
      # mingw cross fixes); teach it to merge before removing this.
      throw ("logos-module-builder: overlays are not yet supported for the "
             + "x86_64-windows target (requested "
             + toString (builtins.length extraOverlays) + ").")
    else
      logos-nix.lib.mkWindowsPkgs { buildSystem = windowsBuildSystem; };

  mkPkgs = mkPkgsWith [ ];

  # The build platform Windows artifacts are produced FROM.
  #
  # Single-sourced from logos-nix, which owns the decision and the reasoning
  # for it (`windowsBuildSystems`: wine does not exist for aarch64-darwin, and
  # upstream only exercises mingw cross from x86_64-linux). It was previously
  # a bare "x86_64-linux" literal repeated here in two places -- a second copy
  # of someone else's constant, free to drift from it.
  #
  # Deliberately NOT the evaluating system. Pinning it keeps
  # `packages.x86_64-windows.*` one well-defined derivation no matter who
  # evaluates it, so a Darwin and a Linux checkout agree and share a cache; a
  # Darwin dev realises it through a Linux remote builder. Widening this is a
  # change to `windowsBuildSystems` in logos-nix, not an edit here.
  windowsBuildSystem =
    if logos-nix == null then "x86_64-linux"
    else lib.head logos-nix.lib.windowsBuildSystems;

  # The system a build for `target` actually RUNS on. Host TOOLS -- the code
  # generators, moc, repc -- must come from here, never from the target set:
  # under cross, `packages.x86_64-windows.logos-qt-generator` is a PE that the
  # Linux builder cannot execute ("logos-cpp-generator: command not found").
  # Identity for every native system, so callers need no isWindows test.
  buildSystemFor = target:
    if target == "x86_64-windows" then windowsBuildSystem else target;

  # Resolve concrete dependencies to typed wrappers generated from each
  # dependency's published LIDL contract. Dependencies without a contract are
  # rejected before a plugin build starts; this keeps optional dependencies
  # genuinely optional and avoids compiling a dependency just for headers.
  classifyConcreteDeps = { system, flakeInputs, src, config, builderName }:
    let
      depLidlOf = name:
        let i = flakeInputs.${name} or null;
        in if i != null && i ? packages && i.packages ? ${system}
           then (i.packages.${system}.lidl or null)
           else null;
      depIsLidl = name:
        (config.dependency_overrides ? ${name}) || (depLidlOf name != null);
      optional = config.optional_dependencies or [];
      fixHint = ''
        Fix: pass the flake input for each name above and re-pin it against a
        current logos-module-builder (any module built by one publishes
        packages.<system>.lidl), or use a dependency_overrides entry. For a
        target whose contract is intentionally dynamic, drop the declaration
        and call modules().dynamic("<name>").
      '';
      requiredWithoutLidl = lib.filter (name: !(depIsLidl name)) config.dependencies;
      optionalWithoutLidl = lib.filter (name: !(depIsLidl name)) optional;
      assertRequiredPublishLidl =
        if requiredWithoutLidl == [] then null
        else throw ''
          metadata.json: module '${config.name}' lists dependencies that publish no LIDL
          contract: ${lib.concatStringsSep ", " requiredWithoutLidl}

          ${fixHint}
        '';
      assertOptionalPublishLidl =
        if optionalWithoutLidl == [] then null
        else throw ''
          metadata.json: module '${config.name}' lists optional dependencies that publish
          no LIDL contract: ${lib.concatStringsSep ", " optionalWithoutLidl}

          ${fixHint}
        '';
      resolve = name:
        let ov = config.dependency_overrides.${name} or null;
        in if ov != null then {
             inherit name;
             impl_class = ov.impl_class;
             path = if ov.input != null
                    then (if flakeInputs ? ${ov.input}
                          then "${flakeInputs.${ov.input}}/${ov.file}"
                          else throw "dependency_overrides.${name}: flake input '${ov.input}' was not passed to ${builderName}.")
                    else "${src}/${ov.file}";
           } else {
             inherit name;
             impl_class = null;
             path = "${depLidlOf name}/${name}.lidl";
           };
    in {
      staticDeps = map resolve
        (builtins.seq assertRequiredPublishLidl
          (builtins.seq assertOptionalPublishLidl (config.dependencies ++ optional)));
    };

  # Install canonical LIDL contracts in an output consumed by bundlers. Input
  # definitions are normalized through the same generator used by modules.
  installLidlContracts = { pkgs, specs, destination }:
    let
      one = e:
        let
          name = e.name;
          path = e.path;
          implClass = e.impl_class or null;
          isLidl = lib.hasSuffix ".lidl" path;
          isHeader = lib.hasSuffix ".h" path || lib.hasSuffix ".hpp" path;
          metadata = pkgs.writeText "${name}-interface-metadata.json"
            (builtins.toJSON { inherit name; version = "1.0.0"; dependencies = [ ]; });
          produce =
            if isLidl then ''
              logos-cpp-generator --normalize-lidl ${lib.escapeShellArg path} -o "$_lidl_candidate"
            ''
            else if isHeader && implClass != null then ''
              logos-cpp-generator --header-to-lidl ${lib.escapeShellArg path} \
                --impl-class ${lib.escapeShellArg implClass} \
                --metadata ${lib.escapeShellArg metadata} \
                -o "$_lidl_candidate"
            ''
            else throw ''
              logos-module-builder: cannot bundle interface '${name}' from ${path}.
              A contract must be a `.lidl` file, or a `.h`/`.hpp` file with an
              `impl_class`.
            '';
        in ''
          mkdir -p "${destination}"
          _lidl_candidate="$(mktemp)"
          ${produce}
          if [ -e "${destination}/${name}.lidl" ]; then
            if ! cmp -s "$_lidl_candidate" "${destination}/${name}.lidl"; then
              echo "Error: conflicting LIDL contracts resolve to '${name}.lidl'" >&2
              exit 1
            fi
          else
            install -m644 "$_lidl_candidate" "${destination}/${name}.lidl"
          fi
          rm -f "$_lidl_candidate"
        '';
    in lib.concatMapStringsSep "\n" one specs;

  # Resolve the TRANSITIONAL header-copy dependencies (deps publishing no `lidl`
  # contract) from flake inputs, as a struct exposing the dep's plugin (.lib)
  # plus the header variant matching the consumer's --api-style.
  #
  # ONE implementation on purpose. This logic used to be copy-pasted into
  # mkLogosModule.nix (core modules) and buildCppPlugin.nix (ui_qml view
  # modules), and a fix applied to one silently missed the other -- which is
  # exactly how the missing-system case below went unnoticed for view modules.
  # Remove the whole thing once every module publishes a `lidl` output.
  resolveLegacyHeaderDeps = { system, flakeInputs, depNames }:
    lib.mapAttrs (depName: input:
      let
        # An lp (Qt-free) consumer must NOT silently fall back to a Qt-typed
        # header set. The wrappers would declare QString/QVariantMap while the
        # consumer's own codegen ran with `--api-style lp`, so the build dies
        # deep inside a generated TU with a wall of unrelated-looking Qt type
        # errors. Lazy: only fires if an lp consumer really reads `headers-lp`.
        staleLpDep = reason: throw ''
          logos-module-builder: dependency '${depName}' cannot be consumed by an lp (Qt-free) module.

          '${depName}' is taking the transitional header-copy path (it publishes
          no `lidl` output), and
            ${reason}.
          So the only headers it offers are Qt-typed. Copying those into a
          Qt-free translation unit fails deep inside a generated source file
          with a wall of unrelated-looking Qt type errors, so this build stops
          here instead.

          Fix: rebuild / re-pin '${depName}' against a current logos-module-builder.
          Any module built by one publishes a `lidl` contract (preferred — it
          skips the header copy entirely) as well as a `headers-lp` output.
        '';

        # A dep flake that publishes `packages` but nothing for THIS system is an
        # error, not a fallback. Degrading to `input` hands the plugin build the
        # dependency's SOURCE TREE as its header root, and the failure surfaces
        # far away as `fatal error: <dep>_api.h: No such file or directory` in a
        # generated TU -- or, worse, silently succeeds against whatever stale
        # headers happen to be checked in.
        #
        # This is how chat_ui's Windows build failed: chat_module v0.2.2
        # publishes only the four native systems, so an x86_64-windows consumer
        # resolved its headers to the chat_module checkout.
        #
        # Only a genuinely bare-derivation input (no `packages` attr at all) may
        # take the fallback path -- the pre-refactor shape it exists for.
        ps =
          if input ? packages && !(input.packages ? ${system}) then
            throw ''
              logos-module-builder: dependency '${depName}' publishes no packages for ${system}.

              It exposes: ${lib.concatStringsSep ", " (builtins.attrNames input.packages)}

              '${depName}' is taking the transitional header-copy path (it
              publishes no `lidl` output), so this build needs its compiled
              headers for ${system} and there are none.

              Fix: give '${depName}' a ${system} target and re-pin it. For a
              cross target that means adding ${system} to the systems list its
              flake folds `packages` over -- mkLogosModule already understands
              the target, so it is usually a one-line change in that flake.
            ''
          else input.packages.${system} or null;

        # Pre-version of this refactor: input was the raw flake-output derivation
        # (not a packages set). Preserve that path so an external flake-input dep
        # still works.
        fallback = if input ? packages.${system}.default
                   then input.packages.${system}.default else input;
      in
      if ps != null then {
        default     = ps.default;
        lib         = ps.lib or ps.default;
        headers-qt  = ps.headers-qt or ps.include or ps.default;
        headers-lp  = ps.headers-lp or (staleLpDep "its packages.${system} exposes no `headers-lp`");
      } else {
        default     = fallback;
        lib         = fallback;
        headers-qt  = fallback;
        headers-lp  = staleLpDep "the flake input is a bare derivation with no packages.${system} attrset";
      }
    ) (lib.filterAttrs (n: _: builtins.elem n depNames) flakeInputs);

  # Helper to run a function for all systems
  forAllSystems = _nixpkgs: f:
    lib.genAttrs systems (system: f {
      inherit system;
      pkgs = mkPkgs system;
    });

in {
  inherit systems mkPkgs mkPkgsWith forAllSystems buildSystemFor
    classifyConcreteDeps installLidlContracts resolveLegacyHeaderDeps;

  inherit collectAllModuleDeps;

  # Keep this lazy: QML-only packages and published LIDL do not need a host.
  # Qt build/generator/test outputs must fail with a wiring diagnostic instead
  # of dereferencing an optional null input.
  requireQtPlugin = input:
    if input == null then
      throw "logos-module-builder: this Qt build output requires the logos-plugin-qt input; pass it when importing the builder library."
    else input;

  # Keep this lazy: QML-only packages and published LIDL do not instantiate
  # replica-factory templates. C++/REP outputs must fail with a wiring
  # diagnostic instead of dereferencing an optional null input.
  requireViewModule = input:
    if input == null then
      throw "logos-module-builder: this C++/REP build output requires the logos-view-module input; pass it when importing the builder library."
    else input;



  # Determine library extension based on platform
  getLibExtension = pkgs:
    if pkgs.stdenv.hostPlatform.isDarwin then "dylib"
    else if pkgs.stdenv.hostPlatform.isWindows then "dll"
    else "so";

  # Get the library filename for a module
  getPluginFilename = pkgs: name:
    "${name}_plugin.${if pkgs.stdenv.hostPlatform.isDarwin then "dylib" else "so"}";

  # Convert module name to various formats
  nameFormats = name: {
    # my_module -> my_module
    snake = name;
    # my_module -> MyModule
    pascal = lib.concatMapStrings (s: lib.toUpper (lib.substring 0 1 s) + lib.substring 1 (-1) s)
             (lib.splitString "_" name);
    # my_module -> myModule
    camel = let
      parts = lib.splitString "_" name;
      first = lib.head parts;
      rest = lib.tail parts;
    in first + lib.concatMapStrings (s: lib.toUpper (lib.substring 0 1 s) + lib.substring 1 (-1) s) rest;
    # my_module -> MY_MODULE
    upper = lib.toUpper (lib.replaceStrings ["-"] ["_"] name);
  };

  # Merge two attribute sets recursively
  recursiveMerge = attrList:
    let
      f = attrPath:
        lib.zipAttrsWith (n: values:
          if lib.tail values == []
          then lib.head values
          else if lib.all lib.isList values
          then lib.unique (lib.concatLists values)
          else if lib.all lib.isAttrs values
          then f (attrPath ++ [n]) values
          else lib.last values
        );
    in f [] attrList;
}
