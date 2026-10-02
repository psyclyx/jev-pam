# jev-pam

A PAM module that asks [Jev](https://docs.typesafe.ai/) whether to let you in.

```
$ sudo systemctl restart nginx
Jev asks: Why do you need root?
> it's down
Asking Jev...
Jev says no.
```

The module sends Jev the user, service, remote host, tty, the question and the
answer, and optionally the command. Jev returns a probability.

## Usage

```
auth sufficient pam_jev.so [question=Why do you need root?] send_cmdline
```

| Argument            | Default                                 |
| ------------------- | --------------------------------------- |
| `question=TEXT`     | none; the user is not asked anything    |
| `send_cmdline`      | off; sends the caller's argv (for sudo) |
| `color`             | off; ANSI colors (not for sshd)         |
| `instructions=TEXT` | derived from the above                  |
| `threshold=P`       | `0.5`                                   |
| `key_file=PATH`     | `/etc/jev/api-key`                      |
| `timeout=SECS`      | `10`                                    |
| `endpoint=URL`      | `https://api.typesafe.ai/v1/systemone`  |
| `model=NAME`        | `jev-latest`                            |

The module returns `PAM_SUCCESS` if Jev's probability meets the threshold and
`PAM_AUTH_ERR` if it doesn't. If Jev can't be reached in time, it returns
`PAM_AUTHINFO_UNAVAIL`.

`zig build run -- [options] USER` makes the same request from the command line,
using `TYPESAFE_API_KEY`.

## Building

```sh
zig build                     # zig-out/lib/security/pam_jev.so
zig build test
nix-build -A default
nix-build -A test             # NixOS VM test against a mock API
```

## Demo

```sh
TYPESAFE_API_KEY=... $(nix-build -A demo)/bin/jev-pam-demo
```

This boots a VM in which Jev alone decides console login, ssh
(`ssh -p 2222 alice@localhost`) and sudo. The users are alice and bob, and
neither has a password.
