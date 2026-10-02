{
  name = "jev-pam";

  nodes.machine =
    { pkgs, ... }:
    let
      pam_jev = "${pkgs.jev-pam}/lib/security/pam_jev.so";
    in
    {
      environment.systemPackages = [ pkgs.pamtester ];
      users.users.alice.isNormalUser = true;

      environment.etc."jev/api-key" = {
        text = "test-key";
        mode = "0400";
      };

      systemd.services.mock-api = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 ${./mock-api.py} 8080";
      };

      security.pam.services.jev.text = ''
        auth    required ${pam_jev} question=Why? send_cmdline endpoint=http://127.0.0.1:8080/ timeout=3
        account required pam_permit.so
      '';
      security.pam.services.jev-unreachable.text = ''
        auth    required ${pam_jev} endpoint=http://127.0.0.1:1/
        account required pam_permit.so
      '';
    };

  testScript = ''
    machine.wait_for_open_port(8080)

    def auth(service, answer):
        return f"echo '{answer}' | pamtester {service} alice authenticate 2>&1"

    with subtest("approve"):
        out = machine.succeed(auth("jev", "good reason"))
        assert "Jev asks: Why?\n> " in out, out

    with subtest("deny"):
        out = machine.fail(auth("jev", "bad reason"))
        assert "Jev says no." in out, out

    with subtest("timeout"):
        out = machine.fail(auth("jev", "stall"))
        assert "Jev is not available." in out, out

    with subtest("unreachable"):
        out = machine.fail(auth("jev-unreachable", ""))
        assert "Jev is not available." in out, out

    with subtest("logging"):
        machine.succeed("journalctl -u mock-api | grep '\"command\": \"pamtester jev alice authenticate\"'")
        machine.succeed("journalctl | grep 'pam_jev: alice: approved'")
        machine.succeed("journalctl | grep 'pam_jev: alice: denied'")
        machine.succeed("journalctl | grep 'pam_jev: alice: Timeout'")
        machine.succeed("journalctl | grep 'pam_jev: alice: ConnectionFailed'")

    with subtest("no crashes"):
        machine.fail("journalctl -k | grep segfault")
  '';
}
