#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
assertDockerRunning

if (( ${#ROLL_PARAMS[@]} == 0 )) || [[ "${ROLL_PARAMS[0]}" == "help" ]]; then
  roll backup --help || exit $? && exit $?
fi

### load connection information for the mysql service
DB_VOLUME="${ROLL_ENV_NAME}_dbdata"
REDIS_VOLUME="${ROLL_ENV_NAME}_redis"
ES_VOLUME="${ROLL_ENV_NAME}_esdata"
CONTAINER_NAME="${ROLL_ENV_NAME}_backup"
ENV_PHP_LOC="$(pwd)/app/etc/env.php"
AUTH_LOC="$(pwd)/auth.json"

"${ROLL_DIR}/bin/roll" env down

if [ ! -d ".roll/" ]; then
  mkdir .roll/
fi

if [ ! -d ".roll/backups" ]; then
  mkdir .roll/backups/
fi

ID=$(date +%s)
BACKUP_LOC="$(pwd)/.roll/backups/$ID/"
mkdir $BACKUP_LOC

echo ""
echo ""
echo "------------------ STARTING BACKUP IN: $BACKUP_LOC (no output nor progress) ---------------------"
echo ""

case "${ROLL_PARAMS[0]}" in
    db)

        docker run \
            --rm --name $CONTAINER_NAME \
            --mount source=$DB_VOLUME,target=/data -v \
            $BACKUP_LOC:/backup ubuntu bash \
            -c "tar -czvf /backup/db.tar.gz /data"


    ;;
    redis)

        docker run \
            --rm --name $CONTAINER_NAME \
            --mount source=$REDIS_VOLUME,target=/data -v \
            $BACKUP_LOC:/backup ubuntu bash \
            -c "tar -czvf /backup/redis.tar.gz /data"

    ;;
    elasticserach)

        docker run \
            --rm --name $CONTAINER_NAME \
            --mount source=$ES_VOLUME,target=/data -v \
            $BACKUP_LOC:/backup ubuntu bash \
            -c "tar -czvf /backup/es.tar.gz /data"

    ;;
    all)

        docker run \
            --rm --name $CONTAINER_NAME \
            --mount source=$DB_VOLUME,target=/data -v \
            $BACKUP_LOC:/backup ubuntu bash \
            -c "tar -czvf /backup/db.tar.gz /data"

        docker run \
            --rm --name $CONTAINER_NAME \
            --mount source=$REDIS_VOLUME,target=/data -v \
            $BACKUP_LOC:/backup ubuntu bash \
            -c "tar -czvf /backup/redis.tar.gz /data"

        docker run \
            --rm --name $CONTAINER_NAME \
            --mount source=$ES_VOLUME,target=/data -v \
            $BACKUP_LOC:/backup ubuntu bash \
            -c "tar -czvf /backup/es.tar.gz /data"

        if [ -f "$ENV_PHP_LOC" ]; then
          cp $ENV_PHP_LOC $BACKUP_LOC
        fi

        if [ -f "$AUTH_LOC" ]; then
          cp "$AUTH_LOC" $BACKUP_LOC
        fi

    ;;
    *)
        fatal "The command \"${ROLL_PARAMS[0]}\" does not exist. Please use --help for usage."
        ;;
esac

tar -czvf $(pwd)/.roll/backups/latest.tar.gz $BACKUP_LOC

echo ""
echo ""
echo "------------------ FNISHED BACKUP WITH ID: $ID ---------------------"
echo ""
