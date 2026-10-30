#
# Mobile NixOS device definition: Xiaomi POCO X3 Pro (vayu), Snapdragon 860 (SM8150)
#
# Not part of upstream Mobile NixOS. Hardware data (kernel, DTB, boot.img
# offsets, firmware layout) is taken from the postmarketOS port
# (pmaports: device-xiaomi-vayu, linux-postmarketos-qcom-sm8150, firmware-xiaomi-vayu).
#
{ config, lib, pkgs, ... }:

let
  inherit (lib) mkDefault mkOption types;
in
{
  # Upstream Mobile NixOS has no SM8150 SoC entry, so we declare one here.
  options.mobile.hardware.socs.qualcomm-sm8150.enable = mkOption {
    type = types.bool;
    default = false;
    internal = true;
    description = "Enable when SOC is Qualcomm SM8150";
  };

  config = {
    mobile.device.name = "xiaomi-vayu";
    mobile.device.identity = {
      name = "POCO X3 Pro";
      manufacturer = "Xiaomi";
    };
    mobile.device.supportLevel = "unsupported";

    mobile.hardware = {
      soc = "qualcomm-sm8150";
      ram = 1024 * 6;
      screen = {
        width = 1080; height = 2400;
      };
    };
    mobile.system.system = "aarch64-linux";

    # ---- Kernel ----------------------------------------------------------
    mobile.boot.stage-1.kernel = {
      package = pkgs.callPackage ./kernel { };
      modular = true;
      # Personal build: warn instead of failing on kernel config differences.
      useStrictKernelConfig = mkDefault false;
    };

    # ---- Firmware --------------------------------------------------------
    hardware.enableRedistributableFirmware = true;
    mobile.device.firmware = pkgs.callPackage ./firmware { };
    mobile.device.enableFirmware = true;

    # GPU + touchscreen firmware are needed early (non-modular DRM_MSM).
    mobile.boot.stage-1.firmware = [
      (pkgs.runCommand "vayu-initrd-firmware" { } ''
        mkdir -p $out/lib/firmware/qcom
        fw=${config.mobile.device.firmware}/lib/firmware
        cp -v $fw/qcom/a630_sqe.fw $fw/qcom/a640_gmu.bin $fw/qcom/a640_zap.* $out/lib/firmware/qcom/
        cp -v $fw/j20s_novatek_ts_fw*.bin $out/lib/firmware/
      '')
    ];

    # ---- Android boot image ---------------------------------------------
    mobile.system.type = "android";
    mobile.system.android = {
      device_name = "vayu";
      # vayu is a non-A/B device with a dedicated recovery partition.
      ab_partitions = false;
      # The rootfs does not fit "system" (dynamic "super" partition);
      # like postmarketOS, it is flashed to "userdata".
      system_partition_destination = "userdata";
      bootimg.flash = {
        offset_base = "0x00000000";
        offset_kernel = "0x00008000";
        offset_ramdisk = "0x01000000";
        offset_second = "0x00f00000";
        offset_tags = "0x00000100";
        pagesize = "4096";
      };
      appendDTB = [
        "dtbs/qcom/sm8150-xiaomi-vayu.dtb"
      ];
    };

    # ---- USB gadget (adb / rndis networking) ---------------------------
    mobile.usb.mode = "gadgetfs";
    mobile.usb.idVendor = mkDefault "18D1";  # Google
    mobile.usb.idProduct = mkDefault "D001"; # "Nexus 4"
    mobile.usb.gadgetfs.functions = {
      adb = "ffs.adb";
      mass_storage = "mass_storage.0";
      rndis = "rndis.usb0";
    };
  };
}
