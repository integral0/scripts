#!/bin/bash

VERSION=v.2.2.0
#
# show_backup.sh $VERSION
#

set -o errtrace
set -o pipefail

readonly PATH=/sbin:/usr/sbin:/usr/local/sbin:/bin:/usr/bin:/usr/local/bin

SESS=$RANDOM
HN=$(hostname -f 2>/dev/null)
LOCATION=/srv/southbridge
OPT=""
CUSTOM_CTID="all"

typeset bn=""
bn="$(basename "$0")"
readonly bn

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

URL_UPDATE="https://raw.github.com/integral0/scripts/main/restic-check.sh"
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
    rm -f "$0.tmp"
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


usage() {
        echo "Use: $0 [GLOBAL OPTION]"
        echo "or"
        echo "Use: $0 [TYPE_BACKUP] [CTID] [OPTION]"
        echo ""
        echo "Type backup:"
        echo "-l              | --local               Local backup"
        echo "-r              | --remote              Remote backup"
        echo ""
        echo "Ctid:"
        echo "-I <ctid>       | --id <ctid>, --ctid <ctid> Container name"
        echo ""
        echo "Option:"
        echo "-s              | --sn, --snapshots         All backups snapshots (default)"
        echo "-S              | --snl, --snapshots-latest Latest backups snapshot"
        echo "-t              | --st, --stats             All backups stats"
        echo "-T              | --stl, --stats-latest     Stats for latest snapshot"
        echo "                | --ls <id snapshot> <path> List files for <id snapshot> and <path>"
        echo "                | --unlock                  Unlock repo"
        echo "                | --check                   Check repo"
        echo "                | --repair                  Repair repo"
        echo ""
        echo "Global option:"
        echo "-h              | --help                Help page"
        echo "-v              | --version             Version"
        echo "                | --update              Self update"
}

function read_args() {
# Getopts
getopt -T; (( $? == 4 )) || { echo "incompatible getopt version" >&2; exit 4; }

if ! TEMP=$(getopt -o lrI:sStThv --longoptions local,remote,id:,ctid:,sn,snapshots,snl,snapshots-latest,st,stats,stl,stats-latest,ls:,unlock,check,repair,version,help,update -n "$bn" -- "$@")
then
    echo "Terminating..." >&2
    exit 1
fi

eval set -- "$TEMP"
unset TEMP

if [[ -n "$1" ]]; then
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --)
        shift
        break
      ;;
      -v|--version)
        echo "$bn $VERSION"
        exit 0
      ;;
      --update)
        runSelfUpdate
        exit
      ;;
      -h|--help)
        usage
        exit 0
      ;;
      -l|--local)
        BACKUP_TYPE="local"
        shift
      ;;
      -r|--remote)
        BACKUP_TYPE="remote"
        shift
      ;;
      -I|--id|--ctid)
        shift
        CUSTOM_CTID="$1"
        shift
      ;;
      -s|--sn|--snapshot)
        OPT="snapshots"
        shift
      ;;
      -S|--snl|--snapshots-latest)
        OPT="snapshots latest"
        shift
      ;;
      -t|--st|--stats)
        OPT="stats --mode raw-data"
        shift
      ;;
      -T|--stl|--stats-latest)
        OPT="stats latest --mode raw-data"
        shift
      ;;
      --ls)
        shift
        LIST_SNAPSHOT="$1"
        shift 2
        LIST_PATH="$1"
        if [[ -z "$LIST_SNAPSHOT" || -z "$LIST_PATH" ]]; then
          echo "Error: --ls requires 2 arguments: <snapshot> <path>" >&2
          exit 1
        fi
        OPT="ls ${LIST_SNAPSHOT} /${CUSTOM_CTID}${LIST_PATH}"
        break
      ;;
      --unlock)
        OPT="unlock"
        break
      ;;
      --check)
        OPT="check"
        break
      ;;
      --repair)
        OPT="repair snapshots"
        break
      ;;
    esac
  done
fi
}

function dsbackup_conf {
  if [ -f $LOCATION/etc/ds-backup.local.conf ]; then
    die "ERROR !!! ds-backup.local.conf is present. Please remove this file. All parameters must be set in ansible inventory"
  fi
  if [ -f $LOCATION/etc/ds-restic-backup.local.conf ]; then
    die "ERROR !!! ds-restic-backup.local.conf is present. Please remove this file. All parameters must be set in ansible inventory"
  fi
  local RESTIC="$(grep -c /srv/southbridge/bin/ds-restic-backup.sh /etc/cron.d/dsbackups)"
  if (( $RESTIC )); then
    . "$LOCATION/etc/ds-restic-backup.conf.dist"
    . "$LOCATION/etc/ds-restic-backup.conf"
    echo
    if [ -z "$REMOTE_BACKUP_HOSTS" ]; then
      echo "Backup disabled"
    else
      echo "Remote backup repo: $REMOTE_BACKUP_HOSTS"
    fi
  else
    . "$LOCATION/etc/ds-backup.conf.dist"
    . "$LOCATION/etc/ds-backup.conf"
    echo
    if [ -z "$REMOTE_HOSTS" ]; then
      echo "Backup disabled"
    else
      for REMOTE_HOST in $REMOTE_HOSTS; do
        echo  "Remote backup repo: $USERNAME@$REMOTE_HOST::$REMOTE_DIR/$REMOTEHOSTDIR"
      done
    fi
  fi

}

function mcbackup_conf {
  if [ -f $LOCATION/etc/mc-backup.local.conf ]; then
    die "ERROR !!! mc-backup.local.conf is present. Please remove this file. All parameters must be set in ansible inventory"
  fi
  if [ -f $LOCATION/etc/mc-restic-backup.local.conf ]; then
    die "ERROR !!! mc-restic-backup.local.conf is present. Please remove this file. All parameters must be set in ansible inventory"
  fi
  local RESTIC="$(grep -c /srv/southbridge/bin/mc-restic-backup.sh /etc/cron.d/mcbackups)"

  if (( $RESTIC )); then
    . "$LOCATION/etc/mc-restic-backup.conf.dist"
    . "$LOCATION/etc/mc-restic-backup.conf"
  else
    . "$LOCATION/etc/mc-backup.conf.dist"
    . "$LOCATION/etc/mc-backup.conf"
  fi

  [ ! -d "$CT_PRIVATE" ] && die "\$CT_PRIVATE directory does not exist. ($CT_PRIVATE)"
  [ "$CTIDS" = "*" ] && die "CTID in \$CT_PRIVATE directory not found."

  echo_ts "Conatiners on host:"
  for CTID in $CTIDS; do
    if [ -L "$CT_PRIVATE/$CTID" ]; then
      PATH_TO_CTID=$(/usr/bin/readlink -f "$CT_PRIVATE/$CTID")
    else
      PATH_TO_CTID="$CT_PRIVATE/$CTID"
    fi
    if [ -d "$PATH_TO_CTID" ]; then
      echo -en "$PATH_TO_CTID\t\t"
      re="\\b$CTID\\b"
      if [[ ! $CTIDS_EXCLUDE =~ $re ]]; then
        echo -n " backup"
        if [[ ! $CTIDS_EXCLUDE_LOCAL =~ $re ]] && [[ -n ${LOCAL_DIR} ]]; then
          echo -n " local"
        fi
        if [[ ! $CTIDS_EXCLUDE_REMOTE =~ $re ]]; then
          echo -n " remote"
        fi
      fi
      echo
    fi
  done
  echo
  echo "Local backup repo: ${LOCAL_DIR:-Disabled}"
  echo "Remote backup repo: $REMOTE_BACKUP_HOSTS"
}

function openvz_conf {
  if [ -f $LOCATION/etc/vz-backup.local.conf ]; then
    die "ERROR !!! vz-backup.local.conf is present. Please remove this file. All parameters must be set in ansible inventory"
  fi
  if [ -f $LOCATION/etc/vz-restic-backup.local.conf ]; then
    die "ERROR !!! vz-restic-backup.local.conf is present. Please remove this file. All parameters must be set in ansible inventory"
  fi
  local RESTIC="$(grep -c /srv/southbridge/bin/vz-restic-backup.sh /etc/cron.d/vzbackups)"

  if (( $RESTIC )); then
    . "$LOCATION/etc/vz-restic-backup.conf.dist"
    . "$LOCATION/etc/vz-restic-backup.conf"
    [ ! -d "$CT_PRIVATE" ] && die "\$CT_PRIVATE directory does not exist. ($CT_PRIVATE)"
    [ "$CTIDS" = "*" ] && die "CTID in \$CT_PRIVATE directory not found."

    echo "Conatiners on host:"
    for CTID in $CTIDS; do
      if [ -L "$CT_PRIVATE/$CTID" ]; then
        PATH_TO_CTID=$(/usr/bin/readlink -f "$CT_PRIVATE/$CTID")
      else
        PATH_TO_CTID="$CT_PRIVATE/$CTID"
      fi
      if [ -d "$PATH_TO_CTID" ]; then
        echo -en "$PATH_TO_CTID\t\t"
        re="\\b$CTID\\b"
        if [[ ! $CTIDS_EXCLUDE =~ $re ]]; then
          echo -n " backup"
          if [[ ! $CTIDS_EXCLUDE_LOCAL =~ $re ]] && [[ -n ${LOCAL_DIR} ]]; then
            echo -n " local"
          fi
          if [[ ! $CTIDS_EXCLUDE_REMOTE =~ $re ]]; then
            echo -n " remote"
          fi
        fi
        echo
      fi
    done
    echo
    echo "Local backup repo: ${LOCAL_DIR:-Disabled}"
    echo "Remote backup repo: $REMOTE_BACKUP_HOSTS"
  else
    . "$LOCATION/etc/vz-backup.conf.dist"
    . "$LOCATION/etc/vz-backup.conf"
    [ ! -d "$VZ_PRIVATE" ] && die "\$VZ_PRIVATE directory doesn't exist. ($VZ_PRIVATE)"
    [ "$VEIDS" = "*" ] && die "VEID in \$VZ_PRIVATE directory not found."

    echo "Conatiners on host:"
    for VEID in $VEIDS; do
      if [ -L "$VZ_PRIVATE/$VEID" ]; then
        PATH_TO_VEID=$(/usr/bin/readlink -f "$VZ_PRIVATE/$VEID")
      else
        PATH_TO_VEID="$VZ_PRIVATE/$VEID"
      fi
      if [ -d "$PATH_TO_VEID" ]; then
        echo -en "$PATH_TO_VEID\t\t"
        re="\\b$VEID\\b"
        if [[ ! $VEIDS_EXCLUDE =~ $re ]]; then
          echo -n " backup"
          if [[ ! $VEIDS_EXCLUDE_LOCAL =~ $re ]]; then
            echo -n " local"
          fi
          if [[ ! $VEIDS_EXCLUDE_REMOTE =~ $re ]]; then
            echo -n " remote"
          fi
        fi
        echo
      fi
    done
    echo
    echo "Local backup repo: ${LOCAL_DIR:-Disabled}"
    for REMOTE_HOST in ${REMOTE_HOSTS}; do
      echo "Remote backup repo: $USERNAME@$REMOTE_HOST::$REMOTE_DIR"
    done
  fi
}

function files_backup_conf {
  echo_ts "coming soon"
}

### DS Backup
function dsbackup {
  source ${LOCATION}/etc/ds-restic-backup.conf.dist
  source ${LOCATION}/etc/ds-restic-backup.conf
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
}

### MC Backup
function mcbackup {
  source ${LOCATION}/etc/mc-restic-backup.conf.dist
  source ${LOCATION}/etc/mc-restic-backup.conf
  if [ "$CUSTOM_CTID" == "all" ]; then
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
}

### VZ Backup
function openvz {
  source ${LOCATION}/etc/vz-restic-backup.conf.dist
  source ${LOCATION}/etc/vz-restic-backup.conf
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
}

### Files Backup
function filesbackup {
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
}

function main {
if [ -f /etc/cron.d/dsbackups ]; then
  echo_ts "############################################"
  echo_ts "VDS backup detected"
  if [ "$#" -eq 0 ]; then
    dsbackup_conf
  else
    read_args "$@"
    dsbackup "$@"
  fi
elif [ -f /etc/cron.d/mcbackups ]; then
  echo_ts "############################################"
  echo_ts "NSPAWN backup detected"
  if [ "$#" -eq 0 ]; then
    mcbackup_conf
  else
    read_args "$@"
    mcbackup "$@"
  fi
elif [ -f /etc/cron.d/vzbackups ]; then
  echo_ts "############################################"
  echo_ts "OpenVZ backup detected"
  if [ "$#" -eq 0 ]; then
    openvz_conf
  else
    read_args "$@"
    openvz "$@"
  fi
else
  echo_ts "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo_ts "Cron task for backup not detected"
fi

if [ -f /etc/cron.d/filebackups ]; then
  echo_ts "############################################"
  echo_ts "Files backup detected"
  if [ "$#" -eq 0 ]; then
    filesbackup_conf
  else
    read_args "$@"
    filesbackup "$@"
  fi
fi
}

main "$@"
