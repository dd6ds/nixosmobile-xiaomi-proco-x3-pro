#
# Proprietary firmware for the POCO X3 Pro, laid out like postmarketOS'
# firmware-xiaomi-vayu package. Source: https://gitlab.com/adomerle/firmware-xiaomi-vayu
#
{ lib
, fetchurl
, runCommand
}:

let
  rev = "2dc9790c669041385d364d3fcee092545534f88d";
  src = fetchurl {
    url = "https://gitlab.com/adomerle/firmware-xiaomi-vayu/-/archive/${rev}/firmware-xiaomi-vayu-${rev}.tar.gz";
    sha512 = "19cdb00dec5e59585eb50787300ed897a2c3a1d6956e8729f248e449ec1af29d39b4bee5251d56f803cd3121560d1ff61e8332e9d080dd6aee2792ae075eda11";
  };
in
runCommand "xiaomi-vayu-firmware" {
  inherit src;
  # We make no claims that it can be redistributed.
  meta.license = lib.licenses.unfree;
} ''
  tar xzf $src
  cd firmware-xiaomi-vayu-${rev}

  fw=$out/lib/firmware
  mkdir -p $fw/qcom/sm8150/vayu $fw/ath10k/WCN3990/hw1.0

  # DSPs, modem, wlan (paths referenced by sm8150-xiaomi-vayu.dts)
  install -m644 adsp* cdsp* modem* wlanmdsp.mbn -t $fw/qcom/sm8150/vayu/

  # Adreno 640 GPU + IPA
  install -m644 qcom/* -t $fw/qcom/

  # Novatek touchscreen
  install -m644 j20s_novatek_ts* -t $fw/

  # WCN3990 wifi board files (device specific, override linux-firmware)
  install -m644 board-2.bin firmware-5.bin -t $fw/ath10k/WCN3990/hw1.0/
''
