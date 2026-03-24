# Host Broker Setup

This deployment model keeps one persistent container per student, but students
SSH only to the host. A forced-command broker creates or resumes the student's
container and drops them into the `ieee` shell inside it.

It also includes a tiny self-service registration website so students can claim
their own host username and password before connecting.

## Why this model

- students use one command: `ssh <username>@<host>`
- each student gets a persistent container keyed to their host username
- reconnecting returns them to the same container state
- containers stay on a private Docker network with no published ports
- outbound internet is blocked at the host firewall, while `localhost` inside
  the container still works for the workshop challenges

## Operator Steps

1. Build the workshop image on the host:

```bash
docker build -t linux-workshop .
```

2. Install the host broker as root:

```bash
sudo ./deploy/install-host-broker.sh --image linux-workshop
```

Optional flags:

- `--network workshop-net`
- `--subnet 172.30.0.0/24`
- `--prefix ws`
- `--cpus 1`
- `--memory 768m`
- `--pids 256`

3. The installer starts a registration site and prints its invite code.

Students visit:

```text
http://your-server:8088/
```

They choose a username and password, enter the invite code, and the host login
account is created for them automatically.

4. If you want to create or reset an account manually from the server:

```bash
sudo ./deploy/provision-student.sh student01 strongpassword
sudo ./deploy/provision-student.sh student02 anotherstrongpassword
```

5. Tell students to connect with:

```bash
ssh student01@your-server
```

## What Happens on Login

- SSH lands on the host account
- sshd forces `/usr/local/lib/workshop/workshop-login.sh`
- that wrapper uses a narrow sudo rule to run the root broker
- the broker creates `ws-<username>` if missing, or starts it if stopped
- the broker attaches the student to a fresh `ieee` login shell inside that
  same container

## Security Notes

- only the host SSH port is exposed
- the student containers are not directly reachable from outside
- host firewall rules block all new outbound traffic from the workshop subnet
- SSH forwarding features are disabled for the student host accounts
- the registration website uses a shared invite code; that is good enough for a
  one-day workshop, but it is not meant to be a high-security signup system

## Reconnect Behavior

- exiting the shell disconnects the SSH session
- the container keeps running
- the next `ssh <username>@<host>` returns to the same container state

## Current Host Requirements

- Docker installed and running
- host OpenSSH server installed and managed by `systemd`
- `iptables` available on the host
- Python 3 available on the host for the registration service
