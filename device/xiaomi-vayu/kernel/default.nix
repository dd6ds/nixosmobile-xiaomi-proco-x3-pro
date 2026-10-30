#
# Mainline kernel fork for SM8150 devices (sm8150-mainline), same commit and
# config as postmarketOS' linux-postmarketos-qcom-sm8150 (6.4).
# Hashes are the sha512 values published in pmaports.
#
{ mobile-nixos
, fetchurl
, ...
}:

let
  rev = "93f303701cafa17135d8ee563ffdc39f319783f1";
in
mobile-nixos.kernel-builder {
  version = "6.4.0";
  # CONFIG_LOCALVERSION="-sm8150" in config.aarch64
  modDirVersion = "6.4.0-sm8150";
  configfile = ./config.aarch64;

  src = fetchurl {
    url = "https://gitlab.com/sm8150-mainline/linux/-/archive/${rev}/linux-${rev}.tar.bz2";
    sha512 = "fde637d245fa55525763d509caeb038005b419ddddfb28bd5087826c3b38e88126cacee048cdef191c2df67cb421cda19ad125ecaa83e0668de0d848a3f38318";
  };

  # Newer GCC from nixpkgs-unstable is stricter than what this 6.4 tree saw.
  enableRemovingWerror = true;

  isModular = true;
  isCompressed = "gz";
}
