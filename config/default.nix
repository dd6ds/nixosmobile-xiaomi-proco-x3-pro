#
# Entry point. build.sh copies this folder to <mobile-nixos>/vayu/ and runs:
#   nix-build vayu --argstr device xiaomi-vayu --argstr variant phosh \
#     -A outputs.android-fastboot-images
#
{ variant ? "phosh", ... }@args:

let
  variantFile = ./. + "/${variant}.nix";
in
if !(builtins.pathExists variantFile)
then builtins.throw "Unknown variant '${variant}' (expected: phosh, minimal)"
else
import ../lib/eval-with-configuration.nix ((builtins.removeAttrs args [ "variant" ]) // {
  configuration = [
    (import ./common.nix)
    (import variantFile)
  ];
})
