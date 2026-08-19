{
  description = "Logos QML UI Module — replace with your description";

  inputs = {
    logos-module-builder.url = "github:3esmit/logos-module-builder";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
