# pipane + wede Docker image

This builds one local image for the apps and serves both through Caddy:

- `pipane` at `http://pipane.localhost:8080`
- `wede` at `http://wede.localhost:8080`
- `pi`, Node 22, Go, Rust, uv/Python, git, `gh`, `rg`, `fd`, and common shell tools

Start both services:

```bash
cd docker
docker compose up --build
```

Open:

- pipane: `http://pipane.localhost:8080/auth?token=change-me`
- wede: `http://wede.localhost:8080` with password `admin`

Useful overrides:

```bash
PIPANE_AUTH_TOKEN=secret WEDE_PASSWORD=secret WORKSPACE_DIR=/path/to/project docker compose up --build
```

To use different local hostnames or port:

```bash
APP_PORT=8081 PIPANE_HOSTNAME=chat.localhost WEDE_HOSTNAME=ide.localhost docker compose up --build
```

To run pipane without its built-in auth URL behind your own reverse proxy auth:

```bash
PIPANE_AUTH_DISABLED=1 WORKSPACE_DIR=/path/to/project docker compose up --build
```

To run wede without its built-in password screen behind your own reverse proxy auth:

```bash
WEDE_AUTH_DISABLED=1 WORKSPACE_DIR=/path/to/project docker compose up --build
```

`WORKSPACE_DIR` is mounted at `/workspace` in both containers. The Pi session data is kept in the `pi-home` Docker volume.

## Personal bootstrap

Copy the example environment file and set the SSH key you want mounted:

```bash
cp .env.example .env
```

```dotenv
PI_SSH_KEY_PATH=/Users/you/.ssh/id_ed25519
```

The selected key is mounted read-only at `/home/ubuntu/.ssh/id_ed25519` in both app containers. SSH config and known hosts are stored in the `user-ssh` Docker volume.

The image runs `/usr/local/bin/pi-web-dev-env-bootstrap` from the entrypoint and creates a first-run marker at:

```text
/home/ubuntu/.local/state/pi-web-dev-env/bootstrap.done
```

That marker is stored in the `user-local` Docker volume, so bootstrap runs once for the persisted environment. To rerun it, remove the marker from inside either container:

```bash
rm ~/.local/state/pi-web-dev-env/bootstrap.done
```

Add personal first-run setup to `user-bootstrap.sh`. Docker Compose mounts that file into the containers at runtime, so changes to it do not require rebuilding the image.
