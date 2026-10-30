#
# Variant "phosh": touch UI (Phosh / GNOME mobile shell)
#
{ config, lib, ... }:

{
  imports = [
    ../examples/phosh/phosh.nix
  ];

  services.xserver.desktopManager.phosh.user = "nixos";
}
