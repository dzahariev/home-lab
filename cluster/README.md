# cluster
K8s cluster part of the lab

## Hardware 

| Node | Name | RAM | OS Disk | Storage |
|---|---|---|---|---|
| Mac Mini 2018 | Atlas | 16 GB | 256 GB SSD | 4 TB SSD (Local), 1 TB SSD (NFS) |
| Mac Mini 2012 | Hyperion | 16 GB | 512 GB SSD | — |

## OS
Ubuntu 24.04

## Visibility
Exposes services to internet

## Responsibilities
K3s based kubernetes cluster with 2 nodes that runs on bare metal.

## Networking

### DNS

Configure a wildcard DNS record pointing to the Mac Mini 2018 (atlas) IP address:

```
*.zahariev.com    A    192.168.0.55
zahariev.com      A    192.168.0.55
```

This covers all service subdomains and the bare domain (dashboard). Adding new services requires no DNS changes.

### Router Port Forwarding

Forward the following ports from the router's WAN interface to 192.168.0.55 (atlas):

| External Port | Internal IP | Internal Port | Protocol | Purpose |
|---|---|---|---|---|
| 80 | 192.168.0.55 | 80 | TCP | Let's Encrypt HTTP-01 challenges (cert-manager) |
| 443 | 192.168.0.55 | 443 | TCP | HTTPS traffic for all services |

The nginx ingress controller (included with K3s) listens on ports 80 and 443 and routes requests to the correct service based on the `Host` header.

## Installation

Prerequisites: Ubuntu 24.04 installed, network configured, SSH access to all nodes.

### 1. Install K3s

On the first node (server):

```bash
curl -sfL https://get.k3s.io | sh -
```

On additional nodes (agents), replace `<server-ip>` and `<token>` (found at `/var/lib/rancher/k3s/server/node-token` on the server):

```bash
curl -sfL https://get.k3s.io | K3S_URL=https://<server-ip>:6443 K3S_TOKEN=<token> sh -
```

Copy the kubeconfig to your local machine:

```bash
scp <user>@<server-ip>:/etc/rancher/k3s/k3s.yaml ~/.kube/config
# Edit ~/.kube/config and replace 127.0.0.1 with <server-ip>
```

Verify:

```bash
kubectl get nodes
```

### 2. Configure NFS Exports

The Mac Mini 2018 (192.168.0.55) serves NFS shares for application data that needs to be accessible from both nodes.

Install NFS server:

```bash
sudo apt install nfs-kernel-server
```

Add the following exports to `/etc/exports`:

```
/data         192.168.0.0/24(rw,sync,no_subtree_check,no_root_squash)
/media/tasks  192.168.0.0/24(rw,sync,no_subtree_check,no_root_squash)
```

Apply and verify:

```bash
sudo exportfs -ra
sudo exportfs -v
```

Install the NFS client on all nodes:

```bash
sudo apt install nfs-common
```

**NFS-backed volumes** (shared across nodes):

| Service | Path |
|---|---|
| calibre | `/data/calibre/config` |
| changedetection | `/data/changedetection` |
| convertx | `/data/convertx` |
| dashboard | `/data/dashboard` |
| filebrowser | `/data/filebrowser/data` |
| freshrss | `/data/freshrss` |
| mealie | `/data/mealie` |
| stirling | `/data/stirling` |
| workers | `/media/tasks` |
| youtrack | `/data/youtrack` |

**Local volumes** (node-pinned, not shared):

| Service | Path |
|---|---|
| keycloak | `/data/keycloakdb` |
| mattermost | `/data/mattermost`, `/data/mattermostdb` |
| mealie | `/data/mealiedb` |
| plex | `/data/plex/config`, `/media` |
| qbittorrent | `/data/qbittorrent/config`, `/media/downloads` |
| filebrowser | `/media` |
| workers | `/media/downloads`, `/media/handbrake/input`, `/media/handbrake/output` |

### 3. Label Nodes

Label the Mac Mini 2018 node for GPU and storage workloads:

```bash
./label-atlas-node.sh
```

This applies the following labels to the `atlas` node:
- `node-role.kubernetes.io/gpu=true` — schedules GPU workloads (Plex, Handbrake)
- `node-role.kubernetes.io/storage=true` — schedules storage-bound workloads (databases, media)

### 4. Install cert-manager and ArgoCD

Run the bootstrap script:

```bash
./bootstrap.sh
```

This installs:
1. **cert-manager** — manages TLS certificates from Let's Encrypt for all ingresses
2. **ArgoCD** — applies the root ApplicationSet that auto-discovers all services under `cluster/overlays/`

Access the ArgoCD UI:

```bash
# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

Once ArgoCD syncs the infrastructure overlay, the UI is available at https://argocd.zahariev.com.

For local access before the ingress is ready:

```bash
kubectl port-forward svc/argocd-server -n argocd 8443:443
```

Then open https://localhost:8443.

### 5. Create Secrets

Secrets are managed outside of git. Each overlay has a `.env` file (gitignored) that holds all secret values.

The format is `secret-name/key:value`, one entry per line:

```
calibre-secrets/admin-password:my-password
keycloak-db-secrets/db-name:keycloak
keycloak-db-secrets/db-user:keycloak
keycloak-db-secrets/db-password:secret
...
```

Fill in the values in `overlays/zahariev.com/.env`, then run:

```bash
./secrets.sh zahariev.com
```

This creates all Kubernetes secrets from the `.env` file. Run this before the first ArgoCD sync, or any time a secret value changes.

## Updates

ArgoCD continuously watches the repository for changes. To update the cluster:

1. Create a branch and make changes to the kustomization files, patches, or base resources.
2. Open a Pull Request and review the changes.
3. Merge the PR into the main branch.
4. ArgoCD detects the new commit, computes the diff against the live cluster, and automatically applies the changes (sync, prune, self-heal).

### Updating ArgoCD and cert-manager

ArgoCD and cert-manager are not managed by ArgoCD — they are bootstrapped manually. To update them:

1. Edit `bootstrap.sh` and bump `ARGOCD_VERSION` or `CERT_MANAGER_VERSION` to the desired release.
2. Re-run the bootstrap script:

```bash
./bootstrap.sh
```

The script is idempotent — `kubectl apply` updates existing resources in place.

## Development 

### Verifying Manifest Changes

Use `cluster/manifests.sh` to build, compare, and clean up rendered Kubernetes manifests before committing changes.

#### Commands

```bash
# Build all manifests and save a snapshot to /tmp/home-server/
./manifests.sh dump zahariev.com

# Build manifests again and show a unified diff against the last snapshot
./manifests.sh diff zahariev.com

# Remove the snapshot directory
./manifests.sh clear
```

The overlay name (e.g. `zahariev.com`) is optional when there is only one overlay.

#### Workflow

1. Run `dump` to capture the current rendered manifests as a baseline.
2. Edit kustomization files, patches, or base resources.
3. Run `diff` to review what changed in the final rendered output.
4. Repeat steps 2–3 until satisfied.
5. Commit your changes and run `clear` to remove the temporary files.
