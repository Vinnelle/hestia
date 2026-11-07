# hestia

[![Terraform](https://img.shields.io/badge/Terraform-1.10+-844FBA?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Talos Linux](https://img.shields.io/badge/Talos_Linux-v1.13+-326CE5?logo=kubernetes&logoColor=white)](https://www.talos.dev/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.37+-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Cilium](https://img.shields.io/badge/Cilium-eBPF_CNI-F05032?logo=cilium&logoColor=white)](https://cilium.io/)
[![WireGuard](https://img.shields.io/badge/WireGuard-Tunnel-88171A?logo=wireguard&logoColor=white)](https://www.wireguard.com/)
[![Cloudflare](https://img.shields.io/badge/Cloudflare-DNS_%26_Edge-F38020?logo=cloudflare&logoColor=white)](https://www.cloudflare.com/)

Declarative personal infrastructure-as-code: a single-node, hardened **Talos Linux** Kubernetes cluster running in a Proxmox VE host at home, fronted by a **RAM-only WireGuard relay** in Switzerland, and managed end-to-end with **Terraform**.

State is stored in **HCP Terraform** (local execution mode); secrets are encrypted with **SOPS** using post-quantum **age** keys.

> **Core Rule:** The repository is the canonical state of the infrastructure. No manual changes, no SSH or shells on the node, no drift.

---

## Architecture Overview

Traffic flows from the public internet through a stateless, RAM-only Alpine relay in Switzerland before tunneling privately over WireGuard to the home cluster:

```mermaid
flowchart TD
    Visitor([Public Visitor]) -->|HTTPS / SSH / Game Ports| CF[Cloudflare DNS]
    CF -->|Public Traffic| Relay["Swiss Cloud Relay (Infomaniak)<br/>• Alpine Linux running 100% in RAM<br/>• Locked root, no syslog, no disk writes<br/>• nftables DNAT & masquerading"]

    subgraph Homelab ["Homelab Hardware (Ryzen 7 7800X3D / 32GB RAM / NVMe)"]
        subgraph PVE ["Proxmox VE 9 Host"]
            HostFW["Host Firewall (LAN only)"]
            ZFS["Encrypted ZFS Pool (ZFS on LUKS)"]
            GPU["NVIDIA GeForce RTX 4070 Ti"]
        end

        subgraph VM ["Single-Node Talos Linux VM"]
            TPM["vTPM 2.0 Sealed Storage (LUKS2)"]
            Cilium["Cilium CNI (eBPF default-deny NetworkPolicies)"]
            Ingress["ingress-nginx (Chainguard hardened fork)"]
            
            subgraph Workloads ["Cluster Workloads"]
                Sites["Sites<br/>(vin.moe, vinnel.cloud)"]
                Apps["Apps<br/>(GitLab, Nextcloud, AdGuard, Matrix)"]
                LLM["Local AI<br/>(llama.cpp CUDA server on RTX 4070 Ti)"]
                Storage["Storage<br/>(Local Path & SeaweedFS S3)"]
                Auth["Identity<br/>(Authelia OIDC + Auth Portal)"]
                Obs["Observability<br/>(Grafana, VictoriaMetrics, Better Stack)"]
            end
        end
    end

    Relay <===>|WireGuard Tunnel (Outbound Dial from Node)| VM
    GPU -.->|PCIe Passthrough| LLM
    VM --> Cilium --> Ingress --> Sites & Apps & LLM & Auth & Obs
```

---

## Key Pillars

### 1. Zero-Trust Ingress & The RAM-Only Relay
- **Stateless Cloud Relay:** An Alpine Linux instance hosted on Infomaniak Public Cloud in Switzerland running entirely in RAM from a custom-built virt ISO. The root account is locked at boot, syslog is disabled, and kernel module loading is disabled after network initialization.
- **Privacy by Masquerade:** Traffic forwarding uses `nftables` DNAT and masquerades over an outbound WireGuard tunnel dialed from the home node. External visitor IP addresses never reach home cluster logs or ingress controllers.
- **Zero Inbound Ports at Home:** The home firewall allows no inbound connections from the WAN. The cluster dials out to maintain the WireGuard tunnel.

### 2. Immutable, Shell-Free Node (Talos Linux)
- **Hardened Kubernetes:** Single-node control plane and workload scheduling managed declaratively via Talos mTLS APIs. There is no SSH daemon, no shell, and no package manager.
- **Secure Boot & vTPM Sealing:** Booted with UEFI Secure Boot. Ephemeral partitions, state directories, and persistent disks are encrypted with LUKS2 sealed against the virtual TPM.
- **Custom Schematic:** Deployed via Talos Image Factory schematics pinning extensions:
  - `siderolabs/nvidia-container-toolkit-lts`
  - `siderolabs/nvidia-open-gpu-kernel-modules-lts`
  - `siderolabs/qemu-guest-agent`
- **Predictable Disk Pinning:** Drives are matched and mounted strictly by device serial numbers, immune to bus reordering.

### 3. eBPF Networking & Isolation (Cilium)
- **Default-Deny Everywhere:** Every application namespace starts with a strict default-deny network policy. Permitted ingress and egress rules are explicitly defined in Terraform.
- **Host Identity Protection:** Cluster-wide rules enforce that relayed traffic can only reach the ingress controller, never direct pod or host identities.
- **Hubble Observability:** eBPF flow data and network map accessible behind Authelia single sign-on.

### 4. Hardware-Accelerated Local AI
- **PCIe Passthrough:** Dedicated NVIDIA GeForce RTX 4070 Ti passed through to the Talos VM.
- **`llama.cpp` CUDA Server:** Runs non-root, read-only root filesystems with dropped Linux capabilities to serve local LLMs for internal automations and chat bots.
- **Metrics Scraping:** Scraped continuously via VictoriaMetrics `VMPodScrape` CRDs into Grafana.

---

## Repository Structure

```
.
├── apps.tf                  # Module calls for cluster applications
├── apps/                    # Application definitions
│   ├── adguard/             # Split-horizon DNS sinkhole & DoH
│   ├── admin/               # Custom Go admin dashboard (vinnel.cloud)
│   ├── automations/         # Go automated reporting service (digest emails)
│   ├── gitlab/              # GitLab CE self-hosted forge & registry
│   ├── llm/                 # llama.cpp server with CUDA acceleration
│   ├── matrix/              # Synapse Matrix homeserver
│   ├── miniflux/            # Minimalist RSS reader
│   ├── nextcloud/           # File sync & collaboration suite
│   ├── searxng/             # Privacy-respecting metasearch engine
│   └── seaweedfs/           # Local S3-compatible object storage
├── bots.tf                  # Local AI bot services
├── bots/gemma/              # Gemma AI assistant integrated with SearXNG
├── identity.tf              # SSO & authentication infrastructure
├── identity/
│   ├── authelia/            # Authelia OIDC & ForwardAuth provider
│   └── auth-portal/         # Custom auth portal UI
├── observability.tf         # Monitoring and alerting definitions
├── observability/
│   ├── betterstack/         # Better Stack heartbeat & status integrations
│   └── grafana/             # VictoriaMetrics, Grafana, custom k8s sidecars
├── platform.tf              # Core Kubernetes & platform definitions
├── platform/
│   ├── cni/                 # Cilium CNI & Hubble configuration
│   ├── core/                # cert-manager, cluster issuers, namespaces
│   ├── ingress-nginx/       # Hardened Chainguard ingress-nginx controller
│   ├── local-path-provisioner/ # Host SSD persistent storage
│   ├── proxmox/             # Proxmox VE VM, storage, & PBS backup configuration
│   ├── relay/               # Alpine RAM-only relay image build & OpenStack setup
│   └── vpa/                 # Vertical Pod Autoscalers
├── proxy.tf                 # Overlay mesh definitions
├── proxy/netbird/           # NetBird WireGuard mesh coordinator & clients
├── sites.tf                 # Static web properties
├── sites/
│   ├── static-site/         # Shared static site deployment module
│   ├── vin-moe/             # vin.moe web service module
│   └── vinnel-cloud/        # vinnel.cloud web service module
├── talos.tf                 # Talos machine configs, patches, & bootstrapping
├── talos/                   # Talos configuration patches (firewall, network, GPU, storage)
├── tests/                   # terraform test suites (network policies, images, schemas)
├── variables.tf             # Input variables
├── locals.tf                # Computed values and image digest mappings
├── providers.tf             # Provider definitions (Talos, Proxmox, K8s, Helm, Cloudflare)
├── versions.tf              # Pinned provider and Terraform versions
└── .gitlab-ci/              # CI/CD pipeline definitions and helper scripts
```

---

## Homelab Hardware Specification

| Component | Specification | Details |
| :--- | :--- | :--- |
| **CPU** | AMD Ryzen 7 7800X3D | 8 cores, 16 threads, TSME memory encryption enabled |
| **RAM** | 32 GB DDR5 | Host ARC capped to 2 GiB; 22 GiB allocated to the Talos VM |
| **GPU** | NVIDIA GeForce RTX 4070 Ti 12GB | PCIe passthrough for local CUDA inference |
| **Host Disk** | 250 GB Samsung 870 EVO (SATA) | Proxmox VE 9 OS on ZFS RAID0 |
| **Data Disk** | 2 TB Samsung 990 PRO (NVMe) | High-speed ZFS storage pool for VM root & bulk volumes |
| **Hypervisor** | Proxmox VE 9 | Managed via Terraform with API tokens |
| **Backups** | Proxmox Backup Server (PBS) | Nightly client-side encrypted backups synced offsite |

---

## Deployment & CI/CD Lifecycle

Changes follow a strict promotion pipeline executed through self-hosted GitLab CI runners:

1. **Branch Workflow:** All changes land on `pre`. Merge requests trigger validation suites:
   - Linting, secret scans (`gitleaks`), container security scans (`trivy`).
   - Native integration tests via `terraform test` across network policies and image schemas.
   - Speculative `terraform plan` (read-only with `-lock=false`).
2. **Merge Gate:** When tests pass, the MR merges automatically into `prd`.
3. **Automated Apply:** GitLab CI runs `terraform apply` from inside the cluster using CI's age key to decrypt `secrets.sops.json`.
4. **Digest Pinning:** Container images built in CI are pushed to the internal registry and recorded into `*-images.json` files by immutable digest (`@sha256:...`).
5. **Renovate:** Automated 15-minute dependency scans submit automated MRs for container base images, Helm charts, and Terraform providers.

---

## Testing & Verification

Unit and integration tests are written using the native Terraform test framework:

```sh
# Run the test suite
terraform test

# Execute specific test modules
terraform test -filter=tests/network_policy/unit.tftest.hcl
terraform test -filter=tests/images_json/unit.tftest.hcl
```

---

## Disaster Recovery

1. **Workspace:** Ensure HCP Terraform execution mode is set to *Local* for state storage.
2. **Secrets:** Restore the post-quantum age secret key to `~/.config/sops/age/keys.txt` and prepare `secrets.sops.json`.
3. **Host & Relay:** Provision Proxmox VE host and upload the Swiss relay image via `platform/relay/image/build.sh`.
4. **Bootstrap Talos:** Apply machine configuration over mTLS via `talos.tf` and run `talosctl bootstrap`.
5. **Apply Infrastructure:** Apply the root Terraform module to deploy Cilium, ingress controllers, storage classes, and services.

---

## License

This project is licensed under the [MIT License](LICENSE) (or original author terms where specified).
