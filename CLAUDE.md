# CLAUDE.md

## What this repo is

The **infrastructure half** of a two-repo learning build: Terraform, cloud-init, Kubernetes manifests, Argo CD config, and the lesson docs in [`docs/`](./docs/).

The app being deployed lives in a separate repo, `../game-project` (FastAPI + static frontend + Postgres). Each repo has its own git history — commit and push in each separately (`git -C <path> ...` checks both without `cd`-ing).

**The learner profile, teaching rules, and guardrails in [`../game-project/CLAUDE.md`](../game-project/CLAUDE.md) apply here too.** They aren't repeated below; only what's specific to this repo is.

## Read this first, every session

1. **[`docs/resume.md`](./docs/resume.md)** — the status snapshot: what's done, what's blocked, the exact next task, and a list of things already verified so they don't get re-checked. This is the source of truth for *where we are*.
2. **`/home/balenius/.claude/plans/create-kubernetes-cluster-that-lovely-shannon.md`** — the master curriculum (modules M0–M8) and the architecture rationale. The source of truth for *where we're going*.

The numbered docs (`docs/00-orientation.md` … `docs/03-terraform-hyperv.md`) are the lesson write-ups for completed modules. Keep them caught up with the code when there's a natural pause.

## Guided build — I write the infra files, not you

This is the whole point of the repo. A previous attempt auto-generated a working setup and it defeated the purpose.

- **Explain the concept and what the file needs to do, then let me write it.** Don't pre-generate `.tf`, YAML, or cloud-init files.
- I paste it back, you review for correctness and explain the fixes.
- Verify with a real command before moving on.
- Fixed boilerplate with no learning value (e.g. `versions.tf`, provider connection blocks) can be given directly — say so when you do.

## Debugging — verify, don't theorize

**Test the hypothesis directly before proposing a fix.** Don't put me through rounds of guess-fix-retry derived from reading error text alone.

- Inspect the real artifacts, not my pasted output: read the rendered file, check it byte-level, look inside the ISO, run the failing command yourself.
- You can reach more than you'd think from WSL: `/mnt/c`, `/mnt/e`, Windows `.exe` via interop, and the LAN (ping/SSH the VM).
- Say plainly which things you verified versus still assume, and correct yourself out loud when a result contradicts something you asserted earlier.

## Git

**I run the commits, not you.** Don't commit, and don't offer to as a next step — just say the work is ready and move on. Reminding me when I've gone a while without committing is still welcome.

## Environment quirks that will bite

The repo lives in WSL but **Terraform for the Hyper-V module runs from Windows PowerShell**, reaching these files over `\\wsl.localhost\...`. Consequences:

- **Every Terraform command here needs `-lock=false`** — state locking doesn't work over the WSL share.
- Build artifacts go to a native Windows path (`C:/HyperV/build`), not into the repo — Hyper-V can't mount an ISO from a WSL path.
- The `taliesins/hyperv` provider is community-maintained and has real bugs (silent path normalization, conflicting-argument rules).

**Before touching the Hyper-V Terraform, read the "Windows, WSL, and a community provider" section at the end of [`docs/03-terraform-hyperv.md`](./docs/03-terraform-hyperv.md)** — it documents all nine environment problems already solved, with the verified fixes.

## Secrets

`.gitignore` already covers `*.tfstate`, `*.tfvars` (except `*.tfvars.example`), `.terraform/`, kubeconfigs, and disk images. `terraform.tfvars` holds real Windows credentials and must stay untracked — confirm before any push.
