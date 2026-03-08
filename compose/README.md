# Compose 
## Hardware 
Raspberry Pi 4 with 8GB RAM booting from SSD drive

## Storage 
Two drives are attached:
 - 512 GB SSD - for OS and containers
 - 1 TB SSD - for TimeMachine backups and remote systems backup

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
# crontab -e
```
Add the line:
```
0 4 * * 6 /home/ubuntu/home-lab/compose/scripts/maintenance.sh 2>&1 | /home/ubuntu/home-lab/compose/scripts/timestamp.sh >> /home/ubuntu/logs/maintenance.log
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
