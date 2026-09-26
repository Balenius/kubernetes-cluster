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

**`node_ip` decided:** `192.168.50.178` (LAN subnet, outside the router's
DHCP pool — see the M3 doc for the external-switch networking reasoning).
Still needs an actual DHCP-reservation/exclusion on the router before
`terraform apply` touches real hardware, but the value itself is set in
`variables.tf` now.

### ✅ `terraform/hyperv/versions.tf` and `terraform/hyperv/variables.tf` — DONE

**`versions.tf`** — fixed boilerplate, given directly rather than as an
exercise (content unchanged from what was planned — see git history for the
file itself rather than duplicating it here).

**`variables.tf`** — written by the user as the live exercise, from a spec
table covering all of: `hyperv_host`, `hyperv_user`/`hyperv_password`,
`hyperv_winrm_port`/`hyperv_winrm_https`, `switch_name`,
`host_net_adapter_name`, `node_ip`, `node_name`, `cpus`, `memory_bytes`,
`disk_size_bytes`, `ubuntu_vhdx_source`, `vhd_destination_path`, `iso_tool`,
`k3s_version`, `ssh_authorized_key`. Real bugs caught and fixed along the
way (all now correct in the committed file):
- **Backslash paths broke HCL parsing.** Windows paths like
  `C:\HyperV\images\...` hit Terraform's string-escape handling (`\H`,
  `\i`, `\u` aren't valid escapes), and a trailing `\"` before a closing
  quote was read as an escaped quote character, leaving the string
  unterminated. Fixed by switching to forward slashes
  (`C:/HyperV/images/ubuntu-24.04.vhdx`) — Windows accepts those fine, and
  it sidesteps HCL escaping entirely.
- **`hyperv_wnrm_port`/`hyperv_wnrm_https` typo** → corrected to
  `hyperv_winrm_port`/`hyperv_winrm_https`.
- **Comma-grouped number literals** (`"4,294,967,296"`) aren't valid HCL —
  no thousands-separator support, quoted or not. Rewritten as arithmetic
  expressions for readability while staying real numbers:
  `memory_bytes = 4 * 1024 * 1024 * 1024` (4 GiB),
  `disk_size_bytes = 20 * 1024 * 1024 * 1024` (20 GiB — the original draft
  value of ~1.2 GiB was too small to even hold the ~2.04 GiB source VHDX
  being copied/grown from).

Key concepts taught alongside this: the `terraform { required_providers }`
block; the `variable` block shape (`description`/`type`/`default`/
`sensitive`); the caveat that `sensitive = true` only redacts CLI output —
it does **not** encrypt `terraform.tfstate`, which is why `*.tfstate` stays
in `.gitignore` (tie-back to the M0 lesson); HCL has no built-in size
units (no `Gi`/`Mi` suffixes) — the Hyper-V provider's memory/disk fields
are plain byte integers because the underlying Windows/Hyper-V WMI API
itself works in bytes.

**Also confirmed: Terraform must run from Windows PowerShell, not WSL,**
for this module specifically — `hyperv_host` defaults to `"localhost"`, and
the WinRM firewall rule from host prep is locked to `127.0.0.1` only. WSL2
runs in its own network namespace with a separate virtual NIC, so a
`localhost` connection from inside WSL does not land on the Windows host's
real loopback interface the way a process running directly on Windows does
— the WinRM connection would likely be refused. The `.tf` files live in the
WSL filesystem but are reached from PowerShell via the `\\wsl$\<Distro>\...`
(or `\\wsl.localhost\<Distro>\...`) UNC path.

**Verified:** `terraform init` run from Windows PowerShell in
`terraform/hyperv/` succeeded — all three providers downloaded (`hyperv`
1.2.1, `local` 2.9.1, `null` 3.3.2), `.terraform.lock.hcl` generated,
`Terraform has been successfully initialized!`. `.terraform/` and
`*.tfstate` are already covered by the existing `.gitignore` from M0. This
step touched nothing in Hyper-V yet — pure config/provider validation.

**`variables.tf` changed further during the real `apply`** (full reasoning in
the Windows/WSL gotchas section near the end of this file): `hyperv_host`
`"localhost"` → `"127.0.0.1"`; `hyperv_winrm_port` `"5986"` → `"5985"`;
`hyperv_winrm_https` `"true"` → `"false"`; `hyperv_user` `"balen"` →
`"hyperv"` (a dedicated local admin account); trailing slash dropped from
`vhd_destination_path` (it was producing `E:/Hyper-V/terraform//node1.vhdx`);
and a new `build_dir` variable added, defaulting to `"C:/HyperV/build"`.

### 🔧 `terraform/hyperv/main.tf` — IN PROGRESS (started, not complete)

So far, two pieces written and reviewed correct:

- **The `provider "hyperv" {}` block** — given directly (provider-specific
  connection plumbing, not a teaching moment), wired to
  `hyperv_user`/`hyperv_password`/`hyperv_host`/`hyperv_winrm_port`/
  `hyperv_winrm_https`, plus `insecure = true` and `use_ntlm = true` (needed
  because this is a local self-signed WinRM setup, not a domain).
- **`resource "hyperv_network_switch" "main" {}`** — user-written exercise.
  Mistakes caught and fixed along the way: confused the `resource "<TYPE>"
  "<LOCAL_NAME>" {}` declaration syntax with a later *reference* to the
  resource (wrote the dotted `type.name.attribute` reference string as if it
  were the type/name themselves); and an unquoted `switch_type = External`
  (HCL treats a bare word as an identifier lookup, not a string — needs
  quotes). Both fixed; block is now correct (`name = var.switch_name`,
  `switch_type = "External"`, `net_adapter_names = [var.host_net_adapter_name]`).

### ✅ `cloud-init/user-data.yaml.tpl` — DONE

New territory: YAML cloud-config (not HCL), templated via Terraform's
`templatefile()` — `${...}` placeholders in this file are Terraform template
interpolation, filled in later when `main.tf` calls `templatefile()` (not
written yet). Three top-level keys: `hostname` (`${node_name}`),
`ssh_authorized_keys` (a YAML list, one item: `${ssh_authorized_key}`), and
`runcmd` (a YAML list, one item: the k3s scripted install pinned via
`INSTALL_K3S_VERSION=${k3s_version}`).

Mistakes caught and fixed: first draft copy-pasted Terraform `variable "..."
{ }` block syntax around the whole thing (doesn't exist in YAML) and used
`key = value` (HCL) instead of `key: value` (YAML); then over-corrected by
making `hostname` a YAML list when it needed to stay a single scalar value
(only `ssh_authorized_keys` and `runcmd` are genuinely lists, since only
those could have more than one item).

**Aside, worth remembering:** the user tested the k3s install command
directly in their WSL shell (`curl -sfL https://get.k3s.io |
INSTALL_K3S_VERSION=v1.31.5+k3s1 sh -`) to see it work — this actually
installed and started a real k3s server **on the WSL dev box itself**, not
inside a VM (no VM exists yet). Uninstalled afterward via
`sudo /usr/local/bin/k3s-uninstall.sh` (the installer drops this script for
undoing itself; `sudo systemctl stop k3s` would only pause it). Confirms WSL
here has systemd enabled (k3s's installer refuses to proceed without
systemd/openrc as a supervisor). Worth remembering if k3s ever gets tested
ad-hoc again: it's a real service with real system-level changes, not a
sandboxed thing — uninstall it when done experimenting outside the VM.

### ✅ `cloud-init/ufw-setup.sh` — DONE

Plain bash, not templated (no `${...}` vars needed). Default-deny-incoming
model: `ufw default deny incoming` / `ufw default allow outgoing`, then
explicit `ufw allow <port> proto tcp comment "..."` for exactly three ports
— `22` (SSH — without this the VM is unreachable), `6443` (Kubernetes API
server — what lets `kubectl` from outside the VM talk to the cluster), `80`
(HTTP, for Traefik ingress once M4 adds one). `443` deliberately skipped for
now (plan is LAN-only, no TLS yet). Enabled non-interactively via
`ufw enable --force` (cloud-init has no human to answer prompts).

Mistakes caught and fixed: `-force` (single dash, gets parsed as bundled
short flags, not the long-form flag) → `--force`; missing shebang line
(`#!/bin/bash`) added; file was briefly named `ufw.sh` before being renamed
to match the plan's `ufw-setup.sh` (old file confirmed not left behind).

**Now wired up:** its contents get onto the VM via `user-data.yaml.tpl`'s
`write_files:` (writes it to `/usr/local/bin/ufw-setup.sh`, `permissions:
'0755'`) + `runcmd:` (executes it, deliberately *before* the k3s install
line — lock the firewall down first). See the `user-data.yaml.tpl` entry
below for the mistakes made getting this wired up correctly.

### ✅ `cloud-init/network-config.yaml.tpl` — DONE

Netplan-style (`version: 2`) NoCloud `network-config`, for `node_ip`'s
**static IP**. One interface key (`eth0` — Ubuntu cloud images on Hyper-V
commonly come up as `eth0`; unconfirmed until first real boot — if the VM
isn't reachable after `terraform apply`, wrong interface name is the first
thing to suspect, and it means dropping to the Hyper-V console/VM Connect
window since SSH wouldn't be reachable either), `addresses: [${node_ip}/24]`,
a default route `via:` the gateway, `nameservers.addresses:`. Gateway
(`192.168.50.1`) and DNS confirmed correct by the user via `ipconfig`/router
admin, not assumed.

Mistake caught and fixed: first draft literally kept `<interface-name>: eth0`
(the placeholder text itself) instead of replacing it with the real YAML key
`eth0:`.

### ✅ `user-data.yaml.tpl` — `write_files:`/`runcmd:` wiring — DONE

Added a `write_files:` entry (path `/usr/local/bin/ufw-setup.sh`,
`permissions: '0755'`, `content: |` literal block) and a second `runcmd:`
item to execute it before the k3s install line. The real teaching content
here was **`${indent(6, ufw_setup_script)}`** — `ufw_setup_script` gets
passed into `templatefile()` from `main.tf` as `file(".../ufw-setup.sh")`
(raw, unrendered text, since the script itself has no `${...}` to fill in).
`indent(n, string)` only prepends `n` spaces to the *2nd and later* lines of
a multi-line string — the first line's position comes entirely from how much
literal whitespace precedes `${...}` in the template itself. Those two
numbers (the literal leading spaces in the `.tpl` file, and the `n` argument
to `indent()`) have to match, or the rendered YAML block ends up with
mismatched indentation partway through and breaks. Went through several
wrong states before landing correctly: `|` with content on the same line
(invalid — `|` must be alone on its line), then correct-line but 14 spaces
(mismatched with `indent(6, ...)`), finally 6 spaces matching. Also fixed
along the way: `runcmd:`'s second command was written as a continuation of
the first list item (missing its own `- ` marker), which would have folded
both commands into one nonsense string instead of two separate commands.

### ✅ `terraform/hyperv/main.tf` — `local_file` resources (DONE)

Three `local_file` resources, reviewed, **`terraform validate` passes**:

- **`local_file.user-data`** (renamed from `user_data` — see rename note
  below) — `templatefile()` over `user-data.yaml.tpl` with vars `node_name`,
  `ssh_authorized_key`, `k3s_version`, `ufw_setup_script` (the last via
  plain `file()`, not `templatefile()` — the script itself isn't
  templated). Mistakes fixed: vars-map key named `hostname` instead of
  `node_name` (map keys must match the template's placeholder names, not
  the YAML key the value happens to fill); a bare `file(...)` call with no
  `key =` in front (map entries need `key = value` like anywhere else in
  HCL); `ssh_authorized_keys` (wrong, plural) instead of
  `ssh_authorized_key` (matches neither the declared variable nor the
  template placeholder, both singular).
- **`local_file.network-config`** — same pattern, one var (`node_ip`).
  Correct on first attempt.
- **`local_file.meta-data`** — no `.tpl` file for this one (content's only
  2 lines: `instance-id`/`local-hostname`, both `var.node_name`) — built
  directly as an HCL string via a heredoc (`<<-EOT ... EOT`) instead.
  Mistake caught: first drafts tried writing YAML-style `key: value` lines
  and a bogus `node_name = var.node_name` as if they were `local_file`
  resource arguments (they're not — `local_file` only knows `filename`/
  `content`/etc.; the YAML-looking lines need to be literal text *inside*
  the `content` string). Then a heredoc indentation subtlety: with `<<-`,
  the amount of leading whitespace stripped from every content line is
  determined by **the closing marker's own indentation**, not the content
  lines' — first draft had `EOT` flush-left while content was indented 4
  spaces, so nothing got stripped and the rendered file would have had
  literal leading spaces; fixed by indenting `EOT` to match.

Key concept taught: `path.module` (the directory containing the current
`.tf` file) is needed throughout because `cloud-init/*.tpl` files live at
the repo root, two directories above `terraform/hyperv/` — paths are built
as `"${path.module}/../../cloud-init/<file>"`. Output files are written to
`terraform/hyperv/build/` (`local_file` creates missing parent dirs
automatically) — now in `.gitignore` (see below).

### ✅ `terraform/hyperv/main.tf` — `null_resource.build_seed_iso` (DONE)

Builds the NoCloud seed ISO from the three rendered `build/` files:

```hcl
resource "null_resource" "build_seed_iso" {
  provisioner "local-exec" {
    command = " ${var.iso_tool} -n -m -lcidata \"${path.module}/build\" \"${path.module}/build/seed.iso\""
  }
  triggers = {
    user-data       = local_file.user-data.content_md5
    network-config  = local_file.network-config.content_md5
    meta-data       = local_file.meta-data.content_md5
  }
}
```

Concepts: `null_resource` (from the `null` provider) manages nothing real —
it only hosts a `provisioner` block, for running a command Terraform has no
native resource type for. `provisioner "local-exec"` runs on the machine
executing `terraform apply` (Windows here), not on the VM. `triggers` (a
map) is how `null_resource` knows to rerun its provisioner, since it has no
real state to diff — referencing all three `local_file.*.content_md5`
values means it reruns whenever rendered content changes, and forces
Terraform's dependency graph to wait for all three `local_file`s first.
`-lcidata` is **not cosmetic** — NoCloud's datasource specifically looks
for a volume labeled exactly `cidata`.

Mistakes fixed along the way (several passes): command written as a bare
line with no `provisioner` block around it at all; then a `provisioner
"local-exec" command = "..."` with the `command` argument missing its
enclosing `{ }` body; then the command string's embedded path-quotes
weren't escaped (`\"..\"`), which ended the outer string early; `triggers`
first written as a YAML-style list (`- item`) instead of an HCL map
(`key = value`); and a reference to `local_file.meta_data` (underscore)
that didn't match the actual declared resource name `local_file.meta-data`
(hyphen) — resource references must match the declared local name exactly.
Also initially named `null_resource.meta-data`, colliding (confusingly,
though not erroring, since type+name is the real address) with the
unrelated `local_file.meta-data` — renamed to `build_seed_iso`.

### ✅ `terraform/hyperv/main.tf` — `hyperv_vhd.boot_disk` (DONE)

```hcl
resource "hyperv_vhd" "boot_disk" {
  path   = local.boot_disk_path_win
  source = var.ubuntu_vhdx_source
  size   = var.disk_size_bytes
}
```

Copies `ubuntu_vhdx_source` (the shared, reusable base image) to a
VM-specific file at `vhd_destination_path`, grown to `disk_size_bytes` —
needed because the VM can't write directly onto the shared base image
(would corrupt it / block reuse for future VMs). Mistake fixed: `path`'s
string was missing its closing `"`, leaving it unterminated.

Two later changes made during the real `apply` (see the Windows/WSL gotchas
section below for the full reasoning): **`vhd_type = "Dynamic"` was removed**
(the provider declares it `ConflictsWith` `source` — a copy inherits its
type from the source file, so it can't be independently set), and **`path`
now takes a backslashed value** via `local.boot_disk_path_win` rather than
the forward-slash interpolation, to stop the provider's silent path
normalization from breaking the plan/apply contract.

Also covered: the `${var.x}` vs bare `var.x` rule — bare (no quotes, no
`${}`) when the whole argument value is just that one reference (`source`,
`size`); `"${var.x}/${var.y}.ext"` interpolation only needed when mixing a
variable into a larger string with literal text.

### Rename note: `local_file.user_data` → `local_file.user-data`

Not itself part of the plan — came up when standardizing naming style
across the `local_file` resources. State was empty at the time, so this
specific rename cost nothing. (No longer true going forward: state now holds
7 real resources, so any future rename needs the handling below.) Covered as
a concept for when it matters: a resource's address
(`type.name`) is its identity in `terraform.tfstate`; renaming it in config
without telling Terraform makes the next plan show a destroy (old address)
+ create (new address) instead of an in-place rename — fine for a
`local_file`, potentially an outage/data-loss for a VM/disk/DB. Two ways to
handle it safely: a `moved` block (`moved { from = old_addr; to = new_addr
}`, a top-level block, e.g. placed directly above the resource it
describes — declarative, versioned in git, applies automatically on the
next `plan`/`apply` for anyone) or `terraform state mv <old> <new>` (an
imperative one-off CLI edit to the state, not captured in code, easy for a
teammate to miss). Also noted: the state update only actually persists
after an `apply` — a `plan` alone doesn't write state, so a `moved` block
should stay in the config until an `apply` has actually run, then it's
safe to delete.

### ✅ `terraform/hyperv/outputs.tf` — DONE

```hcl
output "node_ip" {
  description = "IP of node"
  value       = var.node_ip
}
```
Surfaces the address you'll actually `ssh`/`kubectl` to after `apply`
(via `terraform output`), rather than having to remember it from
`variables.tf`.

### ✅ `.gitignore` — `terraform/hyperv/build/` added (DONE)

Generated Terraform output (rendered cloud-init files + seed ISO) —
reproducible from source, doesn't belong in git.

### ✅ `terraform/hyperv/terraform.tfvars` + `terraform.tfvars.example` — DONE

Four variables in `variables.tf` have no `default` (would prompt or fail
non-interactively without a value): `hyperv_password`, `switch_name`,
`node_name`, `ssh_authorized_key`. `terraform.tfvars` supplies real values
for these (confirmed still correctly git-ignored via the existing
`*.tfvars` / `!*.tfvars.example` pair — not tracked, not staged);
`terraform.tfvars.example` has the same four keys with obvious placeholder
values, committed.

### ✅ `terraform/hyperv/main.tf` — `hyperv_machine_instance.hyperv_node` (DONE)

The resource that actually creates the VM. Schema was looked up from the
provider's docs first (it's large — most of its arguments are irrelevant
here). The subset used:

- Top level: `name`, `generation = 2` (UEFI; Ubuntu 24.04 cloud images are
  built for Gen 2), `processor_count`, `static_memory = true` +
  `memory_startup_bytes` (simpler than the dynamic-memory min/max mode, and
  right for a fixed-size home-lab VM).
- `network_adaptors { }` — `name`, `switch_name =
  hyperv_network_switch.main.name`, and `wait_for_ips = false` (see gotchas).
- `hard_disk_drives { }` — `controller_type = "Scsi"` (Gen 2 VMs have no IDE
  controllers), `controller_number = 0`, `controller_location = 0`, `path =
  hyperv_vhd.boot_disk.path`. **Keep that reference rather than reusing the
  local** — it's what gives Terraform the implicit "VM waits for disk"
  dependency.
- `dvd_drives { }` — `controller_number = 0`, `controller_location = 1` (the
  disk already holds location 0 on the same controller), `path` pointing at
  the seed ISO.
- `vm_firmware { }` — Secure Boot config plus a `boot_order` block (see
  gotchas).
- `depends_on = [null_resource.build_seed_iso]` — needed because
  `null_resource` exposes no attribute to reference, so there'd otherwise be
  no dependency edge telling Terraform to build the ISO before the VM.

Mistakes caught: all three nested blocks were first written as YAML-style
lists (`- key = value`) — the same reflex that hit `triggers` earlier; block
bodies are plain `key = value` pairs. Also `nic0` unquoted (bare words are
identifier lookups, not strings) and `static memory = true` (space instead
of underscore, making it two identifiers).

## 🔑 Windows/WSL/provider gotchas hit during the real `apply`

This module's "likely rough patch" warning was earned. Everything below cost
real debugging time — read this section before touching Terraform here again.

1. **State locking fails over the WSL share.** `Error acquiring the state
   lock ... Incorrect function.` Terraform's local backend uses a Windows
   file-locking syscall the `\\wsl.localhost\` 9P filesystem doesn't
   implement. **Every command in this module needs `-lock=false`**
   (`terraform plan -lock=false`, `terraform apply -lock=false`). Safe here:
   single user, local state, no concurrent runs.

2. **WinRM port/protocol mismatch.** `variables.tf` originally said port
   `5986` + `https = true`, but the host prep only ever created the **HTTP**
   listener on **5985** (an HTTPS listener needs a certificate, never set
   up). Symptom: `dial tcp [::1]:5986 ... actively refused`. Fixed to
   `hyperv_winrm_port = "5985"`, `hyperv_winrm_https = "false"`. Also
   changed `hyperv_host` from `"localhost"` to **`"127.0.0.1"`** — `localhost`
   resolved to IPv6 `[::1]`, but the hardened firewall rule is scoped to the
   IPv4 literal. Diagnostic: `winrm enumerate winrm/config/listener`.

3. **WinRM auth (401).** Next symptom was `401 - invalid content type`.
   Root cause: the user signs into Windows with Windows Hello (PIN), so
   there was no usable account password for WinRM. **Resolved by creating a
   dedicated local admin account** — `hyperv_user` is now `"hyperv"` (was
   `"balen"`), with its password in `terraform.tfvars`. Better practice than
   embedding a personal login anyway. Useful diagnostics if this recurs:
   `Get-LocalUser | Select Name, PrincipalSource` (shows `Local` vs
   `MicrosoftAccount`), and validating a password without side effects:
   ```powershell
   Add-Type -AssemblyName System.DirectoryServices.AccountManagement
   $ctx = [System.DirectoryServices.AccountManagement.PrincipalContext]::new('Machine', $env:COMPUTERNAME)
   $ctx.ValidateCredentials('hyperv', '<password>')
   ```

4. **`oscdimg` takes quotes literally — VERIFIED EMPIRICALLY.** This one ate
   the most time. `local-exec` runs via `cmd /C`, and escaped quotes in the
   command string survive into `oscdimg`'s arguments as literal characters;
   quotes aren't legal in Windows filenames, hence
   `Error 123: The filename, directory name, or volume label syntax is
   incorrect`. Tested directly, three runs: unquoted paths → **exit 0, ISO
   built**; quoted paths → **reproduced the error verbatim**; unquoted with
   the ISO already present → **exit 0, clean overwrite**. So: **no quotes in
   the command**, which is fine because the paths have no spaces.
   ```hcl
   command = "${var.iso_tool} -n -m -lcidata ${local.build_dir_win} ${local.build_dir_win}\\seed.iso"
   ```

5. **The `UNC paths are not supported. Defaulting to Windows directory.`
   warning is harmless noise.** It prints on every `local-exec` run because
   `cmd.exe` can't use a UNC path as its working directory — but the
   successful oscdimg runs printed it too. As long as paths are absolute, it
   doesn't matter. (Mid-session this was wrongly treated as fatal, and a
   `pushd`/`popd` workaround was tried and abandoned — don't go down that
   road again.)

6. **Build output must live on a native Windows path.** `build_dir` is now
   `C:/HyperV/build`, not a directory inside the repo. Two reasons: the
   legacy toolchain is happier, and more importantly **Hyper-V cannot attach
   a DVD ISO from `\\wsl.localhost\...`** — the seed ISO has to be on a real
   Windows filesystem for the VM to mount it. The `.tpl` *source* paths still
   use `${path.module}/../../cloud-init/...` (reading from the repo over the
   WSL share is fine — Terraform's own file I/O handles UNC).

7. **`vhd_type` conflicts with `source`.** Provider schema declares them
   mutually exclusive — a copied VHD inherits its type from the source file.
   Removed.

8. **Provider path normalization breaks the plan/apply contract.** Error:
   `Provider produced inconsistent final plan ... was "E:/Hyper-V/..." but
   now "E:\\Hyper-V\\..."`. The provider silently rewrites forward slashes to
   backslashes during apply, so the value Terraform was promised at plan time
   isn't what came back. Terraform calls this "a bug in the provider" and it
   is. **Fix: feed it backslashes from the start** so normalization is a
   no-op — hence `local.boot_disk_path_win` / `local.build_dir_win` and the
   `replace(..., "/", "\\")` pattern. Leaving forward slashes would also
   cause a permanent phantom diff on every future plan.

9. **Secure Boot rejects Ubuntu by default.** VM booted to
   `The signed image's hash is not allowed (DB)` on the SCSI disk. Gen 2 VMs
   default to the `MicrosoftWindows` Secure Boot template, which only trusts
   Windows-signed bootloaders; Ubuntu's shim is signed by the Microsoft UEFI
   CA. Fix:
   ```hcl
   vm_firmware {
     enable_secure_boot   = "On"
     secure_boot_template = "MicrosoftUEFICertificateAuthority"
   }
   ```
   (`enable_secure_boot = "Off"` also works but is the blunter option.) A
   `boot_order` block with `boot_type = "HardDiskDrive"` was added in the
   same place to skip the pointless PXE attempt on every boot.

10. **`wait_for_ips = false`.** The provider otherwise blocks waiting for the
    VM to report an IP via Hyper-V integration services. Pointless here — the
    IP is statically assigned by cloud-init, so there's nothing to discover —
    and it turns any boot problem into a very long hang.

11. **Apply is slow even when healthy.** The VHDX copy/grow alone took
    ~2m30s, and `hyperv_machine_instance` sat at `Still creating...` for
    ~15 minutes before eventually succeeding. Don't assume a hang is a
    failure too early.

**Final result: `Apply complete! Resources: 7 added, 0 changed, 0 destroyed.`**
The VM is running, reachable at `192.168.50.178` (ping ~0.4ms), SSH port
open, and identifies as Ubuntu 24.04 (`OpenSSH_9.6p1 Ubuntu-3ubuntu13.19`).

## Next task (exact pickup point) — 🔴 BLOCKED: cloud-init didn't apply user-data

**The VM boots and is reachable, but SSH key auth is rejected for every
username tried (`ubuntu`, `root`, `balenius`, `node1`) — the server offers
only `publickey`, and the key isn't installed. There is currently no way
into the VM: no SSH key, and no console password was ever set.**

Everything on the build side has already been verified correct — **don't
re-do this work**:

- `C:\HyperV\build\user-data` renders correctly: valid YAML, `#cloud-config`
  as the exact first line, **no BOM, no CRLF**, the SSH key present verbatim,
  all four expected top-level keys (`hostname`, `ssh_authorized_keys`,
  `write_files`, `runcmd`). The fiddly `${indent(6, ufw_setup_script)}` came
  out correctly indented.
- `~/.ssh/id_ed25519.pub` is **byte-identical** to `ssh_authorized_key` in
  `terraform.tfvars`.
- `seed.iso` was parsed at the ISO9660 level: volume label **`CIDATA`**,
  contains `USER-DATA` (616 b), `META-DATA` (41 b), `NETWORK-CONFIG` (238 b)
  with correct content. Names are uppercase with **no Joliet and no Rock
  Ridge** extensions — Linux's isofs driver lowercases bare ISO9660 names by
  default, so cloud-init *should* still match them, but this remains the one
  unverified assumption in the chain and is worth confirming.
- The DVD is genuinely attached — the earlier failed boot summary listed
  `SCSI DVD (0,1)` as a boot candidate.

**The one cheap diagnostic not yet run: what hostname does the Hyper-V
console login prompt show?**
- `node1 login:` → cloud-init *did* read the seed (that hostname can only
  come from `meta-data`/`user-data`), so the datasource works and the problem
  is narrower — something in the SSH module or the default-user assumption.
- `ubuntu login:` → cloud-init never processed the seed at all. That would
  also mean the static IP didn't come from `network-config`, making
  `192.168.50.178` a DHCP lease — note the router DHCP reservation/exclusion
  flagged earlier in this file **was never actually done**, so the pool may
  well include `.178`.

Likely follow-ups once that's known:
- Getting *into* the locked-out VM: boot to GRUB and add `init=/bin/bash` to
  the kernel line for a root shell, then read `/var/log/cloud-init.log` and
  `cloud-init status --long`. That log is the authoritative answer.
- **Add a break-glass console password to `user-data.yaml.tpl`** so a future
  first boot is never a lockout: top-level `password:`, `chpasswd: {expire:
  false}`, and leave `ssh_pwauth: false` so it's console-only. Should have
  been there from the start for a VM being brought up for the first time.
- If the ISO naming turns out to be the culprit, rebuild with Joliet
  (`oscdimg -j1 ...`) or switch ISO tools.

## What comes after this (once the VM is reachable)
- Confirm cloud-init finished (`cloud-init status`) and that `runcmd`
  actually installed k3s (`systemctl is-active k3s`).
- Fetch the kubeconfig from `/etc/rancher/k3s/k3s.yaml`, rewrite its
  `server:` address from `127.0.0.1` to `192.168.50.178`, and verify
  `kubectl get nodes` → one `Ready` node from the WSL side.
- Then M4 (raw Kubernetes manifests) → M5 (Kustomize) → M6 (Argo CD) → M7
  (GitHub Actions CI/CD) → M8 (Pi/AWS portability, scaffolded only).

## Design notes (asked and answered along the way)

**Single-node, on purpose.** This is a single-node k3s cluster, not
multi-node — `node_ip`, `node_name`, `cpus` etc. in `variables.tf` are
singular on purpose, matching the plan's `terraform apply` → one VM →
`kubectl get nodes` → one `Ready` node. Deliberate simplicity/resource
choice for a home-lab-on-one-Hyper-V-host setup, not an oversight — k3s
supports adding more nodes later (agents joining via `K3S_URL` + a token),
so the door isn't closed, just out of scope for this build. Would need
`variables.tf`/`main.tf` reworked toward a list/`count`- or
`for_each`-based node resource if that ever changes.

## Docs written so far (this folder)
- `00-orientation.md` — the big picture / two-layer architecture / build order.
- `01-docker.md` — Docker concepts + both Dockerfiles (backend, frontend/nginx).
- `02-docker-compose.md` — Compose concepts + the three-service file.
- `03-terraform-hyperv.md` — **now fully caught up with the code.** Covers
  IaC/Terraform/cloud-init concepts, the 6-item host prep checklist,
  `variables.tf`, the whole of `main.tf` (provider, switch, `local_file`s,
  `null_resource`/`oscdimg`, `locals`, `hyperv_vhd`,
  `hyperv_machine_instance`), the cloud-init files, and a long
  "Windows, WSL, and a community provider" section documenting all nine
  environment problems hit during the real `apply`. That last section is the
  one to re-read before rebuilding this module anywhere.
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
