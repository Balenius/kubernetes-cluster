# Resume — Portable Kubernetes Cluster (guided build)

**Purpose of this file:** if this session gets picked up cold (new chat, new
day, whatever) — read this first. It has the current status, every decision
and environment fact gathered so far, and the exact next task.

## Master plan
The full curriculum lives at:
`/home/balenius/.claude/plans/create-kubernetes-cluster-that-lovely-shannon.md`

That file has the complete module list (M0–M8) and the architecture
rationale. This resume file is the *status snapshot*; the plan file is the
*full map*.

## How we're working (don't skip this if resuming)
This is a **guided build**, not a hand-it-to-you build. Protocol:
1. I explain a concept + exactly what a file needs to do.
2. **You write it** — I don't pre-generate files.
3. You paste it back, I review for correctness and explain any fixes.
4. We verify with a real command before moving to the next thing.

Reason this mode was chosen: the first attempt at this project generated a
full working repo automatically, and that defeated the point — the user
wants to actually understand Docker/Kubernetes/Terraform, not inherit a black
box. User's background: comfortable with Linux/SSH already; Docker,
Kubernetes, Terraform, and Git/CI were new going in.

Two separate repos are involved, on purpose (not a mistake to merge):
- **`/home/balenius/kubernetes-cluster`** — infra: Terraform, Kubernetes
  manifests, Argo CD config, these lesson docs. GitHub:
  `github.com/Balenius/kubernetes-cluster`.
- **`/home/balenius/game-project`** — the app being deployed (FastAPI
  backend + static JS frontend + Postgres, a Rock-Paper-Scissors game).
  GitHub: `github.com/Balenius/game-project`.

Each repo has its own git history — commits/pushes are done separately in
each (`git -C <path> ...` is handy for checking both without `cd`-ing).

## Status: modules complete

### ✅ M0 — Git, empty repo
`kubernetes-cluster` initialized, a `.gitignore` the user wrote and
iteratively debugged (learned: trailing-slash-means-directory-only, `.tfvars`
vs `*.tfvars`, `!exception` ordering), pushed to GitHub.

### ✅ M1 — Docker (in `game-project`)
- `backend/Dockerfile` — `python:3.12-slim`, layer-caching order (requirements
  before app code), non-root user, `HEALTHCHECK` via Python's `urllib`
  (no `curl` in the slim image), exec-form `CMD`. Along the way, caught and
  fixed a real bug: a shell-form `CMD` wrapped in the user's own quotes broke
  argument parsing entirely (not just a style/signal-handling issue as the
  linter warning implied) — fixed to exec-form JSON array.
- `frontend/Dockerfile` + `frontend/nginx.conf` — `nginx:alpine`, static
  files served from `/usr/share/nginx/html`, `/api/*` reverse-proxied to
  `backend:8000` (path preserved via the "mirror the location prefix"
  `proxy_pass` pattern — the trailing-slash gotcha). Hit and understood a
  real nginx behavior: `proxy_pass` to a literal (non-variable) hostname
  resolves at **config-load time**, so nginx refuses to boot at all if the
  hostname can't resolve — worked around for standalone testing with
  `docker run --add-host backend:127.0.0.1`.
- Both committed and pushed to `game-project`.

### ✅ M2 — Docker Compose (in `game-project`)
- Same-origin code edits: `frontend/app.js` `API_BASE` → relative `/api`;
  removed the dev-only `CORSMiddleware` from `backend/app/main.py`.
- `docker-compose.yml` — three services (`postgres`, `backend`, `frontend`),
  built up and tested **incrementally** (postgres alone → +backend → +
  frontend) rather than all at once. Verified:
  - Postgres initializes from the bind-mounted `db/schema.sql` (`players`
    table confirmed via `psql \dt`).
  - Backend reaches Postgres over Compose's service DNS
    (`postgres://postgres:testdb123@postgres:5432/rps`) — real
    `{"status":"ok"}` from `/api/health`.
  - Full browser test passed: played a 5-round game, leaderboard updated.
  - **Persistence proven**: `docker compose down` → `up` again, leaderboard
    entry survived (named volume `rpsvolume`, on disk as
    `game-project_rpsvolume` — lives inside Docker Desktop's own hidden WSL2
    distro `docker-desktop`, not the user's `Ubuntu` distro; inspect volume
    contents via `docker run --rm -v <vol>:/data alpine ls /data`, not by
    hunting for the raw host path).
- Committed as three focused commits (frontend/nginx, backend/CORS, compose)
  and pushed.

### 🔧 M3 — Terraform + cloud-init → k3s on Hyper-V (IN PROGRESS)
This is the flagged "likely rough patch" module (community-maintained
`taliesins/hyperv` Terraform provider). **Environment prep is fully done —
no fallback needed, proceeding with real Terraform.**

**Host prep checklist — all 6 items confirmed done:**
1. WinRM enabled (`Enable-PSRemoting`, Basic auth + unencrypted allowed for
   loopback use). **Hardened further than the base instructions**: the user
   also restricted the Windows Firewall rule to `127.0.0.1` only
   (`Get-NetFirewallRule -DisplayGroup "Windows Remote Management" |
   Set-NetFirewallRule -RemoteAddress 127.0.0.1`) — worth noting because the
   base WinRM config commands do *not* themselves enforce loopback-only (that
   was a correction made mid-session; `TrustedHosts` only governs outbound
   client trust, not inbound access — the firewall rule is what actually
   enforces it).
2. LAN network adapter name: **`Ethernet 2`** (needed for the Hyper-V virtual
   switch).
3. Terraform installed on **Windows** (runs from PowerShell, not WSL) —
   confirmed `terraform version` → **v1.14.7**.
4. ISO-building tool: **`oscdimg`** (Windows ADK) confirmed working.
5. Ubuntu 24.04 cloud image converted to VHDX (via WSL `qemu-img`), at
   **`C:\HyperV\images\ubuntu-24.04.vhdx`** (~2.04 GiB, dynamic).
6. SSH keypair generated **in WSL** (since that's where the user will SSH
   from, even though Terraform itself runs on Windows):
   `~/.ssh/id_ed25519` / `~/.ssh/id_ed25519.pub` (comment `k3s-hyperv`). Only
   the *public* key content needs to reach Terraform (as a variable value) —
   the private key never needs to touch Windows.

**Not yet decided:** the static LAN IP to reserve for the VM (`node_ip`
variable) — needs picking and reserving on the router before `terraform
apply`, not required yet for just `variables.tf`/`terraform init`.

## Next task (exact pickup point)

Writing `terraform/hyperv/versions.tf` and `terraform/hyperv/variables.tf`.

**`versions.tf`** — mostly fixed boilerplate, was given directly rather than
as an exercise:
```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    hyperv = {
      source  = "taliesins/hyperv"
      version = "~> 1.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}
```
(`local` and `null` are needed later in `main.tf` to render the cloud-init
file to disk and run the `oscdimg` command that builds the seed ISO.)

**`variables.tf`** — task given as a spec table, NOT written for the user yet
(this is the live exercise). One worked syntax example was given
(`node_name`), and the user is to write `variable` blocks for:

| Variable | Purpose |
|---|---|
| `hyperv_host` | WinRM host — default `"localhost"` |
| `hyperv_user`, `hyperv_password` | Windows admin creds (password `sensitive = true`) |
| `hyperv_winrm_port`, `hyperv_winrm_https` | connection details |
| `switch_name` | name for the Hyper-V virtual switch to create |
| `host_net_adapter_name` | `"Ethernet 2"` (gathered above) |
| `node_ip` | LAN IP to reserve for the VM — **not chosen yet** |
| `node_name`, `cpus`, `memory_bytes`, `disk_size_bytes` | VM identity/sizing |
| `ubuntu_vhdx_source` | `C:\HyperV\images\ubuntu-24.04.vhdx` |
| `vhd_destination_path` | where the VM's own boot-disk copy will live |
| `iso_tool` | default `"oscdimg"` |
| `k3s_version` | pin one, e.g. `"v1.31.5+k3s1"` |
| `ssh_authorized_key` | the public key content (from item 6 above) — no default, filled via `terraform.tfvars` later |

Key concepts taught alongside this: the `terraform { required_providers }`
block; the `variable` block shape (`description`/`type`/`default`/
`sensitive`); and the caveat that `sensitive = true` only redacts CLI output
— it does **not** encrypt `terraform.tfstate`, which is why `*.tfstate` stays
in `.gitignore` (tie-back to the M0 lesson).

**Verify step (once both files exist):**
```bash
mkdir -p terraform/hyperv     # if not already created
cd terraform/hyperv
# versions.tf and variables.tf go here
terraform init
```
Expect all three providers to download and
`Terraform has been successfully initialized!`. This step touches nothing in
Hyper-V yet — pure config/provider validation.

## What comes after this (per the plan, not started)
- `main.tf` — provider block; cloud-init rendering via `templatefile()` +
  `local_file` (writing `user-data`/`meta-data`) + `null_resource` with a
  `local-exec` provisioner running `oscdimg`; the Hyper-V virtual switch;
  copying/growing the VHDX; the `hyperv_machine_instance` VM resource tying
  it all together.
- `outputs.tf`, `terraform.tfvars` (git-ignored, real values) and
  `terraform.tfvars.example` (committed, placeholder values).
- `terraform apply`, fetch the kubeconfig, `kubectl get nodes` → `Ready`.
- Then M4 (raw Kubernetes manifests) → M5 (Kustomize) → M6 (Argo CD) → M7
  (GitHub Actions CI/CD) → M8 (Pi/AWS portability, scaffolded only).

## Docs written so far (this folder)
- `00-orientation.md` — the big picture / two-layer architecture / build order.
- `01-docker.md` — Docker concepts + both Dockerfiles (backend, frontend/nginx).
- `02-docker-compose.md` — Compose concepts + the three-service file.
- `03-terraform-hyperv.md` — IaC/Terraform/cloud-init concepts + the 6-item
  host prep checklist (all confirmed done, see above).
- `resume.md` — this file.

## Misc environment notes
- VS Code is set up as a multi-root workspace (`kubernetes-cluster` +
  `game-project` folders together), with Dockerfile-scoped autocomplete
  disabled in workspace settings (user wanted to write Dockerfiles without
  IDE suggestions helping too much, to force real understanding).
- The user's Postgres dev credentials in `docker-compose.yml`
  (`postgres`/`testdb123`/`rps`) are fine for local dev but are **not**
  committed as a `.env` — they're inline in the compose file (which itself
  contains this dev-only password in plain text, currently committed to
  `game-project`). Not a real security issue for a local personal project,
  but worth remembering if this repo ever goes further/public: rotate or move
  to an env file at that point.
- Model used for this session: Sonnet 5 (`claude-sonnet-5`) — chosen
  deliberately over Opus for this kind of small-file-review teaching loop
  (fast iteration, already proven capable of catching real bugs in this
  session); Opus reserved for genuinely gnarly steps if M3's Terraform
  provider fights us harder than expected.
