# 02 — Docker Compose: running the whole app together

## Why Compose, when you already have two working Dockerfiles
`docker run` starts **one** container. Our app needs **three** — Postgres,
backend, frontend — that need to find each other by name, share startup
order, and get consistent config. Manually juggling three `docker run`
commands with matching `--network` flags gets old fast.

**Docker Compose** solves this with one YAML file, `docker-compose.yml`,
describing all your services declaratively. `docker compose up` reads it and
starts everything, wired together, in one command.

## New concepts

- **Service DNS.** Compose automatically creates a private network for your
  project and gives each service a hostname equal to its **service name** in
  the YAML. If you name a service `backend`, every other container on that
  network can reach it at `http://backend:8000` — no IP addresses, no manual
  linking. This is *exactly* the `backend` hostname your `nginx.conf` already
  expects, and *exactly* why it couldn't resolve when you ran the frontend
  alone in Module 1 — there was no Compose network yet.
- **`depends_on`.** Tells Compose "don't start this service until that one has
  started" — controls startup order. Note: by default this only waits for the
  container to *start*, not for the app inside it to be *ready* (Postgres
  accepting connections can take a few seconds after its container starts).
  Combine it with `condition: service_healthy` (using a container's
  `HEALTHCHECK`) to actually wait for readiness — this is exactly why we
  bothered adding health checks in Module 1.
- **Named volumes.** A `volumes:` entry gives Postgres's data directory a
  persistent home *outside* the container's writable layer, so `docker compose
  down` (which removes containers) doesn't wipe your database. (Contrast:
  `docker compose down -v` *does* remove named volumes too — useful when you
  want a clean slate.)
- **The `environment:` / `env_file:` keys** pass environment variables into a
  container — this is how `DATABASE_URL` reaches the backend, and how
  Postgres's own image gets configured (`POSTGRES_USER`, `POSTGRES_PASSWORD`,
  `POSTGRES_DB` are env vars the official `postgres` image reads to
  initialize itself on first run).
- **Bind-mounting init SQL.** The official `postgres` image runs any
  `*.sql`/`*.sh` file found in `/docker-entrypoint-initdb.d/` — but **only the
  very first time**, when its data directory is empty. Mount your
  `db/schema.sql` there with a `volumes:` entry (a bind mount, not a named
  volume, since it's a file already on your disk, not something Docker should
  manage).

## The two same-origin code edits (do these now, in game-project)

Once nginx proxies `/api/*` to the backend, frontend and backend appear to
the browser as **one origin** — so the workarounds that existed only because
they ran on different ports during dev are no longer needed:

1. **`frontend/app.js:3`** — currently:
   ```js
   const API_BASE = "http://localhost:8000/api";
   ```
   Change it to a **relative** path: `"/api"`. The browser will then request
   `/api/...` from whatever origin served the page — which is nginx, which
   proxies it onward. No more hardcoded host/port.

2. **`backend/app/main.py:19-26`** — the code already flags this for you:
   ```python
   # Dev-only: frontend and backend run on different ports until Milestone 4
   # puts them behind nginx on the same origin. Remove once that lands.
   app.add_middleware(
       CORSMiddleware,
       allow_origins=["*"],
       allow_methods=["*"],
       allow_headers=["*"],
   )
   ```
   `allow_origins=["*"]` exists only because, in dev, the frontend (port 5500)
   and backend (port 8000) were different origins, and browsers block
   cross-origin requests by default (CORS). Once nginx makes everything
   same-origin, the browser never even considers this a cross-origin request
   — so this middleware (and its import) can be deleted entirely.

## The task

**1. Delete the CORS middleware** in `backend/app/main.py` (the `import` line
too, if nothing else uses it) and **change `API_BASE`** in `frontend/app.js`
to `"/api"`.

**2. Write `docker-compose.yml`** at the root of `game-project`, with three
services:

- **`postgres`** — image `postgres:16-alpine` (or similar); env vars for
  user/password/db name; a named volume for `/var/lib/postgresql/data`; a
  bind mount of `./db/schema.sql` into
  `/docker-entrypoint-initdb.d/schema.sql`.
- **`backend`** — `build: ./backend` (Compose builds from your Dockerfile
  instead of pulling an image); `DATABASE_URL` pointing at
  `postgres://<user>:<password>@postgres:5432/<db>` — note the hostname is
  `postgres`, the *service name*, not `localhost`; `depends_on: postgres`
  (bonus: with `condition: service_healthy`, using the `HEALTHCHECK` from
  Postgres's image).
- **`frontend`** — `build: ./frontend`; publish port `80` to your host (e.g.
  `"8080:80"`); `depends_on: backend`.

You do **not** need a `ports:` mapping for `postgres` — nothing outside the
Compose network needs to reach it directly.

## Verify — your first full end-to-end win
```bash
cd /home/balenius/game-project
docker compose up --build
```
Then open **http://localhost:8080** in a browser, play a full 5-round game,
submit a name, and confirm it appears on the leaderboard.

Extra check worth doing: `docker compose down` (containers gone) then
`docker compose up` again (no `--build` needed) — confirm your leaderboard
entry **survived**, proving the named volume is really persisting data
outside the containers.
