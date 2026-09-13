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
