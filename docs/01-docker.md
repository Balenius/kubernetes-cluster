# 01 — Docker: images, containers, and the Dockerfile

## The vocabulary
- **Image** — a read-only *blueprint*: a filesystem snapshot plus metadata
  (what command to run, what port it expects, etc). Built once from a
  `Dockerfile`, then reused.
- **Container** — a *running instance* of an image. Same relationship as a
  program (on disk) and a process (running). You can start many containers
  from one image.
- **Layer** — each instruction in a `Dockerfile` that touches the filesystem
  (`RUN`, `COPY`, ...) produces a cached layer. Docker reuses layers that
  haven't changed on the next build, which is why **instruction order matters**:
  put things that change rarely (installing dependencies) *before* things that
  change often (your app code). If you copy source code before installing
  dependencies, every code edit invalidates the dependency-install cache too.
- **Registry** — where images are stored/shared (Docker Hub, GHCR, ...). Later
  we'll `docker push` our images to GHCR so Kubernetes can `pull` them.

## The Dockerfile instructions you'll need

| Instruction | What it does |
|---|---|
| `FROM <image>` | The base layer to start from. `python:3.12-slim` gives you Python 3.12 on a minimal Debian, matching the app's `.python-version`. |
| `WORKDIR /app` | Sets the "current directory" inside the image for every instruction after it (and at runtime). Creates the dir if missing. |
| `COPY <src> <dst>` | Copies files from your build context (the folder you run `docker build` from) into the image. |
| `RUN <cmd>` | Executes a shell command *while building* the image (e.g. `pip install`), and bakes the result into a layer. |
| `EXPOSE <port>` | **Documentation only** — tells humans/tools which port the app listens on. It does *not* publish the port; that happens later with `docker run -p`. |
| `USER <name>` | Switches which user subsequent instructions (and the container at runtime) run as. Default is `root`, which is a real security risk in production — always drop to a non-root user for a service that talks to a network. |
| `HEALTHCHECK CMD <cmd>` | A command Docker runs periodically *inside the running container* to decide if it's "healthy". This is the same idea as the Kubernetes readiness/liveness probes we'll write in Module 4 — good practice to have it here too. |
| `CMD [...]` | The default command a container runs when started (can be overridden at `docker run` time). This is what actually starts your app. |

## Build vs. run — two different commands
- `docker build -t <name> .` — reads the `Dockerfile`, produces an **image**.
- `docker run -p 8000:8000 <name>` — starts a **container** from that image.
  `-p 8000:8000` publishes the container's port 8000 to your host's port 8000
  (this is the piece `EXPOSE` only documents).

## The task
Write `backend/Dockerfile` in the **game-project** repo (not kubernetes-cluster
— this file lives with the app). It needs to:

1. Start `FROM python:3.12-slim`.
2. Set a `WORKDIR`.
3. Copy **only `requirements.txt` first**, and `RUN pip install` it — before
   copying the rest of the app code (this is the layer-caching order lesson
   above).
4. Copy the rest of the app source in.
5. Create a non-root user and `USER` into it before running anything.
6. `EXPOSE 8000`.
7. Add a `HEALTHCHECK` that hits `/api/health`. Gotcha: `python:3.12-slim`
   doesn't have `curl` installed by default. Either install it with
   `apt-get`, or — simpler, no extra package — use Python itself:
   `python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/api/health')"`.
8. `CMD` that runs `uvicorn app.main:app --host 0.0.0.0 --port 8000` (no
   `--reload` — that's a dev-only flag that watches for file changes and has
   no place in a built image).

## Verify it works
```bash
cd /home/balenius/game-project
docker build -t game-backend ./backend
docker run --rm -p 8000:8000 -e DATABASE_URL=postgresql://fake game-backend
# in another terminal:
curl http://localhost:8000/api/health
```
Expect this to **fail** at startup or on the health check — there's no real
database yet, and `db.py` requires `DATABASE_URL`. That's fine and expected;
we're only proving the image builds and the container starts the right
process. We'll get a real, working health check in Module 2 (Docker Compose)
once Postgres is in the picture.

## Part 2: the frontend (nginx as a static server + reverse proxy)

The frontend is plain static files (`index.html`, `app.js`, `styles.css`) — no
build step. We don't need a language runtime to serve them, just a web server.
**nginx** is the standard choice, and it does double duty here: it serves the
static files *and* forwards `/api/*` requests to the backend, so the browser
sees everything as one origin (no CORS needed).

### New concept: nginx config, not just a Dockerfile
Unlike the backend, most of the interesting logic here lives in an **nginx
config file**, not the Dockerfile. The Dockerfile just gets nginx to *use*
your config instead of its built-in default. Key nginx pieces:

- `server { listen 80; ... }` — one virtual server, listening on port 80
  (nginx's default in the `nginx:alpine` image).
- `location / { root ...; try_files ...; }` — for a request path matching
  `/`, look for that file under `root`. `try_files $uri $uri/ =404;` means
  "serve the exact file if it exists, else 404" — fine here since this is a
  single static page, not a client-side-routed app.
- `location /api/ { proxy_pass http://backend:8000/api/; }` — for anything
  under `/api/`, forward the request to the backend instead of looking for a
  file. `backend` here is a **hostname that will resolve via Docker's
  internal DNS once we add Compose in Module 2** — it won't resolve yet when
  you test the frontend container alone, and that's expected.

**The trailing-slash gotcha** (a famous nginx foot-gun, worth internalizing
now): in `proxy_pass`, whether you include a path after the host:port changes
whether nginx *strips* the matched location prefix before forwarding. Compare:
- `proxy_pass http://backend:8000;` (no path) → forwards the **full original
  URI** unchanged, `/api/` prefix included.
- `proxy_pass http://backend:8000/api/;` (same path as the location prefix)
  → also ends up preserving `/api/`, just by explicitly mirroring it.

Since the backend's routes are mounted *at* `/api/...`, you need the `/api/`
prefix to survive the proxy. Pick the explicit-mirror form above — it's
easier to reason about than relying on the "no path = passthrough" rule.

### The task
Write `frontend/Dockerfile` and `frontend/nginx.conf` in **game-project**:

**`frontend/Dockerfile`:**
1. `FROM nginx:alpine`.
2. `COPY` your `nginx.conf` to `/etc/nginx/conf.d/default.conf` — this
   *replaces* the image's built-in default site config with yours.
3. `COPY` the static files (`index.html`, `app.js`, `styles.css`) into
   `/usr/share/nginx/html` — that's the doc root the base image already
   expects.
4. `EXPOSE 80`.
5. **No `USER` instruction needed here** — unlike `python:3.12-slim`, the
   official `nginx:alpine` image already runs its worker processes as an
   unprivileged user internally; you don't need to set that up yourself.
6. Optional but good practice: a `HEALTHCHECK`. Alpine images include
   BusyBox's `wget`, so `wget -q --spider http://localhost/ || exit 1` works
   without installing anything extra (`--spider` means "just check it
   responds, don't save the output").

**`frontend/nginx.conf`:** one `server` block, listening on port 80, with the
two `location` blocks described above (`/` for static files, `/api/` proxied
to the backend).

### Verify
```bash
cd /home/balenius/game-project
docker build -t game-frontend ./frontend
docker run --rm -p 8080:80 game-frontend
# separately:
curl -I http://localhost:8080/          # expect 200 OK, serving index.html
curl http://localhost:8080/api/health   # expect a connection/DNS error — "backend" doesn't exist yet, that's fine
```
