# Compose 
Apps and services that are best to be run on bare metal or using docker-compose stack outside of the k8s cluster, on separate hardware that is not CPU hungry, but is power efficient.

## Hardware 

| Node | Name | RAM | OS Disk | Storage |
|---|---|---|---|---|
| Raspberry Pi 4 | Chronos | 8 GB | 512 GB SSD | 1 TB SSD (TimeMachine + Backups) |

## OS
Ubuntu 24.04

## Visibility
Internal network only

## Responsibilities
Bare metal stack:
- SMB and Avahi - for TimeMachine backups
- Cron + shell scripts for external systems backup

Compose stack:
- NginX - Static dashboard showing links to other components
- CAdvisor - metrics collector
- Node-exporter - metrics collector
- Blackbox-exporter - metrics collector
- Prometheus - metrics aggregator
- Grafana - metrics visualiser
- PiHole - Ad blocker
- File Browser - exactly what it says

## Updates
Monthly scheduled updates and restart if required managed by cron + `maintenance.sh`.

Cron config:
```
# sudo crontab -e
```
Add the line:
```
0 2 15 * * /home/ubuntu/home-lab/compose/scripts/maintenance.sh 2>&1 | /home/ubuntu/home-lab/compose/scripts/timestamp.sh >> /home/ubuntu/logs/maintenance.log
```

Execution is at [At 04:00 on Saturday](https://crontab.guru/#0_4_*_*_6). Logs are in `/home/ubuntu/logs/maintenance.log`.

Enable log rotation by creating a file `/etc/logrotate.d/server.maintenance` with content:
```
/home/ubuntu/logs/maintenance.log {
        monthly
        copytruncate
        missingok
        rotate 12
        compress
        delaycompress
        notifempty
}
```
## Backups
Daily scheduled backup managed by cron + `backup.sh`.
The server that is backed up need to provide a folder with backup and a file named `lastFullArchive` taht have the path to the folder that contains the archive.

Cron config:
```
# crontab -e
```
Add the line:
```
0 2 * * * SSHPASS="secretpwd" REMOTE_USER="serveruser" REMOTE_HOST="domain.com" REMOTE_BASE="/backup" LOCAL_BASE="/backups/domain" /backups/scripts/backup.sh 2>&1 | /backups/scripts/timestamp.sh >> /backups/domain/logs/backup.log
```

Enable log rotation by creating a file `/etc/logrotate.d/backup.domain` with content:
```
/backups/domain/logs/backup.log {
        monthly
        copytruncate
        missingok
        rotate 12
        compress
        delaycompress
        notifempty
}
```

## Prepare
Adjust the .env file content by setting the base folder, domain, and secrets, or create a new file named .env.server and use it instead.

## Start the bundle
```
docker compose --env-file .env.server up -d
```
## Stop the bundle
```
docker compose --env-file .env.server down
```
