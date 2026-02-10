{ self, inputs, ... }:

{
  perSystem = { config, system, ... }: {
    apps = {
      theme-vm = {
        type = "app";
        program = "${config.packages.theme-vm}/bin/theme-vm";
      };
    };
  };
}
