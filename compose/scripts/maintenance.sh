#!/usr/bin/env bash

COMPOSE_DIR=$(cd "$(dirname "$0")/.." && pwd)

dockerHubIsUp() {
  docker pull nginx:alpine-slim > /dev/null
}

echo "Updates the host packages ..."
sudo apt-get clean -y
sudo apt-get update
sudo apt-get dist-upgrade -y
sudo apt-get upgrade -y
sudo apt-get autoremove -y
echo "Host packages are updated!"

echo "Check if DockerHub can be reached ..."
if ! dockerHubIsUp ; then
	echo "DockerHub cannot be reached, will not update images."
else
	echo "Backup of compose file ..."
 	cp "$COMPOSE_DIR"/docker-compose.yml "$COMPOSE_DIR"/docker-compose.yml.old
 	echo "Old compose file is saved!"

	echo "Gets update from GitHub ..."
	cd "$COMPOSE_DIR"
	git pull
	echo "Updates are fetched from GitHub!"

	echo "Pull new containers ..."
 	cd "$COMPOSE_DIR"
 	docker compose --env-file .env.server pull
 	echo "Containers are pulled!"

	echo "Prepare compose file for stopping ..."
 	mv "$COMPOSE_DIR"/docker-compose.yml "$COMPOSE_DIR"/docker-compose.yml.new
 	mv "$COMPOSE_DIR"/docker-compose.yml.old "$COMPOSE_DIR"/docker-compose.yml
 	echo "Old compose file is restored!"

	echo "Stops the containers ..."
 	cd "$COMPOSE_DIR"
 	docker compose --env-file .env.server down --remove-orphans
 	echo "Containers are stopped!"
	
	echo "Prepare compose file for starting ..."
 	rm "$COMPOSE_DIR"/docker-compose.yml
 	mv "$COMPOSE_DIR"/docker-compose.yml.new "$COMPOSE_DIR"/docker-compose.yml
 	echo "New compose file is restored!"

	echo "Starts the containers ..."
	cd "$COMPOSE_DIR"
	docker compose --env-file .env.server up -d
	echo "Containers are started!"

	echo "Cleanup images ..."
	cd "$COMPOSE_DIR"
	docker system prune -af
	echo "Images are cleared!"
fi

echo "Checking if reboot is required ..."
if [ -f /var/run/reboot-required ]; then
	echo "Rebooting the host!"
	sudo /sbin/reboot
else
	echo "Reboot is not required."
fi
