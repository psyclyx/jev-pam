let
  npins = import ./npins;

  # `lib` must come from a set that does not include the overlay, since the
  # overlay's attribute names are computed with it.
  mkPackages =
    lib: callPackage:
    lib.packagesFromDirectoryRecursive {
      inherit callPackage;
      directory = ./nix/packages;
    };

  overlay = final: prev: mkPackages prev.lib final.callPackage;
in
{
  nixpkgs ? npins.nixpkgs,
  pkgs ? import nixpkgs { },
}:
let
  finalPkgs = pkgs.extend overlay;
in
rec {
  packages = mkPackages pkgs.lib finalPkgs.callPackage;
  default = packages.jev-pam;
  inherit overlay;
  shell = finalPkgs.callPackage ./nix/shell.nix { };
  demo = finalPkgs.callPackage ./nix/demo.nix { };
  test = finalPkgs.testers.runNixOSTest ./nix/test;
}
