# VM in which pam_jev alone decides console login, ssh and sudo.
{
  jev-pam,
  nixos,
  writeShellScriptBin,
}:
let
  questions = {
    login = "State your business.";
    sshd = "What do you need this machine for?";
    sudo = "Why do you need root?";
  };

  machine = nixos (
    { config, lib, ... }:
    {
      system.stateVersion = "26.11";
      networking.hostName = "jev-pam-demo";

      virtualisation.vmVariant.virtualisation = {
        graphics = false;
        forwardPorts = [
          {
            from = "host";
            host.port = 2222;
            guest.port = 22;
          }
        ];
        sharedDirectories.jev = {
          source = ''"$JEV_KEY_DIR"'';
          target = "/run/jev";
        };
      };

      users.users = lib.genAttrs [ "alice" "bob" ] (_: {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
      });

      security.sudo.extraConfig = "Defaults lecture=never";

      services.openssh = {
        enable = true;
        settings = {
          KbdInteractiveAuthentication = true;
          PasswordAuthentication = false;
        };
      };

      security.pam.services = lib.mapAttrs (service: question: {
        rules.auth.jev = {
          order = config.security.pam.services.${service}.rules.auth.unix.order - 10;
          control = "[success=done default=die]";
          modulePath = "${jev-pam}/lib/security/pam_jev.so";
          args = [
            "question=${question}"
            "key_file=/run/jev/api-key"
            "timeout=30"
          ]
          # ssh shows escape codes literally.
          ++ lib.optional (service != "sshd") "color"
          ++ lib.optional (service == "sudo") "send_cmdline";
        };
      }) questions;
    }
  );
in
writeShellScriptBin "jev-pam-demo" ''
  set -eu
  : "''${TYPESAFE_API_KEY:?not set}"
  dir=$(mktemp -d)
  trap 'rm -rf "$dir"' EXIT
  mkdir "$dir/key"
  (umask 077 && printf '%s' "$TYPESAFE_API_KEY" > "$dir/key/api-key")
  # Without SHARED_DIR, the VM's only writable shares are empty temp dirs.
  unset SHARED_DIR USE_TMPDIR
  export JEV_KEY_DIR=$dir/key NIX_DISK_IMAGE=$dir/disk.qcow2
  echo 'Users: alice, bob. ssh: localhost:2222. Quit: Ctrl-a x.'
  ${machine.config.system.build.vm}/bin/run-${machine.config.system.name}-vm
''
