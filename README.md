# Linux Workshop Container

This repository builds a Linux workshop environment with 27 hands-on challenges
across 9 concepts. Students work inside isolated containers and verify progress
with built-in commands.

## Student Experience

Inside the workshop shell, students use:

- `welcome` to show the intro banner again
- `challenges` to list every challenge
- `challenges 4.2` to show one specific challenge
- `verify 4.2` to check a challenge
- `reset 4.2` to restore a challenge to a fresh state
- `status` to see overall progress

## Where Things Live

- `challenges.txt` contains the user-facing challenge text
- `challenges.sh` prints the challenge list and individual entries
- `verifier.sh` contains all verify/reset/status logic
- `setup.sh` creates the workshop filesystem and helper scripts baked into the image
- `entrypoint.sh` initializes runtime state, starts services, and launches the student shell or sshd
- `services/flag-server.py` serves the networking challenge responses

## Build the Image

```bash
docker build -t linux-workshop .
```

For a quick local run with the workshop shell:

```bash
docker run -it --rm linux-workshop
```

## Host Broker Setup

This repo also includes a host-side broker model so students SSH to the host,
not directly to containers. Each student gets one persistent container keyed to
their host username.

### Why this model

- students use one command: `ssh <username>@<host>`
- each student gets a persistent container
- reconnecting returns them to the same container state
- containers stay on a private Docker network
- outbound internet can be blocked at the host firewall while `localhost`
  inside the container still works for the workshop challenges

### Operator Steps

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
- `--host-label your-server-or-ip`
- `--registration-port 8088`
- `--registration-code yourinvitecode`

3. The installer starts a registration site and prints its invite code.

Students visit:

```text
http://your-server:8088/
```

They choose a username and password, enter the invite code, and the host login
account is created automatically.

4. If you want to create or reset an account manually from the server:

```bash
sudo ./deploy/provision-student.sh student01 strongpassword
```

5. Students connect with:

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

- only the host SSH port and registration website need to be exposed
- student containers are not directly reachable from outside
- host firewall rules can block all new outbound traffic from the workshop subnet
- SSH forwarding features are disabled for the student host accounts
- the registration website uses a shared invite code and simple password flow;
  it is designed for workshop convenience, not high-security enrollment

## Reconnect Behavior

- exiting the shell disconnects the SSH session
- the container keeps running
- the next `ssh <username>@<host>` returns to the same container state

## Host Requirements

- Docker installed and running
- host OpenSSH server installed and managed by `systemd`
- `iptables` available on the host
- Python 3 available on the host for the registration service
