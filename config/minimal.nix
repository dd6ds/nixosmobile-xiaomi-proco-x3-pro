#
# Variant "minimal": no GUI, verbose boot, debug access over USB.
# Use it to bring up / debug the port.
#
# WARNING: stage-1 SSH (initrd) allows root login WITHOUT password while the
# phone is in the initrd. Only connect the phone to a trusted computer.
#   Host: ip addr add 172.16.42.2/24 dev <usb-iface>; ssh root@172.16.42.1
#
{ config, lib, ... }:

{
  mobile.beautification = {
    silentBoot = false;
    splash = false;
  };

  mobile.boot.stage-1 = {
    usb.enable = true;
    networking.enable = true;
    ssh.enable = true;
  };
}
