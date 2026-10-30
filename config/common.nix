#
# Settings shared by all variants. Change user / password / ssh keys here.
#
{ config, lib, pkgs, ... }:

let
  user = "nixos";
in
{
  # Firmware blobs are unfree.
  nixpkgs.config.allowUnfree = true;

  networking.hostName = "vayu";
  time.timeZone = lib.mkDefault "Europe/Berlin";
  i18n.defaultLocale = lib.mkDefault "de_DE.UTF-8";

  users.users.${user} = {
    isNormalUser = true;
    # CHANGE THIS after first boot (passwd)! Numeric so it works on the phosh lockscreen.
    initialPassword = "1234";
    extraGroups = [ "dialout" "feedbackd" "networkmanager" "video" "wheel" ];
    # openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA... you@host" ];
  };

  security.sudo.wheelNeedsPassword = lib.mkDefault true;

  networking.networkmanager.enable = true;

  # SSH over WiFi
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
  };

  # Handy tools
  environment.systemPackages = with pkgs; [
    git htop vim usbutils pciutils
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "25.11";
}
