#!/usr/bin/env bash
# 0 2 * * 3 SSHPASS="secretpwd" REMOTE_USER="serveruser" REMOTE_HOST="domain.com" REMOTE_BASE="/backup" LOCAL_BASE="/backups/domain.com" /backups/scripts/backup.sh 2>&1 | /backups/scripts/timestamp.sh >> /backups/domain.com/logs/backup.log


# REMOTE_USER="serveruser"          # the user on the remote server, set via environment variable
# REMOTE_HOST="domain.com"          # the remote server's address, set via environment variable
# REMOTE_BASE="/backup"             # the base directory on the remote server where lastFullArchive is located, set via environment variable
# LOCAL_BASE="/backups/domain.com"  # the local base directory where backups will be stored, set via environment variable

RETRY_DELAY=60   # seconds between retries
MAX_RETRIES=5    # maximum number of attempts

echo "[INFO] Fetching lastFullArchive file..."
sshpass -e rsync -avz --progress --partial --append-verify -e "ssh -o StrictHostKeyChecking=no" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_BASE}/lastFullArchive" /tmp/${REMOTE_HOST}_lastFullArchive || {
    echo "[ERROR] Failed to fetch lastFullArchive"
    exit 1
}

REMOTE_FOLDER=$(cat /tmp/${REMOTE_HOST}_lastFullArchive | tr -d '\r\n')
if [[ -z "$REMOTE_FOLDER" ]]; then
    echo "[ERROR] lastFullArchive is empty or invalid."
    rm /tmp/${REMOTE_HOST}_lastFullArchive
    exit 1
fi

rm /tmp/${REMOTE_HOST}_lastFullArchive

echo "[INFO] Remote folder to backup: $REMOTE_FOLDER"

ATTEMPT=1
while (( ATTEMPT <= MAX_RETRIES )); do
    echo "[INFO] Rsync attempt $ATTEMPT..."

    sshpass -e rsync -avz --progress --partial --append-verify -e "ssh -o StrictHostKeyChecking=no" \
        "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_FOLDER}/" \
        "${LOCAL_BASE}/$(basename "$REMOTE_FOLDER")/"

    RSYNC_EXIT=$?
    if [[ $RSYNC_EXIT -eq 0 ]]; then
        echo "[INFO] Rsync completed successfully."
        exit 0
    else
        echo "[WARN] Rsync failed with exit code $RSYNC_EXIT."
        if (( ATTEMPT == MAX_RETRIES )); then
            echo "[ERROR] Reached maximum retries. Giving up."
            exit 1
        fi
        echo "[INFO] Waiting ${RETRY_DELAY}s before retry..."
        sleep "$RETRY_DELAY"
        ((ATTEMPT++))
    fi
done