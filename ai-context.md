## Project Identity

- **Name**: home-lab
- **Type**: Infrastructure-as-Code (IaC) / GitOps configuration repository
- **Languages**: YAML (Kubernetes manifests), Bash (scripts)
- **Runtime**: K3s Kubernetes (cluster), Docker Compose (compose)
- **Framework**: Kustomize (manifest templating), ArgoCD (GitOps delivery)
- **Build tool**: `kubectl kustomize` (manifest rendering)
- **Test framework**: None (infrastructure repo; validation via `manifests.sh diff`)
- **Linter**: None explicit; Renovate bot for dependency updates
- **CI/CD**: ArgoCD ApplicationSet (auto-sync from git on push)
- **Container strategy**: All services run as pre-built container images; no images built in this repo
- **Production entrypoint**: ArgoCD syncs `cluster/overlays/zahariev.com/*` directories automatically

## Purpose

Declarative configuration for a personal home lab running self-hosted services across two physical nodes. The K3s cluster (Mac Mini "Hyperion") hosts internet-facing applications with TLS, while a Docker Compose stack (Raspberry Pi "Chronos") handles internal monitoring, DNS filtering, and backups. ArgoCD watches this repo and reconciles cluster state on every git push. No upstream callers — this is the top-level infrastructure definition consumed by ArgoCD and Docker Compose.

## Architecture

**Startup flow (cluster):**
1. `bootstrap.sh` installs cert-manager and ArgoCD into K3s
2. ArgoCD applies the root ApplicationSet (`cluster/argocd/applicationset.yaml`)
3. ApplicationSet generator discovers all directories under `cluster/overlays/zahariev.com/*`
4. ArgoCD creates one Application per service directory
5. Each Application runs `kubectl kustomize` on the overlay path and applies the result
6. Services start with automated prune + self-heal sync policy

**Startup flow (compose):**
1. `docker compose --env-file .env.server up -d` in the compose/ directory
2. All services start with restart: unless-stopped

**Request flow (cluster):**
1. DNS `*.zahariev.com` resolves to 192.168.0.176 (Hyperion)
2. Router forwards ports 80/443 to Hyperion
3. Traefik ingress (bundled with K3s) terminates TLS via cert-manager certs
4. Ingress rules route by Host header to the correct ClusterIP Service
5. Service routes to Pod

```
Internet → Router:443 → Traefik Ingress → cert-manager TLS → Service → Pod
                                              ↑
                                    ClusterIssuer (letsencrypt-prod, HTTP-01)

ArgoCD ← GitHub repo (this repo)
  ↓
ApplicationSet (generator: git directories)
  ↓
Per-service Application (kustomize overlay)
  ↓
kubectl apply (ServerSideApply, prune, selfHeal)
```

**Compose monitoring flow:**
```
Containers → cAdvisor → Prometheus → Grafana
Host       → node-exporter ↗
Endpoints  → blackbox-exporter ↗
Containers → Promtail → Loki → Grafana
```

## Security Model

| Aspect | Mechanism |
|--------|-----------|
| Authentication | Keycloak (OpenID Connect) for application-level auth (invval, taskboard) |
| Authorization | Keycloak realm/client/role-based; per-app secret injection |
| TLS termination | Traefik ingress + cert-manager (Let's Encrypt prod, HTTP-01) |
| Secrets management | Kubernetes Secrets created from gitignored `.env` file via manual process; referenced as `secretKeyRef` in deployments |
| Network isolation | Compose stack internal-only (no internet exposure); cluster services exposed selectively via Ingress |
| Container security | `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, `seccompProfile: RuntimeDefault` on infrastructure pods (intel-gpu-plugin); `fsGroup` on Mattermost |
| ArgoCD | Runs in insecure mode (TLS terminated externally by Traefik); initial admin secret auto-generated |
| DNS filtering | PiHole on compose stack blocks ads network-wide |

Security is handled externally at the ingress/TLS layer. Individual applications delegate auth to Keycloak. No WAF or rate limiting configured in this repo.

## File Map

| Path | Responsibility |
|------|---------------|
| [cluster/bootstrap.sh](cluster/bootstrap.sh) | Installs cert-manager and ArgoCD; applies root ApplicationSet |
| [cluster/label-node.sh](cluster/label-node.sh) | Labels hyperion node with gpu=true and storage=true roles |
| [cluster/manifests.sh](cluster/manifests.sh) | CLI tool to dump/diff rendered kustomize manifests locally |
| [cluster/argocd/applicationset.yaml](cluster/argocd/applicationset.yaml) | Root ArgoCD ApplicationSet that auto-discovers all overlay services |
| [cluster/argocd/argocd-cmd-params-cm.yaml](cluster/argocd/argocd-cmd-params-cm.yaml) | Configures ArgoCD server in insecure mode (TLS offloaded) |
| [cluster/base/infrastructure/kustomization.yaml](cluster/base/infrastructure/kustomization.yaml) | Aggregates all infrastructure resources |
| [cluster/base/infrastructure/storage-class.yaml](cluster/base/infrastructure/storage-class.yaml) | Defines local-storage and nfs-storage StorageClasses |
| [cluster/base/infrastructure/intel-gpu-plugin.yaml](cluster/base/infrastructure/intel-gpu-plugin.yaml) | Intel GPU device plugin DaemonSet for hardware transcoding |
| [cluster/base/infrastructure/cert-manager.yaml](cluster/base/infrastructure/cert-manager.yaml) | cert-manager namespace placeholder (actual install via bootstrap.sh) |
| [cluster/base/infrastructure/cluster-issuer.yaml](cluster/base/infrastructure/cluster-issuer.yaml) | Let's Encrypt prod ClusterIssuer with HTTP-01 solver |
| [cluster/base/infrastructure/argocd-ingress.yaml](cluster/base/infrastructure/argocd-ingress.yaml) | Ingress for ArgoCD UI |
| [cluster/base/bento/](cluster/base/bento/) | PDF generation service (bentopdf-simple) |
| [cluster/base/calibre/](cluster/base/calibre/) | E-book management (Calibre web) |
| [cluster/base/changedetection/](cluster/base/changedetection/) | Web page change monitoring |
| [cluster/base/convertx/](cluster/base/convertx/) | File format converter |
| [cluster/base/dashboard/](cluster/base/dashboard/) | Static HTML dashboard (nginx + git init-container) |
| [cluster/base/filebrowser/](cluster/base/filebrowser/) | Web-based file manager |
| [cluster/base/freshrss/](cluster/base/freshrss/) | RSS feed aggregator |
| [cluster/base/georgi/](cluster/base/georgi/) | Portfolio website |
| [cluster/base/invval/](cluster/base/invval/) | Investment validation app (Keycloak-secured) |
| [cluster/base/keycloak/](cluster/base/keycloak/) | Identity provider (Keycloak + PostgreSQL) |
| [cluster/base/mattermost/](cluster/base/mattermost/) | Team chat (Mattermost + PostgreSQL) |
| [cluster/base/mealie/](cluster/base/mealie/) | Recipe manager (Mealie + PostgreSQL) |
| [cluster/base/monitoring/](cluster/base/monitoring/) | Full observability stack (Prometheus, Grafana, Loki, Promtail, Node-exporter, Kube-state-metrics) |
| [cluster/base/plex/](cluster/base/plex/) | Media server with Intel GPU transcoding |
| [cluster/base/qbittorrent/](cluster/base/qbittorrent/) | BitTorrent client |
| [cluster/base/taskboard/](cluster/base/taskboard/) | Task management app (Keycloak-secured) |
| [cluster/base/workers/](cluster/base/workers/) | Background workers (DLP + Handbrake with GPU) |
| [cluster/base/youtrack/](cluster/base/youtrack/) | Issue tracker (JetBrains YouTrack) |
| [cluster/overlays/zahariev.com/](cluster/overlays/zahariev.com/) | Production overlay: patches hostnames to *.zahariev.com, sets PV paths and node affinity |
| [compose/docker-compose.yml](compose/docker-compose.yml) | Defines all compose services (monitoring, DNS, file browser) |
| [compose/blackbox-exporter/blackbox.yml](compose/blackbox-exporter/blackbox.yml) | HTTP probe configuration for blackbox-exporter |
| [compose/grafana/](compose/grafana/) | Grafana dashboards and provisioning configs |
| [compose/loki/loki-config.yaml](compose/loki/loki-config.yaml) | Loki storage and retention config |
| [compose/loki/promtail-config.yaml](compose/loki/promtail-config.yaml) | Promtail log collection config |
| [compose/prometheus/prometheus.yml](compose/prometheus/prometheus.yml) | Prometheus scrape targets |
| [compose/scripts/backup.sh](compose/scripts/backup.sh) | Remote backup via rsync with retry and rotation |
| [compose/scripts/maintenance.sh](compose/scripts/maintenance.sh) | Monthly auto-update: apt, git pull, docker pull, restart |
| [compose/scripts/timestamp.sh](compose/scripts/timestamp.sh) | Prepends timestamps to piped log lines |
| [compose/dashboard/index.html](compose/dashboard/index.html) | Static dashboard landing page |

## Test Map

No test framework. Validation approaches:

| Tool | Purpose |
|------|---------|
| `cluster/manifests.sh dump` | Renders all kustomize overlays to /tmp for inspection |
| `cluster/manifests.sh diff` | Compares current manifests against previous dump |
| ArgoCD sync status | Runtime validation — failed syncs surface misconfiguration |

## Configuration Files

| File | Purpose |
|------|---------|
| [renovate.json](renovate.json) | Renovate bot config: daily schedule, auto-merge, Kubernetes manifest scanning |
| [.gitignore](.gitignore) | Ignores .env, .server files, .DS_Store |
| [cluster/argocd/applicationset.yaml](cluster/argocd/applicationset.yaml) | Root GitOps generator for all services |
| [cluster/argocd/argocd-cmd-params-cm.yaml](cluster/argocd/argocd-cmd-params-cm.yaml) | ArgoCD server insecure mode toggle |
| [cluster/overlays/zahariev.com/.env](cluster/overlays/zahariev.com/.env) | Secrets file (gitignored) for Kubernetes secret generation |
| [compose/.env.server](compose/.env.server) | Compose environment variables (gitignored) |
| [compose/blackbox-exporter/blackbox.yml](compose/blackbox-exporter/blackbox.yml) | HTTP probe modules |
| [compose/grafana/provisioning-datasources.yaml](compose/grafana/provisioning-datasources.yaml) | Grafana datasource definitions |
| [compose/grafana/provisioning-dashboards.yaml](compose/grafana/provisioning-dashboards.yaml) | Grafana dashboard provisioning |
| [compose/loki/loki-config.yaml](compose/loki/loki-config.yaml) | Loki server configuration |
| [compose/loki/promtail-config.yaml](compose/loki/promtail-config.yaml) | Promtail scrape configuration |
| [compose/prometheus/prometheus.yml](compose/prometheus/prometheus.yml) | Prometheus scrape jobs and targets |

## Dependencies

### Container Images — Cluster

| Image | Purpose |
|-------|---------|
| bentopdfteam/bentopdf-simple:2.8.5 | PDF generation |
| linuxserver/calibre:9.9.0 | E-book management |
| dgtlmoon/changedetection.io:0.55.7 | Web change detection |
| c4illin/convertx:v0.17.0 | File conversion |
| nginx:alpine-slim | Static dashboard |
| filebrowser/filebrowser:v2.63.14 | File browser |
| linuxserver/freshrss:1.29.1 | RSS reader |
| georgizahariev/portfolio:0.0.6 | Portfolio site |
| dzahariev/invval:4.1 | Investment validator |
| keycloak/keycloak:26.6.3 | Identity provider |
| postgres:18.4-alpine3.22 | PostgreSQL (Keycloak, Mattermost, Mealie) |
| mattermost/mattermost-team-edition:11.8.0 | Team chat |
| ghcr.io/mealie-recipes/mealie:v3.19.2 | Recipe manager |
| prom/prometheus:v3.12.0 | Metrics |
| grafana/grafana:13.0.2 | Dashboards |
| grafana/loki:3.7.2 | Log aggregation |
| grafana/promtail:3.6.11 | Log shipping |
| prom/node-exporter:v1.11.1 | Host metrics |
| registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.19.0 | K8s metrics |
| plexinc/pms-docker:1.43.0.10492-121068a07 | Media server |
| linuxserver/qbittorrent:5.2.1 | Torrent client |
| dzahariev/taskboard:1.25 | Task board |
| dzahariev/dlp-worker:1.7 | Download worker |
| dzahariev/handbrake-worker:3.6 | Video transcoding worker |
| jetbrains/youtrack:2026.1.13757 | Issue tracker |
| intel/intel-gpu-plugin:0.36.0 | GPU device plugin |

### Container Images — Compose

| Image | Purpose |
|-------|---------|
| nginx:alpine-slim | Static dashboard |
| gcr.io/cadvisor/cadvisor:v0.55.1 | Container metrics |
| prom/node-exporter:v1.11.1 | Host metrics |
| prom/blackbox-exporter:v0.28.0 | Endpoint probes |
| prom/prometheus:v3.12.0 | Metrics aggregation |
| grafana/loki:3.7.2 | Log aggregation |
| grafana/promtail:3.6.11 | Log shipping |
| grafana/grafana:13.0.2 | Dashboards |
| filebrowser/filebrowser:v2.63.14 | File browser |
| pihole/pihole:2026.05.0 | DNS ad-blocking |

### Infrastructure Dependencies

| Component | Purpose |
|-----------|---------|
| cert-manager v1.20.2 | TLS certificate lifecycle (installed via bootstrap.sh) |
| ArgoCD v3.4.3 | GitOps continuous delivery (installed via bootstrap.sh) |
| Traefik | Ingress controller (bundled with K3s) |
| K3s | Lightweight Kubernetes distribution |
| Renovate | Automated dependency updates |

## Environment Variables

### Cluster (from overlay .env — secret format: `secret-name/key:value`)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| calibre-secrets/admin-password | Yes | — | Calibre admin password |
| keycloak-db-secrets/db-name | Yes | — | Keycloak PostgreSQL database name |
| keycloak-db-secrets/db-user | Yes | — | Keycloak PostgreSQL username |
| keycloak-db-secrets/db-password | Yes | — | Keycloak PostgreSQL password |
| keycloak-db-secrets/db-port | Yes | — | Keycloak PostgreSQL port |
| keycloak-db-secrets/admin-user | Yes | — | Keycloak admin username |
| keycloak-db-secrets/admin-password | Yes | — | Keycloak admin password |
| mattermost-db-secrets/datasource | Yes | — | Mattermost PostgreSQL connection string |
| mattermost-db-secrets/db-name | Yes | — | Mattermost DB name |
| mattermost-db-secrets/db-user | Yes | — | Mattermost DB user |
| mattermost-db-secrets/db-password | Yes | — | Mattermost DB password |
| mattermost-db-secrets/db-port | Yes | — | Mattermost DB port |
| mealie-db-secrets/db-name | Yes | — | Mealie DB name |
| mealie-db-secrets/db-user | Yes | — | Mealie DB user |
| mealie-db-secrets/db-password | Yes | — | Mealie DB password |
| mealie-db-secrets/db-port | Yes | — | Mealie DB port |
| invval-secrets/realm | Yes | — | Keycloak realm for invval |
| invval-secrets/client-id | Yes | — | Keycloak client ID for invval |
| invval-secrets/client-secret | Yes | — | Keycloak client secret for invval |
| taskboard-secrets/AUTH_REALM | Yes | — | Keycloak realm for taskboard |
| taskboard-secrets/AUTH_CLIENT_ID | Yes | — | Keycloak client ID for taskboard |
| taskboard-secrets/AUTH_CLIENT_SECRET | Yes | — | Keycloak client secret for taskboard |
| grafana-secrets/admin-password | Yes | — | Grafana admin password |
| plex-secrets/claim | Yes | — | Plex claim token |

### Compose (.env.server)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| MONITORING_DATA_DIR | Yes | — | Base path for persistent monitoring data |
| DATA_DIR | Yes | — | Base path for application data |
| FS_DIR | Yes | — | Filesystem root exposed to file browser |
| ROOT_IP | Yes | — | Host IP for PiHole DNS binding |
| PIHOLE_PASSWORD | Yes | — | PiHole web UI password |
| GF_SECURITY_ADMIN_USER | Yes | — | Grafana admin username |
| GF_SECURITY_ADMIN_PASSWORD | Yes | — | Grafana admin password |

### Compose (backup.sh cron environment)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| SSHPASS | Yes | — | Password for remote SSH (used by sshpass) |
| REMOTE_USER | Yes | — | SSH username for backup source |
| REMOTE_HOST | Yes | — | Hostname of backup source |
| REMOTE_BASE | Yes | — | Remote base directory containing lastFullArchive |
| LOCAL_BASE | Yes | — | Local directory for storing backups |

## API Surface

This repo does not expose APIs. It deploys services that expose the following ingress endpoints:

| Service | Hostname | Port | Description |
|---------|----------|------|-------------|
| ArgoCD | argocd.zahariev.com | 443 | GitOps UI |
| Bento | bento.zahariev.com | 443 | PDF generation |
| Calibre | calibre.zahariev.com | 443 | E-book management |
| Changedetection | changedetection.zahariev.com | 443 | Web monitoring |
| ConvertX | convertx.zahariev.com | 443 | File conversion |
| Dashboard | zahariev.com | 443 | Landing page |
| Filebrowser | filebrowser.zahariev.com | 443 | File management |
| FreshRSS | freshrss.zahariev.com | 443 | RSS reader |
| Georgi | georgi.zahariev.com | 443 | Portfolio |
| Grafana | grafana.zahariev.com | 443 | Metrics dashboards |
| Invval | invval.zahariev.com | 443 | Investment validator |
| Keycloak | auth.zahariev.com | 443 | Identity provider |
| Mattermost | mattermost.zahariev.com | 443 | Team chat |
| Mealie | mealie.zahariev.com | 443 | Recipes |
| Plex | plex.zahariev.com | 443 | Media server |
| Prometheus | prometheus.zahariev.com | 443 | Metrics |
| Qbittorrent | qbittorrent.zahariev.com | 443 | Torrent client |
| Taskboard | taskboard.zahariev.com | 443 | Task management |
| YouTrack | youtrack.zahariev.com | 443 | Issue tracker |

## Dev Commands

```bash
# Render all kustomize manifests to /tmp/home-server
./cluster/manifests.sh dump zahariev.com

# Diff current manifests against last dump
./cluster/manifests.sh diff zahariev.com

# Clear rendered manifests
./cluster/manifests.sh clear

# Bootstrap cluster (one-time)
./cluster/bootstrap.sh

# Label node (one-time)
./cluster/label-node.sh

# Start compose stack
cd compose && docker compose --env-file .env.server up -d

# Stop compose stack
cd compose && docker compose --env-file .env.server down

# Validate a single service's kustomize output
kubectl kustomize cluster/overlays/zahariev.com/<service-name>

# Run maintenance (compose host)
./compose/scripts/maintenance.sh

# Run backup (compose host)
SSHPASS="x" REMOTE_USER="x" REMOTE_HOST="x" REMOTE_BASE="/x" LOCAL_BASE="/x" ./compose/scripts/backup.sh
```

## Testing Patterns

- **Framework**: None (infrastructure repo)
- **Manifest validation**: `manifests.sh dump` renders all overlays; non-zero exit on kustomize errors
- **Diff review**: `manifests.sh diff` shows what changed since last dump (for pre-push review)
- **Runtime validation**: ArgoCD sync status; failed syncs indicate broken manifests
- **Dependency updates**: Renovate bot creates PRs for image version bumps; `ignoreTests: true` (no CI tests)

## Deployment Model

| Component | Target | Hardware | Scaling |
|-----------|--------|----------|---------|
| Cluster services | K3s on Mac Mini 2012 (Hyperion) | 16GB RAM, 512GB SSD + 4TB SSD, Intel iGPU | Single node, 1 replica per service (Recreate strategy) |
| Compose services | Docker Compose on Raspberry Pi 4 (Chronos) | 8GB RAM, 512GB SSD + 1TB SSD | Single host, 1 container per service |

- **GitOps delivery**: Push to `main` → ArgoCD detects change → applies manifests (prune + self-heal)
- **Storage**: Local PVs with node affinity (hyperion); NFS-backed PVs for shared data
- **GPU workloads**: Plex and Handbrake worker pinned to gpu=true nodes via nodeSelector + resource requests
- **Database pattern**: PostgreSQL sidecar per stateful service (keycloakdb, mattermostdb, mealiedb)
- **No horizontal scaling**: All services run as single replicas with Recreate deployment strategy

## Non-Obvious Design Decisions

- **ArgoCD in insecure mode**: `server.insecure: "true"` in argocd-cmd-params-cm. TLS is terminated by Traefik ingress, not ArgoCD itself. Do not "fix" by enabling ArgoCD TLS.
- **Base manifests use example.com hostnames**: All ingress rules in `cluster/base/` use `*.example.com`. The overlay patches these to `*.zahariev.com`. Do not change base hostnames directly.
- **Traefik is the ingress class, not nginx**: Despite K3s docs mentioning nginx, this cluster uses `ingressClassName: traefik` (K3s default). Do not add nginx ingress controller.
- **ServerSideApply enabled globally**: The ApplicationSet uses `ServerSideApply=true` sync option. This avoids field ownership conflicts but means `kubectl apply` from CLI may conflict.
- **Dashboard fetches content via git init-container**: The dashboard pod uses a git sparse-checkout init container to pull `cluster/base/dashboard/www/` content at startup. Content changes require pod restart (handled by ArgoCD).
- **No secrets in git**: Secrets are managed via a manual `.env` file + undocumented `secrets.sh` script. The `.env` file format is `secret-name/key:value`. There is no external secrets operator.
- **Compose uses atomic swap for updates**: `maintenance.sh` renames compose files before stopping containers to minimize downtime — old file used for `down`, new file used for `up`.
- **Backup uses .progressing/.completed state files**: The backup script tracks sync state via directory suffixes, not a database. Multiple parallel runs are safe (checks for .completed first).
- **cert-manager namespace in base is a placeholder**: The actual cert-manager install happens in `bootstrap.sh` via remote URL. The namespace YAML just ensures the namespace exists for ArgoCD sync.
- **PV sizes are oversized (500Gi)**: Local PVs use 500Gi even for small databases. This is because local-path provisioner doesn't enforce capacity — the size is nominal.
- **Single overlay pattern**: Only one overlay exists (`zahariev.com`). The structure supports multiple but currently everything targets one environment.

## Quick Grep Targets

- `letsencrypt-prod` — ClusterIssuer name for TLS certs
- `traefik` — ingress class used across all ingresses
- `cert-manager.io/cluster-issuer` — annotation triggering cert provisioning
- `nfs-storage` / `local-storage` — StorageClass names
- `node-role.kubernetes.io/gpu` — node selector label for GPU workloads
- `node-role.kubernetes.io/storage` — node selector label for storage workloads
- `hyperion` — the single K3s node name
- `zahariev.com` — production domain (overlay patches)
- `example.com` — base template domain (do not deploy directly)
- `argocd-cmd-params-cm` — ArgoCD server config
- `home-lab` — ApplicationSet name
- `dzahariev/home-lab.git` — repo URL in ApplicationSet
- `cluster/overlays/zahariev.com/*` — ArgoCD generator path
- `secretKeyRef` — pattern for secret injection into pods
- `Recreate` — deployment strategy used by all services
- `.env.server` — compose environment file
- `lastFullArchive` — backup state file on remote host
- `SSHPASS` — backup script auth variable
- `keycloak-db-secrets` — shared secret name for Keycloak DB
- `taskboard-secrets` — secret name for taskboard auth
- `invval-secrets` — secret name for invval auth
- `grafana-secrets` — secret name for Grafana admin
- `plex-secrets` — secret name for Plex claim
- `gpu.intel.com/i915` — GPU resource request key
- `ServerSideApply=true` — sync option in ApplicationSet
- `CreateNamespace=true` — sync option enabling namespace auto-creation
- `bootstrap.sh` — one-time cluster setup script
- `manifests.sh` — local manifest validation tool
- `maintenance.sh` — compose auto-update script
- `backup.sh` — remote backup script
