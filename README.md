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
docker build -t linux-workshop ./user-container
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
docker build -t linux-workshop ./user-container
```

2. Install the host broker as root:

```bash
sudo ./install-host-broker.sh --image linux-workshop
```

If it is already installed, the script exits. To refresh the existing install:

```bash
sudo ./install-host-broker.sh --reinstall --image linux-workshop
```

Reinstalling keeps the existing session secret.

Optional flags:

- `--network workshop-net`
- `--subnet 172.30.0.0/24`
- `--prefix ws`
- `--cpus 1`
- `--memory 768m`
- `--pids 256`
- `--host-label your-server-or-ip`
- `--registration-port 8088`
- `--reinstall`

3. The installer starts a registration site.

Students visit:

```text
http://your-server:8088/
```

They choose a username and password, and the host login account is created
automatically. Each source IP can claim only one username through the
self-service flow.

The same site also provides:

- a student dashboard where each student can reset only their own machine
  after logging in and confirming their password

Important: the website is for workshop convenience only. Do not use a real
password or reuse a password from anywhere else. Passwords sent to the site can
be read on the network.

After install, the host also gets a `workshop-ops` command.

4. If you want to create or reset an account manually from the server:

```bash
sudo workshop-ops create-user student01 strongpassword
```

5. To reset a student's machine without deleting the account:

```bash
sudo workshop-ops reset-machine student01
```

This removes the student's current container and archives it first. The next SSH
login creates a fresh machine.

6. To recoverably delete a student account from the server:

```bash
sudo workshop-ops delete-user student01
```

This archives the student's current machine first, then removes the host login
and home directory.

7. To restore a previously deleted student account from the latest archive:

```bash
sudo workshop-ops restore-user student01 newstrongpassword
```

8. To inspect current workshop users and machines:

```bash
sudo workshop-ops status
```

9. Students connect with:

```bash
ssh student01@your-server
```

To remove the host integration without deleting workshop users or containers:

```bash
sudo ./uninstall-host-broker.sh
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
- the registration website uses one-claim-per-IP policy and host password
  authentication for the student dashboard; it is designed for workshop
  convenience, not high-security enrollment
- students should use temporary workshop-only passwords because the website runs
  over plain HTTP and credentials can be read on the network

## Reconnect Behavior

- exiting the shell disconnects the SSH session
- the container keeps running
- the next `ssh <username>@<host>` returns to the same container state

## Host Requirements

- Docker installed and running
- host OpenSSH server installed and managed by `systemd`
- `iptables` available on the host
- Python 3 with `venv` support available on the host for the registration service
