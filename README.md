# hestia

Personal infrastructure-as-code: a single-node Talos Linux Kubernetes cluster, managed
end-to-end from this repo via HCP Terraform (org `lover`, workspace `hestia`). See
`CLAUDE.md` for the core rule: **the repo is the canonical state of the infrastructure.**

## Layout

```
hestia/               Terraform root module (the only active project)
  <service>.tf        grouped by service/domain — see CLAUDE.md for the prefix scheme
  <app>/              app source built by GitHub Actions (vin-moe, monke-academy, vinnel-cloud)
  helm-values/        values for Helm-installed platform charts
  manifests/          templated raw manifests (cluster issuers, VPAs)
  talos/              Talos machine config patch
love/                 love CLI source (binary is released via Vinnelle/love, not committed)
```

## How changes deploy

- **Infrastructure** (`hestia/**/*.tf` and everything they template): push to `prd` →
  TFC plans and applies. Feature branches get speculative plans only.
- **Sites** (`hestia/<app>/site/**`, `hestia/vinnel-cloud/dashboard/**`): push to `prd` →
  GitHub Actions builds and pushes the image, records BuildKit's immutable digest in
  `hestia/images.json`, then rolls out that same digest. Terraform reconciles the
  committed manifest, so replacement and disaster recovery reproduce the reviewed image.
- **Version bumps**: Renovate PRs, automerged **except majors** — provider and Helm-chart
  majors wait for a human. Image tags pinned in `.tf` files are reconciled by Terraform
  (there is no `ignore_changes` on them), so a merged bump rolls the pod.

## Bootstrap order (fresh cluster / disaster recovery)

The `grafana`, `harbor` and `netbird` providers point at services this same workspace
creates, so a from-scratch apply needs staged targets:

1. Node up with Talos installed (out of band), `node_ip` reachable.
2. `terraform apply -target=talos_machine_bootstrap.this` — machine secrets, config, bootstrap.
3. `terraform apply -target=helm_release.ingress_nginx -target=helm_release.cert_manager`
   then the cluster issuers and `kubernetes_secret_v1.cloudflare_api_token`.
4. `terraform apply -target=helm_release.harbor` — wait for `registry.vinnel.cloud` to answer.
5. `terraform apply -target=kubernetes_deployment_v1.authelia` (+ its secrets/PVC/ingress) —
   the netbird OIDC clients and both dashboards authenticate against it.
6. `terraform apply -target=kubernetes_deployment_v1.netbird_management` (+ signal, relay,
   dashboard, ingresses) — wait for `proxy.vinnel.cloud/api` to answer, mint a service-user
   PAT, set `netbird_api_token` in TFC.
7. Full `terraform apply`. First-boot races: the `netbird_peer` data sources (adguard, momus)
   read peers that only exist after those pods register — re-run the apply if they 404.
8. Site images: before the first full apply of this revision, trigger each `*-build` workflow
   (`workflow_dispatch`) to replace the bootstrap tags in `images.json` with immutable
   image digests; then let the resulting Terraform VCS run apply them.
9. Momus: the deployment references the immutable digest recorded in `images.json` by
   `momus-build.yml`. On a fresh Harbor, trigger that workflow (`workflow_dispatch`) before the
   full apply so the registry contains the pinned image; the momus pod cannot pull until it does.

## Backups & restore

- `pv-backup` CronJob (03:00 UTC, `backup` namespace) takes a restic snapshot of
  `/opt/local-path-provisioner` (every local-path PV) into the Bunny Storage repository
  `s3://talos/restic`, keeping 7 daily snapshots. Snapshots are encrypted client-side with
  `backup_encryption_password` (TFC variable — **keep an offline copy**, without it the
  backups are unreadable). Failures trip the `BackupJobFailed` Grafana alert.
- **Caveat**: it is a file-level copy of live data — sqlite DBs (Authelia, netbird,
  dashboard) may not be crash-consistent. Run `PRAGMA integrity_check` after restoring one.
- **Restore**: scale the workload to 0, then from any pod/machine with the repo password:
  `restic -r s3:https://de-s3.storage.bunnycdn.com/talos/restic restore latest --target /tmp/restore`
  (add `--path /data/<pv-dir>` to cherry-pick one PV), copy the files back into the PV
  directory under `/opt/local-path-provisioner/` on the node (`talosctl` or a debug pod),
  scale up. `restic snapshots` lists restore points.
- **Not on any PV — lives only in TFC state**: Talos machine secrets, every
  `random_password`, ACME account keys. Losing the workspace loses the
  cluster. Periodically export state (`terraform state pull > state-$(date +%F).json`) and
  save `terraform output -raw talosconfig` / `kubeconfig` somewhere offline.

## Operational credentials

All sensitive values are TFC workspace variables (see `variables.tf` descriptions).
Retrieve generated ones with `terraform output -raw <name>`: `kubeconfig`, `talosconfig`,
`ci_kubeconfig` (GitHub `HESTIA_KUBECONFIG` secret), `harbor_ci_username`/`_password`
(GitHub `HARBOR_USERNAME`/`HARBOR_PASSWORD` secrets), `authelia_admin_password`,
`adguard_admin_password`, `momus_ssh_address`.

## Alerting

Alert rules are provisioned in `observability-alerting.tf` (backup failures, node
NotReady, PVCs >85%, certificates <14d from expiry, degraded workloads). **Delivery is
not wired up**: point Grafana's default notification policy at a real contact point
(SMTP/webhook) to get paged. A single-node cluster cannot report its own death — pair
this with an external uptime check (e.g. on `vin.moe`).

## In-cluster deploy runner (optional, for closing 6443)

`platform-ci.tf` can stand up a self-hosted GitHub Actions runner in the `ci`
namespace so the deploy step reaches the API server internally instead of over the
public 6443 endpoint. It's gated on `github_runner_token` — unset, nothing is created.

Rollout is two phases so a broken runner can never strand deploys:

1. **Stand it up.** Mint a fine-grained PAT on `Vinnelle/hestia` with
   `Administration: read and write`, set it as the `github_runner_token` TFC
   variable, apply. Confirm the runner appears under repo → Settings → Actions →
   Runners, idle, labelled `hestia-incluster`.
2. **Cut over.** Only then split `site-deploy.yml` into a `build-push` job
   (`ubuntu-latest`) and a `deploy` job (`runs-on: hestia-incluster`). The deploy
   job installs kubectl and runs `set image`/`rollout status` using the pod's
   ServiceAccount (bound to the existing `ci-deployer` Role) — no kubeconfig, so
   `HESTIA_KUBECONFIG` can be deleted from GitHub afterwards. Builds stay on
   GitHub-hosted runners, so the pod needs no Docker daemon.

Change detection is unaffected: GitHub's control plane still evaluates the `paths:`
filters and queues jobs; the self-hosted runner only executes the deploy job. The
runner is persistent (one at a time); flip to `EPHEMERAL=true` env for per-job
isolation at the cost of re-registration churn. Only after a deploy is confirmed
working through it should 6443 be narrowed in `talos/firewall.yaml.tftpl`.

## Node firewall

`talos/firewall.yaml.tftpl` applies a default-block ingress firewall (hot-applied by
Talos, no reboot). Open: 80/443 from Cloudflare's edge ranges only (every public
hostname is proxied), 6443 and 50000 to the world (GitHub Actions/TFC have no pinnable
egress IPs; both ports are mTLS/token-gated — and 50000 is the recovery path for the
firewall itself), kubelet/metrics ports from the pod CIDR, DHCP client replies. ICMP
and established/outbound traffic are always allowed by Talos.

If something breaks after a firewall change: the sites 522ing means a Cloudflare range
problem, mesh peers stuck "connecting" fall back to the relay — but `kubectl`,
`talosctl` and TFC keep working by design, so fix or revert the patch and re-apply.
Worst case, the provider's out-of-band console is the escape hatch. Cloudflare's
ranges (https://www.cloudflare.com/ips) change rarely; re-check them if visitors
report 522s after a Cloudflare announcement.

## Known gaps / deferred hardening (deliberate)

- **6443 and 50000 remain world-reachable** (see Node firewall above) — accepted so CI,
  TFC and disaster recovery keep working; both are certificate/token-authenticated.
- **etcd secrets encryption at rest** (Talos `secretboxEncryptionSecret`) is not enabled.
  Defense-in-depth on top of LUKS2 full-disk encryption; enabling it on a live single-node
  cluster restarts the API server, so do it in a maintenance window, not from a drive-by PR.
- **GitHub Actions are pinned to major tags**, not commit SHAs. Pin to SHAs when you can
  verify them (this repo's CI secrets — Harbor + kubeconfig — are what a compromised
  action tag would reach).
- **promtail is EOL** (replaced by Grafana Alloy); it still works but won't get updates.
- **Grafana image** is `:latest` until you pin the running version — see the TODO in
  `observability-grafana.tf` (never pin below the running version: no downgrade migrations).
- **Authelia OIDC CORS** derives allowed origins from client redirect URIs
  (`allowed_origins_from_client_redirect_uris`) — adding a redirect URI widens CORS too.
- The dashboard's session cookie is stateless (HMAC, 24h): logout clears the cookie but
  can't revoke a stolen one. Fine for the single-admin analytics page; don't reuse the
  pattern for anything multi-user.
