#!/bin/bash

PATH=/sbin:/usr/sbin:/usr/local/sbin:/bin:/usr/bin:/usr/local/bin

VERSION=v.2.1.4
#
# show_backup.sh $VERSION
#

SESS=$RANDOM
HN=$(hostname -f 2>/dev/null)
LOCATION=/srv/southbridge
OPT=""

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
    exi_tst 1;
}

function read_args() {
if [ -n "$1" ]; then
  while [ -n "$1" ]; do
    case "$1" in
      -v|--version)
        echo "$0 $VERSION"
        exit
      ;;
      -h|--help)
        echo "Use: $0 [GLOBAL OPTION]"
        echo "or"
        echo "Use: $0 [TYPE_BACKUP] [CTID] [OPTION]"
        echo ""
        echo "Type backup:"
        echo "-l         | --local               Local backup"
        echo "-r         | --remote              Remote backup"
        echo ""
        echo "Ctid:"
        echo "-id <ctid>               | --ctid <ctid>         Container name"
        echo ""
        echo "Option:"
        echo "-sn                      | --snapshots           All backups snapshots (default)"
        echo "-snl                     | --snapshots-latest    Latest backups snapshot"
        echo "-st                      | --stats               All backups stats"
        echo "-stl                     | --stats-latest        Stats for latest snapshot"
        echo "-ls <id snapshot> <path> |                       List files for <id snapshot> and <path>"
        echo "                         | --unlock              Unlock repo"
        echo "                         | --check               Check repo"
        echo "                         | --repair              Repair repo"
        echo ""
        echo "Global option:"
        echo "-h                       | --help                Help page"
        echo "-v                       | --version             Version"
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
      -id|--ctid)
        shift
        CUSTOM_CTID="$1"
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
    esac
    shift
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
