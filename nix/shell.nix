{
  mkShell,
  zig_0_16,
  zls,
  linux-pam,
  pamtester,
  nixfmt,
  treefmt,
}:
mkShell {
  packages = [
    zig_0_16
    zls
    linux-pam
    pamtester
    nixfmt
    treefmt
  ];
}
