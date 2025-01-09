#!/bin/bash

PATH=/sbin:/usr/sbin:/usr/local/sbin:/bin:/usr/bin:/usr/local/bin

VERSION=v.1.11.3
#
# restic-check $VERSION
#

SESS=$RANDOM
LOCATION=/srv/southbridge
OPT=""
#URL_UPDATE="https://raw.githubusercontent.com/integral0/scripts/refs/heads/main/restic_check.sh"
URL_UPDATE="https://raw.githubusercontent.com/integral0/scripts/refs/heads/main/restic-check.sh"

# Echo with timestamp
function echo_ts {
    echo -e "$(date "+%F %T [$SESS]")": "$1"
}

# Nice debugging messages
function die {
    echo_ts "Error: $1" >&2
    exit 1;
}

function runSelfUpdate {
  echo "Performing self-update..."

  # Download new version
  echo -n "Downloading latest version..."
  if ! wget --quiet --output-document="$0.tmp" $URL_UPDATE ; then
    echo "Failed: Error while trying to wget new version!"
    echo "File requested: $URL_UPDATE"
    exit 1
  fi
  echo "Done."

  # Copy over modes from old version
  OCTAL_MODE=$(stat -c '%a' $0)
  if ! chmod $OCTAL_MODE "$0.tmp" ; then
    echo "Failed: Error while trying to set mode on $0.tmp."
    exit 1
  fi

  # Spawn update script
  cat > updateScript.sh << EOF
#!/bin/bash
# Overwrite old file with new
if mv "$0.tmp" "$0"; then
  echo "Done. Update complete."
  rm \$0
else
  echo "Failed!"
fi
EOF

  echo -n "Inserting update process..."
  exec /bin/bash updateScript.sh
}

if [ -n "$1" ]; then
  while [ -n "$1" ]; do
    case "$1" in
      -v|--version)
        echo "$0 $VERSION"
        exit
      ;;
      --update)
        runSelfUpdate
        exit
      ;;
      -h|--help)
        echo "Use: $0 [TYPE_BACKUP] [OPTION]"
        echo "Type backup:"
        echo "-l         | --local               Local backup"
        echo "-r         | --remote              Remote backup"
        echo "-v         | --version             Version"
        echo "Option:"
        echo "-sn        | --snapshots           All backups snapshots (default)"
        echo "-snl       | --snapshots-latest    Latest backups snapshot"
        echo "-st        | --stats               All backups stats"
        echo "-stl       | --stats-latest        Latest backups stats"
        echo "-u         | --unlock              Unlock backup"
        echo "-id <ctid> | --ctid <ctid>         Container name"
        echo "-id <ctid> | --ctid <ctid>         Container name"
        echo ""
        echo "For self-update use: $0 --update"
        exit
      ;;
      -l|--local)
        #shift
        BACKUP_TYPE="local"
      ;;
      -r|--remote)
        #shift
        BACKUP_TYPE="remote"
      ;;
      -sn|--snapshot)
        #shift
        OPT="snapshots"
      ;;
      -snl|--snapshots-latest)
        #shift
        OPT="snapshots latest"
      ;;
      -st|--stats)
        #shift
        OPT="stats --mode raw-data"
      ;;
      -stl|--stats-latest)
        #shift
        OPT="stats latest --mode raw-data"
      ;;
      -u|--unlock)
        #shift
        OPT="unlock"
      ;;
      -id|--ctid)
        shift
        CUSTOM_CTID="$1"
      ;;
    esac
    shift
  done
fi

if [ -f /etc/cron.d/mcbackups ]; then
  source ${LOCATION}/etc/mc-restic-backup.conf.dist
  source ${LOCATION}/etc/mc-restic-backup.conf
  echo_ts "Nspawn backup detected."
  if [ -z "$CUSTOM_CTID" ];then CTIDs=$(mctl list | grep -v ^NAME | awk '{print $1}'); else CTIDs=$CUSTOM_CTID; fi
  for CTID in $CTIDs; do
    if [ "$BACKUP_TYPE" == "local" ];then
      echo_ts "Check LOCAL backup: ${LOCAL_DIR}/${CTID} (${OPT:-snapshots})"
      if [ -d "${LOCAL_DIR}/${CTID}" ];then
        export RESTIC_PASSWORD=${LOCAL_PASSWORD}
        LLOG=$(set -x; restic -r ${LOCAL_DIR}/${CTID} ${OPT:-snapshots}; set +x)
        echo "$LLOG"
      else
        echo_ts "backup ${LOCAL_DIR}/${CTID} not found"
      fi
    elif [ "$BACKUP_TYPE" == "remote" ];then
      for REMOTE_BACKUP_HOST in ${REMOTE_BACKUP_HOSTS}; do
        echo_ts "Check REMOTE backup: ${REMOTE_BACKUP_HOST}/${CTID} (${OPT:-snapshots})"
        LOCAL_AUTH_CONFIG="$LOCATION/etc/mc-restic-url-"$(echo -n "$REMOTE_BACKUP_HOST" | sha256sum | awk '{print $1}')".conf"
        source $LOCAL_AUTH_CONFIG 2>/dev/null
        export RESTIC_PASSWORD=${REMOTE_BACKUP_PASSWORD}
        LLOG=$(set -x; restic -r ${REMOTE_BACKUP_HOST}/${CTID} ${OPT:-snapshots}; set +x)
        echo "$LLOG"
      done
    fi
  done
elif [ -f /etc/cron.d/vzbackups ];then
  source ${LOCATION}/etc/vz-restic-backup.conf.dist
  source ${LOCATION}/etc/vz-restic-backup.conf
  echo_ts "OpenVZ backup detected."
  if [ -z "$CUSTOM_CTID" ];then CTIDs=$(vzlist -H | awk '{print $1}');  else CTIDs=$CUSTOM_CTID; fi
  for CTID in $CTIDs; do
    if [ "$BACKUP_TYPE" == "local" ];then
      echo_ts "Check LOCAL backup: ${LOCAL_DIR}/${CTID} (${OPT:-snapshots})"
      if [ -d "${LOCAL_DIR}/${CTID}" ];then
        export RESTIC_PASSWORD=${LOCAL_PASSWORD}
        LLOG=$(set -x; restic -r ${LOCAL_DIR}/${CTID} ${OPT:-snapshots}; set +x)
        echo "$LLOG"
      else
        echo_ts "backup ${LOCAL_DIR}/${CTID} not found"
      fi
    elif [ "$BACKUP_TYPE" == "remote" ];then
      for REMOTE_BACKUP_HOST in ${REMOTE_BACKUP_HOSTS}; do
        echo_ts "Check REMOTE backup: ${REMOTE_BACKUP_HOST}/${CTID} (${OPT:-snapshots})"
        LOCAL_AUTH_CONFIG="$LOCATION/etc/vz-restic-url-"$(echo -n "$REMOTE_BACKUP_HOST" | sha256sum | awk '{print $1}')".conf"
        source $LOCAL_AUTH_CONFIG 2>/dev/null
        export RESTIC_PASSWORD=${REMOTE_BACKUP_PASSWORD}
        LLOG=$(set -x; restic -r ${REMOTE_BACKUP_HOST}/${CTID} ${OPT:-snapshots}; set +x)
        echo "$LLOG"
      done
    fi
  done
elif [ -f /etc/cron.d/dsbackups ]; then
  source ${LOCATION}/etc/ds-restic-backup.conf.dist
  source ${LOCATION}/etc/ds-restic-backup.conf
  echo_ts "VDS backup detected"
  if [ "$BACKUP_TYPE" == "local" ];then
    echo_ts "Local backup for vds not work... Use -r"
  elif [ "$BACKUP_TYPE" == "remote" ];then
    for REMOTE_BACKUP_HOST in ${REMOTE_BACKUP_HOSTS}; do
      echo_ts "Check REMOTE backup: ${REMOTE_BACKUP_HOST}/${CTID} (${OPT:-snapshots})"
      LOCAL_AUTH_CONFIG="$LOCATION/etc/ds-restic-url-"$(echo -n "$REMOTE_BACKUP_HOST" | sha256sum | awk '{print $1}')".conf"
      source $LOCAL_AUTH_CONFIG 2>/dev/null
      export RESTIC_PASSWORD=${REMOTE_BACKUP_PASSWORD}
      LLOG=$(set -x; restic -r ${REMOTE_BACKUP_HOST}/${CTID} ${OPT:-snapshots}; set +x)
      echo "$LLOG"
    done
  fi
else
  die "unknown error. exit."
fi