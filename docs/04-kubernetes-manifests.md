# 04 — Kubernetes: running the app on the cluster

## Why this module is different

Modules 1–2 ran the app with Docker Compose on one machine. Module 3 built a
real Kubernetes cluster. This module puts the same three pieces (Postgres,
backend, frontend) onto that cluster, using raw Kubernetes manifests: one
YAML file per object, applied with `kubectl`.

Nothing about the app changes. The images are the same, the env vars are the
same, and nginx still proxies `/api/` to a host called `backend`. What changes
is who is responsible for keeping it running. Compose starts containers once
and leaves them. Kubernetes keeps comparing **what you declared** with
**what is actually running**, and fixes any difference. If a pod dies, it
starts a new one. That loop is the core idea of the whole module.

M5 will refactor these files with Kustomize. Writing them raw first means
you know what Kustomize is saving you from.

## Compose → Kubernetes, side by side

| In `docker-compose.yml` | In Kubernetes | Why it's split up |
|---|---|---|
| a `service:` entry (`backend:`) | **Deployment** (runs the pods) + **Service** (gives them a stable name) | Pods come and go and get new IPs each time. The Service is the fixed address in front of them. |
| service name as hostname (`backend`) | the **Service's `metadata.name`** | Same idea, different mechanism: cluster DNS instead of Compose's network. |
| `postgres:` with a named volume | **StatefulSet** + **headless Service** + **PersistentVolumeClaim** | A database needs a stable identity and its *own* disk that follows it. |
| `environment:` (non-secret) | **ConfigMap** | Config lives outside the image. |
| `environment:` (passwords) | **Secret** | Same thing, but handled as sensitive (see caveat below). |
| bind-mounting `schema.sql` | **ConfigMap** mounted as a file | There's no host path to bind-mount from. Files come from the API. |
| `ports: "8080:80"` | **Ingress** (via Traefik) | One shared entry point routing by hostname, not one host port per app. |
| `depends_on` / `HEALTHCHECK` | **readiness** and **liveness probes** | Kubernetes doesn't order startup. It retries until things are ready. |
| the project (all three services) | a **Namespace** | A named box for everything belonging to this app. |

## New vocabulary

- **Pod.** The smallest thing Kubernetes runs: one or more containers sharing
  an IP. You almost never create pods directly. You create something that
  manages pods for you.
- **Deployment.** "Keep N copies of this pod running, and when I change the
  pod template, roll them over gradually." Right for **stateless** things
  (backend, frontend): any copy is as good as any other.
- **StatefulSet.** Like a Deployment, but each pod gets a **stable name**
  (`postgres-0`, not `postgres-7d9f8-xk2p`) and its **own disk** that follows
  it across restarts. Right for databases.
- **Labels and selectors.** Labels are key/value tags on objects
  (`app: backend`). Selectors are queries over labels. This is how a
  Deployment knows which pods are its own, and how a Service knows which pods
  to send traffic to. **If a selector doesn't match the pod labels, nothing
  errors. Traffic just goes nowhere.** It's the most common M4 bug.
- **Service.** A stable virtual IP and DNS name in front of a set of pods
  (chosen by selector). The default type, `ClusterIP`, is reachable only
  from inside the cluster. That's the `10.43.0.0/16` range your firewall
  rules allow.
- **Headless Service** (`clusterIP: None`). No virtual IP. The DNS name
  resolves straight to the pod IP(s). A StatefulSet requires one, and it's
  what gives `postgres-0` its own DNS entry.
- **PersistentVolumeClaim (PVC).** "I need 1 GiB of disk." A **StorageClass**
  decides how that request is fulfilled. k3s ships one called `local-path`,
  which makes a directory on the node's disk. On AWS (M8), the same claim
  would get an EBS volume instead. The claim is identical; only the class
  differs. That's the portability story in one line.
- **ConfigMap / Secret.** Key/value data that pods consume as env vars or
  mounted files. **Caveat:** a Secret is only base64-*encoded*, not
  encrypted. Anyone who can read it from the API can decode it. That's why
  the plan keeps it out of git until M6 introduces Sealed Secrets.
- **Ingress.** Rules for HTTP routing from outside the cluster ("requests for
  host `rps.local` go to Service `frontend`, port 80"). An Ingress is just a
  rule. An **ingress controller** has to exist to act on it. k3s ships
  **Traefik** as that controller, already running in `kube-system`, and
  listening on the node's port 80 (the port your firewall opens).
- **Probes.**
  - **Readiness:** "is this pod ready for traffic right now?" A failing
    readiness probe removes the pod from its Service's endpoints but leaves
    it running.
  - **Liveness:** "is this pod broken beyond recovery?" A failing liveness
    probe **restarts the container**.

  Mixing them up causes real outages (see the backend section).

## How we'll work

One object at a time, each verified before the next. The loop:

```bash
kubectl apply -f <file>          # send your declared state to the cluster
kubectl get <kind> -n rps        # did it get created? what state?
kubectl describe <kind> <name> -n rps   # the Events section at the bottom explains most failures
kubectl logs <pod> -n rps        # what the app itself printed
```

When something is wrong, **`describe`'s Events section comes first.** Pull
failures, scheduling problems, failed probes and mount errors all show up
there before they show up anywhere else.

Files go in **`apps/game-project/`** in this repo, one file per object (or
per closely related pair). M5 moves them into `apps/game-project/base/`
unchanged, so it's worth naming them well now.

## Step 0: get the images onto the node

**The problem:** your `game-project-backend` and `game-project-frontend`
images exist only in Docker's image store in WSL. The cluster's node runs its
own container runtime (containerd, inside the VM) and has never heard of
them. When a pod asks for `game-project-backend`, the node tries Docker Hub,
finds nothing, and the pod sits in `ErrImagePull` → `ImagePullBackOff`.

M7 fixes this properly by building in CI and pushing to GHCR, where the node
can pull from. For now, **copy the images straight into the node's
containerd**. That keeps M4 about Kubernetes, not registries.

1. **Give them a real tag, not `latest`.** This matters. When an image tag
   is `:latest` (or missing), Kubernetes defaults the pod's
   `imagePullPolicy` to `Always`, meaning "always check the registry". It
   will try Docker Hub, fail, and never use your imported copy. Any other tag
   defaults to `IfNotPresent`, meaning "use the local copy if it's there".
   Tag them something like `:m4`:
   ```bash
   docker tag game-project-backend:latest  game-project-backend:m4
   docker tag game-project-frontend:latest game-project-frontend:m4
   ```
2. **Stream them into the node.** `docker save` writes an image as a tar to
   stdout, `ssh` carries it across, and `k3s ctr images import -` reads it
   from stdin on the other side:
   ```bash
   docker save game-project-backend:m4 game-project-frontend:m4 \
     | ssh ubuntu@192.168.50.178 'sudo k3s ctr images import -'
   ```
3. **Verify on the node.** Imported images are named in full, with the
   implied Docker Hub prefix added:
   ```bash
   ssh ubuntu@192.168.50.178 'sudo k3s ctr images ls | grep game-project'
   # expect docker.io/library/game-project-backend:m4 and ...-frontend:m4
   ```

In manifests you can still write `image: game-project-backend:m4`.
Kubernetes expands short names the same way.

**Architecture check, already done:** the images were built on x86_64 WSL
and the node is x86_64, so they'll run. On the Pi (arm64, M8), they wouldn't.
That's what M7's multi-arch builds are for.

**Rebuilds wipe this.** A Terraform `destroy`/`apply` gives you a fresh node
with an empty image store, so repeat this step after any rebuild.

## Step 1: Namespace — `namespace.yaml`

**What it does:** creates a Namespace called `rps`. Everything else in this
module lives inside it.

**Needs:** `apiVersion`, `kind`, `metadata.name`. Nothing else. It's the
smallest possible Kubernetes object, which makes it a good first file for
learning the four top-level fields every manifest has (`apiVersion`,
`kind`, `metadata`, and usually `spec`).

**Every later manifest** sets `metadata.namespace: rps`, so they land in it
no matter which namespace your `kubectl` defaults to.

**Verify:** `kubectl get ns rps` → `Active`.

## Step 2: the `game-db` Secret — created with `kubectl`, no file

**What it does:** holds the database credentials that both Postgres and the
backend read. It's created imperatively so no password ever sits in a file
in the repo.

**Needs these keys:**
- `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`: the official Postgres
  image reads exactly these names on first start, same as in Compose.
- `DATABASE_URL`: what the backend reads (`backend/app/db.py` does
  `os.environ["DATABASE_URL"]`, so the name is fixed by the code). Its host
  part is the **Postgres Service's name**, `postgres`, because that's the
  DNS name Kubernetes will give it. Same shape as in Compose:
  `postgresql://<user>:<password>@postgres:5432/<db>`.

**Pick a new password.** Don't reuse `testdb123`: it's committed in plain
text in `docker-compose.yml`.

Look up `kubectl create secret generic` and its `--from-literal` flag (one
per key). Watch your shell quoting if the password has special characters.

**Verify:** `kubectl describe secret game-db -n rps` lists the four keys with
byte sizes but not the values. Then decode one to see the "encoded, not
encrypted" point for yourself:
`kubectl get secret game-db -n rps -o jsonpath='{.data.POSTGRES_DB}' | base64 -d`.

## Step 3: Postgres

Three objects. They can go in one file separated by `---`, or in separate
files.

### 3a. Schema ConfigMap — `postgres-schema.yaml` (or generated)

**What it does:** carries `game-project/db/schema.sql` into the cluster so
Postgres can run it on first start, the same job the Compose bind-mount did.

**Needs:** a `data:` key named e.g. `schema.sql` whose value is the file's
contents. You can write the YAML by hand, or generate it:
`kubectl create configmap ... --from-file=... --dry-run=client -o yaml`
prints a manifest without creating anything. Knowing that trick is worth it
on its own.

### 3b. Headless Service — `postgres` Service

**What it does:** gives Postgres its DNS name. **It must be named
`postgres`**, because that's the host in your `DATABASE_URL`.

**Needs:** `clusterIP: None` (that's what makes it headless), a selector
matching the Postgres pod's labels, and port `5432`.

### 3c. StatefulSet — `postgres`

**What it does:** runs one Postgres pod with its own persistent disk.

**Needs:**
- `serviceName: postgres`, which links it to the headless Service.
- `replicas: 1`. (Running more than one copy of Postgres takes replication
  setup that a StatefulSet doesn't do for you. Out of scope.)
- A `selector.matchLabels` that exactly matches `template.metadata.labels`.
- Container: `postgres:16-alpine` (pulled from Docker Hub; the node has
  internet access, which you verified in M3), port `5432`.
- **Env from the Secret:** the three `POSTGRES_*` keys. Look at `envFrom`
  with a `secretRef` (pulls in every key) versus individual `env` entries
  with `valueFrom.secretKeyRef` (picks specific keys). Think about whether
  Postgres should see `DATABASE_URL` too. It's harmless, but it's a good
  question to have an answer for.
- **Two volume mounts:**
  - the data disk at `/var/lib/postgresql/data`, from a
    **`volumeClaimTemplates`** entry (say 1Gi, `ReadWriteOnce`). The
    StatefulSet creates the PVC for you and names it `<template>-postgres-0`.
  - the schema ConfigMap at `/docker-entrypoint-initdb.d`, from a
    `configMap` volume.
- **A readiness probe.** Postgres ships `pg_isready`, which fits an `exec`
  probe well.

**Watch out for:** the init scripts in `/docker-entrypoint-initdb.d` **only
run when the data directory is empty**, same rule as in Compose. If
Postgres ever starts once with a broken schema, fixing the ConfigMap won't
re-run it. You'd have to delete the PVC and start over. So get the
ConfigMap right before the first start.

**Verify:**
```bash
kubectl get statefulset,pod,pvc -n rps     # postgres-0 Running 1/1, PVC Bound
kubectl exec -it postgres-0 -n rps -- psql -U <user> -d <db> -c '\dt'   # players table exists
```

## Step 4: Backend — `backend.yaml` (Deployment + Service)

**Deployment needs:**
- Image `game-project-backend:m4`, container port `8000`.
- `DATABASE_URL` from the `game-db` Secret.
- **Readiness probe:** HTTP GET `/api/health` on port 8000. That endpoint
  runs `SELECT 1` against Postgres, so "ready" really does mean "can serve
  requests".
- **Liveness probe: *not* `/api/health`.** Ask yourself what would happen if
  it were. Postgres restarts, `/api/health` returns 503 for a few seconds,
  liveness fails, and Kubernetes **restarts every backend pod**, even though
  the backend itself was fine and restarting it can't fix the database. A
  database blip turns into an app-wide outage. Liveness should only check
  "is this process alive". A **TCP socket probe on port 8000** does exactly
  that.
- `replicas: 2` is worth trying. It shows the Service load-balancing across
  pods, and deleting one pod doesn't interrupt anything.

**Service needs:** **named `backend`, port `8000`.** That isn't a stylistic
choice: `frontend/nginx.conf` hard-codes `proxy_pass http://backend:8000`.
The Service name *is* the hostname. `ClusterIP` (the default): only the
frontend talks to it, so it never needs to be reachable from outside the
cluster.

**Verify:**
```bash
kubectl get deploy,pods,endpoints -n rps     # backend endpoints lists 2 pod IPs:8000
kubectl run curltest -n rps --rm -it --image=curlimages/curl --restart=Never \
  -- curl -s http://backend:8000/api/health  # {"status":"ok"}
```
If `endpoints` is empty while the pods are Running, the Service selector
doesn't match the pod labels, or the readiness probe is failing.
`describe` tells you which.

## Step 5: Frontend — `frontend.yaml` (Deployment + Service)

**Deployment needs:** image `game-project-frontend:m4`, port `80`, and a
readiness probe (HTTP GET `/` on port 80 is enough).

**Service needs:** named `frontend`, port `80`, `ClusterIP`. It isn't exposed
directly either. The Ingress in step 6 is the only way in from outside.

**Watch out for:** nginx looks up `backend` **once, at startup**. If the
`backend` Service doesn't exist yet, nginx exits with
`host not found in upstream "backend"`, and the pod crash-loops. That's why
the order is backend → frontend. (It fixes itself once `backend` exists,
because the crash-loop keeps retrying. That's Kubernetes' reconcile loop
filling in for `depends_on`.)

**Verify:** `kubectl get pods -n rps` → frontend Running 1/1.
`kubectl port-forward svc/frontend 8080:80 -n rps`, then
`curl -s localhost:8080/api/health` from WSL tests the whole chain
frontend → backend → Postgres, before an Ingress even exists.

## Step 6: Ingress — `ingress.yaml`

**What it does:** tells Traefik "HTTP requests with `Host: rps.local` go to
Service `frontend`, port 80."

**Needs:** `ingressClassName: traefik`, one rule with `host: rps.local`, and
path `/` with `pathType: Prefix` pointing at the `frontend` Service. Only
`/`: nginx inside the frontend already routes `/api/` to the backend, so
the Ingress doesn't need to know the backend exists.

**Name resolution:** `rps.local` doesn't exist in any DNS. You're adding it
by hand, **on Windows**, because that's where your browser runs:
`C:\Windows\System32\drivers\etc\hosts` (edit as admin), add
`192.168.50.178 rps.local`.

**Verify:** `curl -s -H 'Host: rps.local' http://192.168.50.178/api/health`
from WSL works without the hosts entry. It sets the header directly, which
proves the Ingress rule on its own. Then open `http://rps.local` in the
browser.

## Module verify: the real test

1. Play a full game at `http://rps.local`. The result shows on the
   leaderboard.
2. **Delete the database pod:** `kubectl delete pod postgres-0 -n rps`. Watch
   `kubectl get pods -n rps -w`: the StatefulSet recreates `postgres-0`,
   reattaches the **same** PVC, and the backend's readiness probe drops out
   and comes back.
3. Reload the leaderboard. **Your game is still there.** The pod was
   disposable; the data wasn't. That's the whole point of the PVC.

Worth also trying: `kubectl delete pod <one backend pod>` while refreshing
the page. With `replicas: 2`, you shouldn't notice.

## Progress

| Step | File | Status |
|---|---|---|
| 0 | images imported into node | ⬜ |
| 1 | `namespace.yaml` | ⬜ |
| 2 | `game-db` Secret (kubectl) | ⬜ |
| 3 | Postgres: ConfigMap + headless Service + StatefulSet | ⬜ |
| 4 | `backend.yaml` | ⬜ |
| 5 | `frontend.yaml` | ⬜ |
| 6 | `ingress.yaml` + hosts entry | ⬜ |
| ✔ | play, delete `postgres-0`, leaderboard survives | ⬜ |
