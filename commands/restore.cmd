#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1


CURRENT_DIR=$(pwd)
if [[ ! -f "$CURRENT_DIR/.env.roll" ]]; then
	if [[ -f "$CURRENT_DIR/.env" ]]; then
		 sed -i.warden 's/WARDEN/ROLL/g' "$CURRENT_DIR/.env"
		if [[ -d "$CURRENT_DIR/.warden" ]]; then
			mv "$CURRENT_DIR/.warden" "$CURRENT_DIR/.roll"
			if [[ -f "$CURRENT_DIR/.roll/warden-env.yml" ]]; then
					mv "$CURRENT_DIR/.roll/warden-env.yml" "$CURRENT_DIR/.roll/roll-env.yml"
					sed -i.warden 's/WARDEN/ROLL/g;s/warden/roll/g' "$CURRENT_DIR/.roll/roll-env.yml"
			fi
		fi

		if [[ -n "$(grep -r 'ROLL_NO_STATIC_CACHING' "$CURRENT_DIR/.env")" ]]; then
			perl -i -pe's/.*ROLL_NO_STATIC_CACHING.*$/ROLL_NO_STATIC_CACHING\=1/g' "$CURRENT_DIR/.env"
		else
			echo "ROLL_NO_STATIC_CACHING=1" >> "$CURRENT_DIR/.env"
		fi

		if [[ -n "$(grep -r 'ROLL_' "$CURRENT_DIR/.env")" ]]; then
			mv "$CURRENT_DIR/.env" "$CURRENT_DIR/.env.roll"
		fi
	fi
fi

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
assertDockerRunning

if [[ ${ROLL_DB:-1} -eq 0 ]]; then
  fatal "Database environment is not used (ROLL_DB=0)."
fi

### load information
DOCKER_COMPOSER_V=$( docker compose version | grep -Eo '[0-9]\.([0-9][0-9]|[0-9])\.[0-9]+')

DB_VOLUME_NAME="dbdata"
REDIS_VOLUME_NAME="redis"
ES_VOLUME_NAME="esdata"
DB_VOLUME="${ROLL_ENV_NAME}_${DB_VOLUME_NAME}"
REDIS_VOLUME="${ROLL_ENV_NAME}_${REDIS_VOLUME_NAME}"
ES_VOLUME="${ROLL_ENV_NAME}_${ES_VOLUME_NAME}"
CONTAINER_NAME="${ROLL_ENV_NAME}_restore"
LATEST_TIMESTAMP=$(ls "$(pwd)/.roll/backups/" | sort -n | tail -1)
ENV_PHP_LOC="$(pwd)/app/etc/env.php"
AUTH_LOC="$(pwd)/auth.json"
SKIP_DB=0
SKIP_REDIS=0
SKIP_ELASTICSEARCH=0


if [ ! -d ".roll/backups/$LATEST_TIMESTAMP" ]; then
  fatal "No backups available in the directory .roll/backups/"
fi

if [ ! -f ".roll/backups/$LATEST_TIMESTAMP/db.tar.gz" ]; then
  SKIP_DB=1
fi

if [ ! -f ".roll/backups/$LATEST_TIMESTAMP/redis.tar.gz" ]; then
  SKIP_REDIS=1
fi

if [ ! -f ".roll/backups/$LATEST_TIMESTAMP/es.tar.gz" ]; then
  SKIP_ELASTICSEARCH=1
fi


echo ""
echo ""
echo "------------------ STARTING INITIALIZATION ---------------------"
echo ""

RUNNING_CONTAINERS=$(roll env ps --services --filter "status=running" | grep 'php-fpm' | sed 's/ *$//g')
if [[ ! -z "$RUNNING_CONTAINERS" ]]; then
	"${ROLL_DIR}/bin/roll" env down
fi

echo ""
echo "------ CREATING CONTAINER (if necessary) ---------------------"
echo ""

if [[ $SKIP_DB -eq 0 ]]; then
  if [ ! -z "$(docker volume ls | grep -w $DB_VOLUME)" ]; then
      docker volume rm $DB_VOLUME && true # dont fail
  fi
  docker volume create $DB_VOLUME \
			--label com.docker.compose.project=$ROLL_ENV_NAME \
			--label com.docker.compose.version=$DOCKER_COMPOSER_V \
			--label com.docker.compose.volume=$DB_VOLUME_NAME
fi

if [[ $SKIP_REDIS -eq 0 ]]; then
    if [ ! -z "$(docker volume ls | grep -w $REDIS_VOLUME)" ]; then
         docker volume rm $REDIS_VOLUME && true # dont fail
    fi
    docker volume create $REDIS_VOLUME \
			 --label com.docker.compose.project=$ROLL_ENV_NAME \
			 --label com.docker.compose.version=$DOCKER_COMPOSER_V \
			 --label com.docker.compose.volume=$REDIS_VOLUME_NAME
fi

if [[ $SKIP_ELASTICSEARCH -eq 0 ]]; then
    if [ ! -z "$(docker volume ls | grep -w $ES_VOLUME)" ]; then
         docker volume rm $ES_VOLUME && true # dont fail
    fi
    docker volume create $ES_VOLUME \
				 --label com.docker.compose.project=$ROLL_ENV_NAME \
				 --label com.docker.compose.version=$DOCKER_COMPOSER_V \
				 --label com.docker.compose.volume=$ES_VOLUME_NAME
fi



echo ""
echo ""
echo "------------------ RESTORING BACKUP FROM: .roll/backups/$LATEST_TIMESTAMP/ (no output nor progress) ---------------------"
echo ""

if [[ $SKIP_DB -eq 0 ]]; then
    docker run \
        --rm --name $CONTAINER_NAME \
        --mount source=$DB_VOLUME,target=/data \
        -v $(pwd)/.roll/backups/$LATEST_TIMESTAMP/:/backup ubuntu bash \
        -c "cd /data && tar -xvf /backup/db.tar.gz --strip 1 && chown -R 999:root /data"
fi

if [[ $SKIP_REDIS -eq 0 ]]; then
    docker run \
        --rm --name $CONTAINER_NAME \
        --mount source=$REDIS_VOLUME,target=/data \
        -v $(pwd)/.roll/backups/$LATEST_TIMESTAMP/:/backup ubuntu bash \
        -c "cd /data && tar -xvf /backup/redis.tar.gz --strip 1 && chown -R 999:root /data"
fi

if [[ $SKIP_ELASTICSEARCH -eq 0 ]]; then
    docker run \
        --rm --name $CONTAINER_NAME \
        --mount source=$ES_VOLUME,target=/data \
        -v $(pwd)/.roll/backups/$LATEST_TIMESTAMP/:/backup ubuntu bash \
        -c "cd /data && tar -xvf /backup/es.tar.gz --strip 1 && chown -R 1000:root /data"
fi


if [ -f ".roll/backups/$LATEST_TIMESTAMP/env.php" ]; then
  cp .roll/backups/$LATEST_TIMESTAMP/env.php $ENV_PHP_LOC
fi

if [ -f ".roll/backups/$LATEST_TIMESTAMP/auth.json" ]; then
  cp .roll/backups/$LATEST_TIMESTAMP/auth.json $AUTH_LOC
fi

echo ""
echo ""
echo "------------------ FNISHED BACKUP FROM: .roll/backups/$LATEST_TIMESTAMP/ ---------------------"
echo ""
