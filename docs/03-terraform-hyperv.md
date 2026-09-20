# 03 — Terraform + cloud-init: k3s on Hyper-V

## Why this module is different
Every module so far has been "write a file, test it, move on." This one adds
a wrinkle: **Terraform needs several things installed/enabled on Windows
before any `.tf` file can work at all.** So we do host prep as its own
checked-off phase, *then* write code — rather than discover halfway through
writing `main.tf` that WinRM isn't configured.

This is also the module I flagged at the very start as the likely rough
patch: the Hyper-V Terraform provider (`taliesins/hyperv`) is
community-maintained, not official, and can be fussier than, say, the AWS
provider. If it genuinely fights us, we have a documented fallback (install
k3s by hand over SSH) so it doesn't block your Kubernetes learning — but
let's give it a fair shot first.

## New vocabulary (for context while you do the prep)
- **Infrastructure as Code (IaC).** Instead of clicking through Hyper-V
  Manager, you *describe* the VM you want in a text file, and a tool
  reconciles reality to match it. The benefit isn't just automation — it's
  that the description is versioned, reviewable, and reproducible.
- **Terraform provider.** A plugin that knows how to talk to one specific
  system's API — AWS, Hyper-V, Kubernetes, whatever. `taliesins/hyperv`
  knows how to talk to Hyper-V specifically, over WinRM.
- **WinRM (Windows Remote Management).** A protocol for remotely running
  commands/config changes on Windows. Confusingly, the Hyper-V provider uses
  it even when the "remote" target is the same machine Terraform runs on —
  it always talks to Hyper-V *as if* managing it remotely, so WinRM has to be
  enabled even for `localhost`.
- **cloud-init.** A near-universal standard for configuring a Linux VM on its
  *very first boot* — creating users, running commands, installing packages
  — before you ever manually log in. Every environment we'll ever provision
  (Hyper-V now, AWS/Pi later) uses the exact same cloud-init file to install
  k3s. It's the piece that keeps "the same solution everywhere" true.
- **NoCloud datasource.** Cloud providers like AWS hand a VM its cloud-init
  config over a network metadata service. Hyper-V has no such service, so we
  fake it: burn the config onto a small ISO ("seed" disk) and attach it to
  the VM. cloud-init's "NoCloud" datasource knows to look for a CD-ROM
  labeled `cidata` and read its config from there.

## ✅ Host prep checklist — do this before we write any `.tf` file

Work through these **in Windows PowerShell** (run as Administrator where
noted), and report back what happened at each step — including any errors,
verbatim. Some of these I genuinely cannot verify from here (I only have a
shell into your WSL/Ubuntu side, not Windows), so this is one of the few
times your accurate reporting back is the *only* way we catch a problem
early.

### 1. Enable WinRM
```powershell
Enable-PSRemoting -Force
winrm quickconfig -q
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "localhost" -Force
```
**Security note, worth understanding rather than just running:** the last two
commands weaken WinRM's normal security (allowing basic auth and unencrypted
traffic) — that's a real downgrade, and not something you'd want on a
network-exposed WinRM setup. It's an acceptable *narrow* exception here
specifically because this traffic never leaves the machine (`localhost` to
`localhost`). We're not doing this for convenience everywhere — just for this
one loopback-only case.

Verify: `Test-WSMan localhost` should return without an error.

### 2. Note your network adapter name
```powershell
Get-NetAdapter
```
Write down the `Name` column value for whichever adapter is actually
connected to your LAN (e.g. `Ethernet` or `Wi-Fi`) — you'll need this for the
Terraform virtual switch later.

Name is : Ethernet 2

### 3. Install Terraform on Windows
Via [Chocolatey](https://chocolatey.org/) if you have it: `choco install
terraform`. Otherwise, download the Windows zip from
[terraform.io/downloads](https://www.terraform.io/downloads) and put
`terraform.exe` somewhere on your `PATH`.

Verify: `terraform version` in a **new** PowerShell window.

### 4. Get an ISO-building tool
We need something that can build a small ISO (for the cloud-init "seed"
disk). Recommended: **`oscdimg`**, part of the Windows ADK. Either:
- `choco install windows-adk-oscdimg`, or
- Install the [Windows ADK](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install) and add its `Deployment Tools\amd64\Oscdimg` folder to `PATH`.

Verify: running `oscdimg` alone (no args) in PowerShell should print usage
help, not "command not found".

### 5. Prepare the Ubuntu cloud image (VHDX)
This step is easiest done from **WSL** (this Ubuntu shell), outputting
directly into a path Windows can see (`/mnt/c/...`).
```bash
sudo apt-get update && sudo apt-get install -y qemu-utils   # gives you qemu-img
wget https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img
mkdir -p /mnt/c/HyperV/images
qemu-img convert -f qcow2 -O vhdx -o subformat=dynamic \
  ubuntu-24.04-server-cloudimg-amd64.img /mnt/c/HyperV/images/ubuntu-24.04.vhdx
```
Verify: the file exists and has a real size —
`ls -la /mnt/c/HyperV/images/ubuntu-24.04.vhdx` (expect tens to a couple
hundred MB, not 0 bytes).

### 6. Generate an SSH keypair (in WSL, since that's where you'll SSH from)
```bash
ssh-keygen -t ed25519 -C "k3s-hyperv"
```
Accept the default path (`~/.ssh/id_ed25519`) unless you have a reason not
to. We don't need the *private* key anywhere near Windows/Terraform — only
the **public** key's text content goes into a Terraform variable later
(`cat ~/.ssh/id_ed25519.pub`), so Terraform can embed it into the VM via
cloud-init.

## Report back
For each of the 6 items above: did it work, and what did the verify command
actually print? Paste real output, especially for anything that errored —
this is exactly the kind of module where a skipped detail causes a confusing
failure three steps later.

All 6 items above are done. `node_ip` decided: `192.168.50.178` (LAN
subnet, outside the router's DHCP pool).

## `versions.tf` and `variables.tf`

`versions.tf` is fixed boilerplate (the `terraform { required_providers }`
block declaring `hyperv`, `local`, `null`) — given directly rather than as an
exercise, since there's no real concept to learn from typing it out.

`variables.tf` declares every input the rest of the module needs:
`hyperv_host`/`hyperv_user`/`hyperv_password`, `hyperv_winrm_port`/
`hyperv_winrm_https`, `switch_name`, `host_net_adapter_name`, `node_ip`,
`node_name`, `cpus`, `memory_bytes`, `disk_size_bytes`, `ubuntu_vhdx_source`,
`vhd_destination_path`, `iso_tool`, `k3s_version`, `ssh_authorized_key`. Each
`variable` block can carry `description`/`type`/`default`/`sensitive` —
`sensitive = true` (used for `hyperv_password`) only redacts the value from
CLI output, it does **not** encrypt `terraform.tfstate`, which is why
`*.tfstate` is in `.gitignore` (same reasoning as the M0 `.gitignore` lesson).

Gotchas hit writing this file, worth knowing about HCL in general:
- **Windows paths need forward slashes.** `C:\HyperV\images\...` breaks HCL
  string parsing — `\H`, `\i`, `\u` aren't valid escape sequences, and a
  trailing backslash before the closing quote reads as an escaped quote,
  leaving the string unterminated. Windows accepts forward slashes fine
  (`C:/HyperV/images/ubuntu-24.04.vhdx`), so that's what to use.
- **No thousands-separators in numbers.** `"4,294,967,296"` isn't valid HCL,
  quoted or not. Byte counts are written as arithmetic instead, which stays
  readable and evaluates to a real number: `memory_bytes = 4 * 1024 * 1024 *
  1024` (4 GiB), `disk_size_bytes = 20 * 1024 * 1024 * 1024` (20 GiB — big
  enough to hold the ~2.04 GiB source VHDX once copied/grown).
- **HCL has no built-in size units.** No `Gi`/`Mi` suffixes like Kubernetes
  YAML has — the Hyper-V provider's memory/disk fields are plain byte
  integers, because the underlying Windows/Hyper-V WMI API works in bytes.

**Terraform for this module runs from Windows PowerShell, not WSL.**
`hyperv_host` defaults to `"localhost"`, and the WinRM firewall rule from
host prep is locked to `127.0.0.1`. WSL2 has its own network namespace and
virtual NIC, so a `localhost` connection from inside WSL doesn't land on
Windows's real loopback interface the way it does for a process running
directly on Windows — the WinRM connection would likely be refused. The
`.tf` files live in the WSL filesystem but are reached from PowerShell via
`\\wsl$\<Distro>\...` (or `\\wsl.localhost\<Distro>\...`).

Verified: `terraform init`, run from Windows PowerShell in
`terraform/hyperv/`, succeeded — all three providers downloaded (`hyperv`
1.2.1, `local` 2.9.1, `null` 3.3.2), `.terraform.lock.hcl` generated. This
step touches nothing in Hyper-V — pure config/provider validation.

## `main.tf` — provider block and the network switch

```hcl
provider "hyperv" {
  user     = var.hyperv_user
  password = var.hyperv_password
  host     = var.hyperv_host
  port     = var.hyperv_winrm_port
  https    = var.hyperv_winrm_https
  insecure = true
  use_ntlm = true
}
```
Given directly — this is provider-specific connection plumbing, not a
teaching moment. `insecure = true` and `use_ntlm = true` are needed because
this is a local self-signed WinRM setup, not a domain-joined one.

```hcl
resource "hyperv_network_switch" "main" {
  name              = var.switch_name
  switch_type       = "External"
  net_adapter_names = [var.host_net_adapter_name]
}
```
**Resource syntax:** `resource "<TYPE>" "<LOCAL_NAME>" { ... }` — the type
comes from the provider (`hyperv_network_switch`), the local name
(`main`) is yours to pick, and it's only used later when *referencing* the
resource elsewhere as `hyperv_network_switch.main.<attribute>` (easy to
mix up the declaration syntax with the reference syntax the first time).
`switch_type = External` (unquoted) would be wrong — HCL treats a bare
word as an identifier lookup, not a string; string values always need
quotes.

**Why `External`:** an external switch bridges the VM directly onto your
LAN via the host's real network adapter (`host_net_adapter_name`), so the
VM gets a routable LAN IP instead of being stuck behind Hyper-V's internal
NAT — needed so you can `kubectl`/`ssh` to it from anywhere on your network,
not just from the Hyper-V host itself.

## cloud-init files

cloud-init configures a Linux VM on its very first boot — before you ever
log in. These files are YAML/bash, not HCL, and some of them get filled in
by Terraform's `templatefile()` before being handed to the VM.

### `user-data.yaml.tpl`

```yaml
#cloud-config
hostname: ${node_name}
ssh_authorized_keys:
    - ${ssh_authorized_key}
write_files:
  - path: /usr/local/bin/ufw-setup.sh
    permissions: '0755'
    content: |
      ${indent(6, ufw_setup_script)}

runcmd:
    - /usr/local/bin/ufw-setup.sh
    - "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${k3s_version} sh -"
```
Three top-level cloud-config keys in play: `hostname` (a single scalar —
not a list, there's only ever one), `ssh_authorized_keys` (a YAML list, one
item here, but genuinely could have more), and `runcmd` (a list of shell
commands run near the end of boot). `write_files` drops the ufw script onto
the VM's disk before `runcmd` executes it — ordering matters: the firewall
script runs *before* the k3s install line, so the box is locked down before
anything starts listening.

The `${...}` placeholders are Terraform's `templatefile()` interpolation,
not YAML syntax — they get replaced when `main.tf` calls `templatefile()`
on this file (covered below).

**`${indent(6, ufw_setup_script)}` is the fiddly part.** `ufw_setup_script`
is the *raw, unrendered* text of `ufw-setup.sh`, passed in via `file(...)`
(not `templatefile()` — the script itself has no `${...}` to fill in).
`indent(n, string)` only prepends `n` spaces to the *second and later*
lines of a multi-line string — the first line's position comes entirely
from how much literal whitespace already precedes `${...}` in this `.tpl`
file. Those two numbers (the literal leading spaces here, and the `n`
argument to `indent()`) have to match, or the rendered YAML ends up with
mismatched indentation partway through the block and breaks. This file
uses 6 spaces of literal indent before `${indent(6, ...)}` — both must
agree.

Also worth knowing: a YAML literal block (`content: |`) needs the `|` alone
on its own line — content can't start on the same line as the `|`.

### `ufw-setup.sh`

```bash
#!/bin/bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 80 proto tcp comment "HTTP"
ufw allow 6443 proto tcp comment "Kubernetes API Server"
ufw allow 22 proto tcp comment "SSH"
ufw enable --force
```
Plain bash, not templated — no `${...}` vars needed. Default-deny-incoming
model, then explicit allows for exactly the three ports this build needs:
`22` (SSH — without it the VM is unreachable), `6443` (the Kubernetes API
server — what lets `kubectl` from outside the VM talk to the cluster), and
`80` (HTTP, for Traefik ingress once M4 adds one). `443` is deliberately
skipped for now — this build is LAN-only, no TLS yet. `ufw enable --force`
(not `-force`, which parses as bundled short flags) is needed because
cloud-init has no human around to answer the interactive confirmation
prompt.

### `network-config.yaml.tpl`

```yaml
network:
  version: 2
  ethernets:
    eth0:
      addresses:
        - ${node_ip}/24
      routes:
        - to: default
          via: 192.168.50.1
      nameservers:
        addresses:
          - 192.168.50.1
          - 8.8.8.8
```
Netplan-style (`version: 2`) NoCloud `network-config`, giving the VM
`node_ip` as a **static IP** instead of relying on DHCP. `eth0` is the
interface key — Ubuntu cloud images on Hyper-V commonly come up as `eth0`,
but this is unconfirmed until first real boot. If the VM isn't reachable
after `terraform apply`, wrong interface name is the first thing to
suspect — and it'd mean dropping into the Hyper-V console/VM Connect window
to check, since SSH wouldn't be reachable either. Gateway
(`192.168.50.1`) and DNS were confirmed against the real router, not
assumed.

## `main.tf` — the `local_file` resources

Three `local_file` resources render the cloud-init files above (with their
`${...}` placeholders filled in) to real files on disk, in a new
`terraform/hyperv/build/` directory (`local_file` creates missing parent
directories automatically — this directory still needs adding to
`.gitignore` as generated output, not done yet).

```hcl
resource "local_file" "user_data" {
  filename = "${path.module}/build/user-data"
  content = templatefile("${path.module}/../../cloud-init/user-data.yaml.tpl", {
    node_name          = var.node_name
    ssh_authorized_key = var.ssh_authorized_key
    k3s_version        = var.k3s_version
    ufw_setup_script   = file("${path.module}/../../cloud-init/ufw-setup.sh")
  })
}

resource "local_file" "network-config" {
  filename = "${path.module}/build/network-config"
  content = templatefile("${path.module}/../../cloud-init/network-config.yaml.tpl", {
    node_ip = var.node_ip
  })
}

resource "local_file" "meta-data" {
  filename = "${path.module}/build/meta-data"
  content = <<-EOT
    instance-id: ${var.node_name}
    local-hostname: ${var.node_name}
    EOT
}
```

`path.module` is the directory containing the current `.tf` file — needed
here because `cloud-init/*.tpl` files live at the repo root, two
directories above `terraform/hyperv/`, hence
`"${path.module}/../../cloud-init/<file>"`.

The `templatefile()` call's second argument is a map whose **keys must
match the template's `${...}` placeholder names**, not whatever the value
happens to represent elsewhere (e.g. the key has to be `node_name`, not
`hostname`, even though it fills in the `hostname:` YAML line).

`meta-data` has no `.tpl` file — its content is only two lines
(`instance-id`/`local-hostname`, both `var.node_name`), so it's built
directly as an HCL heredoc (`<<-EOT ... EOT`) instead. Two things to know
about `<<-` heredocs: everything between the markers is **literal text**,
not HCL — a stray line like `node_name = var.node_name` inside the heredoc
would just be text, not an assignment. And the amount of leading whitespace
stripped from every content line is set by **the closing marker's own
indentation** — `EOT` needs to be indented to match the content lines, or
nothing gets stripped and the rendered file ends up with literal leading
spaces.

`terraform validate` passes with the file in this state.

## Where we are now

- `versions.tf`, `variables.tf` — done.
- `main.tf` — provider block, `hyperv_network_switch.main`, and all three
  `local_file` resources are written and validated. Not yet written: the
  `null_resource` + `oscdimg` block (builds the seed ISO from the rendered
  `build/` files), the VHDX copy/grow, and the `hyperv_machine_instance`
  resource that ties node identity + switch + disk + seed ISO together.
- All three cloud-init files (`user-data.yaml.tpl`, `network-config.yaml.tpl`,
  `ufw-setup.sh`) — done.

See `docs/resume.md` for the exact next task and the full up-to-date
status.
