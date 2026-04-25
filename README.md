# home-lab

Home lab project consisting of two components:

- **[Compose](compose/README.md)** — always-on infrastructure services running on a low-power Raspberry Pi. Handles DNS filtering, TimeMachine backups, and remote system backups using bare metal services and Docker Compose. Internal network only.

- **[Cluster](cluster/README.md)** — K3s Kubernetes cluster running on two bare metal Mac Mini nodes. Hosts applications exposed to the internet with TLS termination, managed via ArgoCD and Kustomize.
