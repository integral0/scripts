#!/bin/bash

PATH=/sbin:/usr/sbin:/usr/local/sbin:/bin:/usr/bin:/usr/local/bin

VERSION=v.1.16.0
#
# restic-check $VERSION
#

SESS=$RANDOM
HN=$(hostname -f 2>/dev/null)
LOCATION=/srv/southbridge
OPT=""
#URL_UPDATE="https://raw.githubusercontent.com/integral0/scripts/refs/heads/main/restic_check.sh"
URL_UPDATE="https://raw.github.com/integral0/scripts/main/restic-check.sh"

# Echo with timestamp
function echo_ts {
    echo -e "$(date "+%F %T [$SESS]")": "$1"
}

function echo_tsn {
    echo -n "$(date "+%F %T [$SESS]")": "$1"
}

# Nice debugging messages
function die {
    echo_ts "Error: $1" >&2
    exit 1;
}

function runSelfUpdate {
  echo_ts "Performing self-update..."
  echo_ts  "Check current version... $VERSION"
  # Download new version
  echo_tsn "Check latest version...  "
  if ! wget --quiet --output-document="$0.tmp" $URL_UPDATE ; then
    echo_ts "Failed: Error while trying to wget new version!"
    echo_ts "File requested: $URL_UPDATE"
    exit 1
  fi
  NEW_VERSION=$(cat $0.tmp 2>/dev/null | grep ^VERSION | awk -F'=' '{print $2}')
  echo "$NEW_VERSION"
  if [ "${VERSION}" == "${NEW_VERSION}" ];then
    echo_ts "SKIP. This script latest version."
    return;
  fi
  # Copy over modes from old version
  OCTAL_MODE=$(stat -c '%a' $0)
  if ! chmod $OCTAL_MODE "$0.tmp" ; then
    echo_ts "Failed: Error while trying to set mode on $0.tmp."
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

  echo_tsn "Inserting update process..."
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
        echo "Use: $0 [GLOBAL OPTION]"
        echo "or"
        echo "Use: $0 [TYPE_BACKUP] [OPTION] [FLAGS]"
        echo ""
        echo "Type backup:"
        echo "-l         | --local               Local backup"
        echo "-r         | --remote              Remote backup"
        echo ""
        echo "Option:"
        echo "-sn                      | --snapshots           All backups snapshots (default)"
        echo "-snl                     | --snapshots-latest    Latest backups snapshot"
        echo "-st                      | --stats               All backups stats"
        echo "-stl                     | --stats-latest        Stats for latest snapshot"
        echo "-ls <id snapshot> <path> |                       List files for lastest snapshot"
        echo "                         | --unlock              Unlock repo"
        echo "                         | --check               Check repo"
        echo "                         | --repair              Repair repo"
        echo ""
        echo "Flags:"
        echo "-id <ctid>               | --ctid <ctid>         Container name"
        echo ""
        echo "Global option:"
        echo "-h                       | --help                Help page"
        echo "-v                       | --version             Version"
        echo "                         | --update              For self-update this script"
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
        OPT="snapshots"
      ;;
      -snl|--snapshots-latest)
        OPT="snapshots latest"
      ;;
      -st|--stats)
        OPT="stats --mode raw-data"
      ;;
      -stl|--stats-latest)
        OPT="stats latest --mode raw-data"
      ;;
      -ls|--list)
        shift
        LIST_SNAPSHOT="$1"
        shift
        LIST_PATH="$1"
        OPT="ls ${LIST_SNAPSHOT} /${CUSTOM_CTID}${LIST_PATH}"
      ;;
      --unlock)
        OPT="unlock"
      ;;
      --check)
        OPT="check"
      ;;
      --repair)
        OPT="repair"
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
  if [ -z "$CUSTOM_CTID" ]; then
    CTIDs_LOCAL=$(mctl list | grep -v ^NAME | awk '{print $1}')
    CTIDs_REMOTE="$CTIDs_LOCAL ${HN}_etc"
  else
    CTIDs_LOCAL=${CUSTOM_CTID}
    CTIDs_REMOTE=${CUSTOM_CTID}
  fi

  if [ "$BACKUP_TYPE" == "local" -a -n "$LOCAL_DIR" ];then
    for CTID in $CTIDs_LOCAL; do
      if [[ -d "${LOCAL_DIR}/${CTID}" ]] && [[ $(echo $CTIDS_EXCLUDE| grep "$CTID" | wc -l) -eq 0 ]];then
        echo_ts "CHECK local backup: ${CTID}"
        export RESTIC_PASSWORD=${LOCAL_PASSWORD}
        LLOG=$(set -x; restic -r ${LOCAL_DIR}/${CTID} ${OPT:-snapshots}; set +x)
        echo "$LLOG"
      elif [[ ! -d "${LOCAL_DIR}/${CTID}" ]] && [[ $(echo $CTIDS_EXCLUDE| grep "$CTID" | wc -l) -gt 0 ]];then
        echo_ts "SKIP local backup: $CTID excluded"
      else
        echo_ts "Backup ${LOCAL_DIR}/${CTID} not found"
      fi
    done
  elif [ "$BACKUP_TYPE" == "local" -a -z "$LOCAL_DIR" ];then
    echo_ts "SKIP. Local backup is DISABLED"
  elif [ "$BACKUP_TYPE" == "remote" ];then
    for CTID in $CTIDs_REMOTE; do
      for REMOTE_BACKUP_HOST in ${REMOTE_BACKUP_HOSTS}; do
        if [[ $(echo $CTIDS_EXCLUDE_REMOTE| grep "$CTID" | wc -l) -eq 0 ]]; then
          echo_ts "CHECK remote backup: ${CTID}"
          LOCAL_AUTH_CONFIG="$LOCATION/etc/mc-restic-url-"$(echo -n "$REMOTE_BACKUP_HOST" | sha256sum | awk '{print $1}')".conf"
          source $LOCAL_AUTH_CONFIG 2>/dev/null
          export RESTIC_PASSWORD=${REMOTE_BACKUP_PASSWORD}
          LLOG=$(set -x; restic -r ${REMOTE_BACKUP_HOST}/${CTID} ${OPT:-snapshots}; set +x)
          echo "$LLOG"
        else
           echo_ts "SKIP remote backup: $CTID excluded"
        fi
      done
    done
  fi
fi

### Files Backup
if [ -f /etc/cron.d/filebackups ]; then
  source ${LOCATION}/etc/file-restic-backup.conf.dist
  source ${LOCATION}/etc/file-restic-backup.conf
  echo_ts "Custom files backup detected."

  if [ "$BACKUP_TYPE" == "local" ];then
    echo_ts "SKIP. Local backup is DISABLED"
  elif [ "$BACKUP_TYPE" == "remote" ];then
      for REMOTE_BACKUP_HOST in ${REMOTE_BACKUP_HOSTS}; do
          echo_ts "CHECK remote files backup: ${REMOTE_BACKUP_PATH}"
          LOCAL_AUTH_CONFIG="$LOCATION/etc/file-restic-url-"$(echo -n "$REMOTE_BACKUP_HOST" | sha256sum | awk '{print $1}')".conf"
          source $LOCAL_AUTH_CONFIG 2>/dev/null
          export RESTIC_PASSWORD=${REMOTE_BACKUP_PASSWORD}
          LLOG=$(set -x; restic -r ${REMOTE_BACKUP_HOST} ${OPT:-snapshots}; set +x)
          echo "$LLOG"
      done
  fi
fi

### VZ Backup
if [ -f /etc/cron.d/vzbackups ];then
  source ${LOCATION}/etc/vz-restic-backup.conf.dist
  source ${LOCATION}/etc/vz-restic-backup.conf
  echo_ts "OpenVZ backup detected."
  if [ -z "$CUSTOM_CTID" ];then CTIDs=$([[ -d /vz/private/ ]]&& cd /vz/private/ && echo *); else CTIDs=$CUSTOM_CTID; fi
  if [ "$BACKUP_TYPE" == "local" -a -n "$LOCAL_DIR" ];then
    for CTID in $CTIDs; do
      echo_ts "Check LOCAL backup: ${LOCAL_DIR}/${CTID} (${OPT:-snapshots})"
      if [ -d "${LOCAL_DIR}/${CTID}" ];then
        export RESTIC_PASSWORD=${LOCAL_PASSWORD}
        LLOG=$(set -x; restic -r ${LOCAL_DIR}/${CTID} ${OPT:-snapshots}; set +x)
        echo "$LLOG"
      else
        echo_ts "backup ${LOCAL_DIR}/${CTID} not found"
      fi
    done
  elif [ "$BACKUP_TYPE" == "local" -a -z "$LOCAL_DIR" ];then
    echo_ts "SKIP. Local backup is DISABLED"
  elif [ "$BACKUP_TYPE" == "remote" ];then
    for CTID in $CTIDs ${HN}_etc; do
      for REMOTE_BACKUP_HOST in ${REMOTE_BACKUP_HOSTS}; do
        echo_ts "Check REMOTE backup: ${REMOTE_BACKUP_HOST}/${CTID} (${OPT:-snapshots})"
        LOCAL_AUTH_CONFIG="$LOCATION/etc/vz-restic-url-"$(echo -n "$REMOTE_BACKUP_HOST" | sha256sum | awk '{print $1}')".conf"
        source $LOCAL_AUTH_CONFIG 2>/dev/null
        export RESTIC_PASSWORD=${REMOTE_BACKUP_PASSWORD}
        LLOG=$(set -x; restic -r ${REMOTE_BACKUP_HOST}/${CTID} ${OPT:-snapshots}; set +x)
        echo "$LLOG"
      done
    done
  fi
fi

### DS Backup
if [ -f /etc/cron.d/dsbackups ]; then
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
fi
