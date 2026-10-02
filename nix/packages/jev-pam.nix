{
  lib,
  stdenv,
  zig_0_16,
  linux-pam,
}:
stdenv.mkDerivation {
  pname = "jev-pam";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.unions [
      ../../build.zig
      ../../build.zig.zon
      ../../src
    ];
  };

  nativeBuildInputs = [ zig_0_16.hook ];
  buildInputs = [ linux-pam ];

  meta = {
    description = "PAM module that asks Jev";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
