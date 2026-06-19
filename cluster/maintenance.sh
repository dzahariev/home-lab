#!/bin/bash

ARCHIVE_DIR="/media/ubuntu/HDD/Media/archives"
DATA_DIR="/media/ubuntu/HDD/Media/data"

shouldCreateArchive() {
  local CURRENT_DAY=$(date +%d)
  if (( CURRENT_DAY <= 20 )); then
    return 1
  fi
  local CURRENT_YYMM=$(date +%y%m)
  local EXISTING=$(find "${ARCHIVE_DIR}" -maxdepth 1 -type d -name "${CURRENT_YYMM}*data" 2>/dev/null)
  [[ -z "$EXISTING" ]]
}

createArchive() {
  local ARCHIVE_BASE="$(date +%y%m%d)data"
  local ARCHIVE_NAME="${ARCHIVE_BASE}.tgz"
  local WRAPPER_DIR="${ARCHIVE_DIR}/${ARCHIVE_BASE}"
  local ARCHIVE_PATH="${WRAPPER_DIR}/${ARCHIVE_NAME}"

  echo "Creating archive ${ARCHIVE_PATH} ..."
  sudo mkdir -p "${WRAPPER_DIR}"
  sudo tar -czf "${ARCHIVE_PATH}" -C "$(dirname "${DATA_DIR}")" "$(basename "${DATA_DIR}")"

  if [[ $? -eq 0 ]]; then
    echo "Archive created successfully!"

    for old_dir in "${ARCHIVE_DIR}"/*/; do
      [[ -d "$old_dir" ]] || continue
      if [[ "$old_dir" != "${WRAPPER_DIR}/" ]]; then
        echo "Deleting old archive folder: $old_dir"
        sudo rm -rf "$old_dir"
      fi
    done
    echo "Previous archives deleted!"

    echo "${WRAPPER_DIR}" | sudo tee "${ARCHIVE_DIR}/lastFullArchive" > /dev/null
    echo "lastFullArchive updated with: ${WRAPPER_DIR}"
  else
    echo "Archive creation failed!"
    sudo rm -rf "${WRAPPER_DIR}"
  fi
}

stop_k3s() {
    echo "Stopping k3s cluster..."
    if sudo systemctl is-active --quiet k3s.service; then
        sudo systemctl stop k3s.service || true
        sleep 5
        echo "k3s stopped"
    else
        echo "k3s already stopped"
    fi
}

stop_nfs_shares() {
    echo "Stopping NFS shares..."    
    if [ -f /etc/exports ]; then
        sudo cp /etc/exports /etc/exports.bak
        sudo sed -i 's/^\([^#]\)/#\1/' /etc/exports
        echo "NFS exports commented out"
    fi
    
    sudo systemctl stop nfs-server.service nfs-mountd.service rpc-statd.service 2>/dev/null || true
    sleep 3
    
    if sudo systemctl is-active --quiet nfs-server.service; then
        echo "NFS server did not stop cleanly"
    else
        echo "NFS shares stopped"
    fi
}

start_nfs_shares() {
    echo "Starting NFS shares..."    
    if [ -f /etc/exports.bak ]; then
        sudo cp /etc/exports.bak /etc/exports
        sudo rm /etc/exports.bak
        sudo exportfs -ra 2>/dev/null || true
        echo "NFS exports restored"
    fi
    
    sudo systemctl start rpc-statd.service nfs-mountd.service nfs-server.service
    sleep 2
    
    if sudo systemctl is-active --quiet nfs-server.service; then
        echo "NFS shares started successfully"
    else
        echo "NFS server failed to start"
    fi
}

start_k3s() {
    echo "Starting k3s cluster..."
    sudo systemctl start k3s.service
    
    echo "Waiting for k3s to become ready..."
    local max_wait=120  # Increased timeout
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        if sudo kubectl get nodes >/dev/null 2>&1; then
            echo "k3s is ready after $((wait_time / 5 + 1)) attempts"
            return 0
        fi
        sleep 5
        wait_time=$((wait_time + 5))
        
        if [ $((wait_time % 30)) -eq 0 ] && [ $wait_time -gt 0 ]; then
            echo "Still waiting for k3s..."
        fi
    done
    
    echo "k3s did not become ready within timeout - see logs for details"
    sudo systemctl status k3s --no-pager | tail -n 10
    return 1
}

echo "Get updates from GitHub ..."
cd /home/helios/home-server
git pull

echo "Stops k3s ..."
stop_k3s

echo "Stops NFS ..."
stop_nfs_shares

echo "Updates the host packages ..."
sudo apt-get clean -y
sudo apt-get update
sudo apt-get dist-upgrade -y
sudo apt-get upgrade -y
sudo apt-get autoremove -y
echo "Host packages are updated!"

echo "Checking if monthly archive is needed ..."
if shouldCreateArchive; then
    echo "Monthly archive will be created."
    createArchive
else
  echo "Monthly archive already exists, skipping."
fi

echo "Starts NFS ..."
start_nfs_shares

echo "Starts k3s ..."
start_k3s || echo "k3s failed to start properly"

echo "Checking if reboot is required ..."
if [ -f /var/run/reboot-required ]; then
  echo "Rebooting the host!"
  sudo /sbin/reboot
else
  echo "Reboot is not required."
fi
