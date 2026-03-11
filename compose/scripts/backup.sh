#!/usr/bin/env bash
# 0 2 * * * SSHPASS="secretpwd" REMOTE_USER="serveruser" REMOTE_HOST="domain.com" REMOTE_BASE="/backup" LOCAL_BASE="/backups/domain" /backups/scripts/backup.sh 2>&1 | /backups/scripts/timestamp.sh >> /backups/domain/logs/backup.log


# REMOTE_USER="serveruser"          # the user on the remote server, set via environment variable
# REMOTE_HOST="domain.com"          # the remote server's address, set via environment variable
# REMOTE_BASE="/backup"             # the base directory on the remote server where lastFullArchive is located, set via environment variable
# LOCAL_BASE="/backups/domain"  # the local base directory where backups will be stored, set via environment variable

RETRY_DELAY=60   # seconds between retries
MAX_RETRIES=5    # maximum number of attempts
MAX_COMPLETED=2  # number of completed backups to keep

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

BACKUP_NAME=$(basename "$REMOTE_FOLDER")
PROGRESSING_DIR="${LOCAL_BASE}/${BACKUP_NAME}.progressing"
COMPLETED_DIR="${LOCAL_BASE}/${BACKUP_NAME}.completed"

echo "[INFO] Remote folder to backup: $REMOTE_FOLDER"

# If this backup is already completed, nothing to do
if [[ -d "$COMPLETED_DIR" ]]; then
    echo "[INFO] Backup '$BACKUP_NAME' is already completed. Nothing to do."
    exit 0
fi

# Remove any .progressing folders for a different backup (stale partial downloads
# from a previous remote backup that is no longer current)
for old_prog in "${LOCAL_BASE}"/*.progressing; do
    [[ -d "$old_prog" ]] || continue
    if [[ "$old_prog" != "$PROGRESSING_DIR" ]]; then
        echo "[INFO] Removing stale in-progress backup: $old_prog"
        rm -rf "$old_prog"
    fi
done

echo "[INFO] Downloading into: $PROGRESSING_DIR"

ATTEMPT=1
while (( ATTEMPT <= MAX_RETRIES )); do
    echo "[INFO] Rsync attempt $ATTEMPT..."

    sshpass -e rsync -avz --progress --partial --append-verify -e "ssh -o StrictHostKeyChecking=no" \
        "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_FOLDER}/" \
        "${PROGRESSING_DIR}/"

    RSYNC_EXIT=$?
    if [[ $RSYNC_EXIT -eq 0 ]]; then
        echo "[INFO] Rsync completed successfully."

        # Mark backup as completed
        mv "$PROGRESSING_DIR" "$COMPLETED_DIR"
        echo "[INFO] Backup marked as completed: $COMPLETED_DIR"

        # Rotate: keep only the last MAX_COMPLETED completed backups (oldest first)
        mapfile -t COMPLETED_LIST < <(ls -1dtr "${LOCAL_BASE}"/*.completed 2>/dev/null)
        COMPLETED_COUNT=${#COMPLETED_LIST[@]}

        if (( COMPLETED_COUNT > MAX_COMPLETED )); then
            DELETE_COUNT=$(( COMPLETED_COUNT - MAX_COMPLETED ))
            echo "[INFO] Found $COMPLETED_COUNT completed backups, keeping $MAX_COMPLETED, deleting $DELETE_COUNT oldest."
            for (( i=0; i<DELETE_COUNT; i++ )); do
                echo "[INFO] Deleting old backup: ${COMPLETED_LIST[$i]}"
                rm -rf "${COMPLETED_LIST[$i]}"
            done
        fi

        exit 0
    else
        echo "[WARN] Rsync failed with exit code $RSYNC_EXIT."
        if (( ATTEMPT == MAX_RETRIES )); then
            echo "[ERROR] Reached maximum retries. Will resume on next scheduled run."
            exit 1
        fi
        echo "[INFO] Waiting ${RETRY_DELAY}s before retry..."
        sleep "$RETRY_DELAY"
        ((ATTEMPT++))
    fi
done