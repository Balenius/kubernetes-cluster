# 00 — Orientation: the big picture

Everything we build serves **one idea**: split the stack into two layers so the
top layer is *identical everywhere* (home PC, Raspberry Pi, AWS).

```
   PROVISIONING  (changes per environment)          CLUSTER + WORKLOADS  (identical everywhere)
   ┌───────────────────────────────┐                ┌───────────────────────────────────────┐
   │ Hyper-V → terraform/hyperv     │                │ k3s  (real Kubernetes, tiny)            │
   │ AWS     → terraform/aws        │  ──produces──▶ │   ├─ Traefik ingress + ServiceLB (LB)   │
   │ Pi      → flash SD + cloud-init │               │   ├─ Argo CD  ──pulls this git repo──┐  │
   └───────────────────────────────┘                │   └─ your app (Kustomize manifests) ◀┘  │
                                                     └───────────────────────────────────────┘
```

- **Provisioning layer** — how a machine and Kubernetes get *created*. This is
  the only part that changes per environment (a Terraform module per cloud/host,
  or a flashed SD card for the Pi). All paths install the **same** thing: k3s.
- **Cluster + workloads layer** — what actually *runs*. Because k3s is real,
  CNCF-conformant Kubernetes, the manifests, Argo CD config, and container
  images never change between environments.

## Why k3s
[k3s](https://k3s.io) is a tiny, single-binary, fully-conformant Kubernetes. The
same k3s runs on an x86_64 Hyper-V VM, an ARM64 Raspberry Pi, and an AWS EC2
instance — which is what makes "one solution for all three" possible.

## Build order (bottom-up)
We build from the smallest thing you can run and see, upward:

1. **Docker** — containerize the app.
2. **Docker Compose** — run the whole app (frontend + backend + Postgres)
   locally. *First end-to-end win.*
3. **Terraform + k3s** — make a real cluster on Hyper-V.
4. **Kubernetes** — put the app on the cluster (raw manifests).
5. **Kustomize** — tidy the manifests into base + per-environment overlays.
6. **Argo CD + GitHub Actions** — automate delivery (GitOps + CI/CD).
7. **Pi / AWS** — prove portability.

## Why Git comes first
None of the above matters until we have somewhere to keep the work with history
and safety. So **Module 0 is Git**: initialize the repo, add a `.gitignore` that
keeps secrets and huge binaries out, make the first commit, and push to GitHub.
This repo then becomes the single source of truth that Argo CD later watches.
