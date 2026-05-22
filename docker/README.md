# pipane + wede Docker image

This builds one local image with:

- `pipane` on port `8222`
- `wede` on port `9090`
- `pi`, Node 22, Go, Rust, uv/Python, git, `gh`, `rg`, `fd`, and common shell tools

Start both services:

```bash
cd pipane-docker
docker compose up --build
```

Open:

- pipane: `http://localhost:8222/auth?token=change-me`
- wede: `http://localhost:9090` with password `admin`

Useful overrides:

```bash
PIPANE_AUTH_TOKEN=secret WEDE_PASSWORD=secret WORKSPACE_DIR=/path/to/project docker compose up --build
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
