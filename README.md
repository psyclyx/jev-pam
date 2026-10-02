# jev-pam

A PAM module that asks [Jev](https://docs.typesafe.ai/) whether to let you in.

```
$ sudo systemctl restart nginx
Jev asks: Why do you need root?
> nginx is down
Asking Jev...
$
```

The module sends Jev the user, service, remote host, tty, the question and the
answer, and optionally the command. Jev returns a probability.

## Usage

```
auth sufficient pam_jev.so [question=Why do you need root?] send_cmdline
```

| Argument            | Meaning                                    | Default                                |
| ------------------- | ------------------------------------------ | -------------------------------------- |
| `question=TEXT`     | Ask the user this; send Jev the answer     |                                        |
| `send_cmdline`      | Send the caller's command line (for sudo)  |                                        |
| `color`             | Color messages (not for sshd)              |                                        |
| `instructions=TEXT` | The yes/no question put to Jev             | derived from the attempt               |
| `threshold=P`       | Minimum probability to let the user in     | `0.5`                                  |
| `key_file=PATH`     | TypeSafe API key                           | `/etc/jev/api-key`                     |
| `timeout=SECS`      | How long to wait for Jev                   | `10`                                   |
| `endpoint=URL`      |                                            | `https://api.typesafe.ai/v1/systemone` |
| `model=NAME`        |                                            | `jev-latest`                           |

The module returns `PAM_SUCCESS` if Jev's probability meets the threshold and
`PAM_AUTH_ERR` if it doesn't. If Jev can't be reached in time, it returns
`PAM_AUTHINFO_UNAVAIL`.

## Building

```sh
zig build                     # zig-out/lib/security/pam_jev.so
zig build test
nix-build -A default
nix-build -A test             # NixOS VM test against a mock API
```

## Packages

```sh
cd packaging/arch && makepkg -si                        # Arch
rpmbuild -bb --build-in-place packaging/rpm/jev-pam.spec  # Fedora
cp -r packaging/debian . && dpkg-buildpackage -b         # Debian, Ubuntu
cd packaging/alpine && abuild -r                        # Alpine
```

Debian has no Zig 0.16 package. Use one from ziglang.org and pass `-d`.

## Demo

```sh
TYPESAFE_API_KEY=... $(nix-build -A demo)/bin/jev-pam-demo
```

This boots a VM in which Jev alone decides console login, ssh
(`ssh -p 2222 alice@localhost`) and sudo. The users are alice and bob, and
neither has a password.
