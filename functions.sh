#!/bin/bash

# This script aims to adhere to the Google Shell Style Guide: https://google.github.io/styleguide/shellguide.html

# Full system path to the directory containing this file, with trailing slash.
# This line determines the location of the script even when called from a bash
# prompt in another directory (in which case `pwd` will point to that directory
# instead of the one containing this script).  See http://stackoverflow.com/a/246128
MYDIR="$( cd -P "$( dirname "$(readlink -f "${BASH_SOURCE[0]}")" )" && pwd )/"

# Source config file or exit.
if [ -e ${MYDIR}/config.sh ]; then
  source ${MYDIR}/config.sh
else
  echo "Could not find required config file at ${MYDIR}/config.sh. Exiting."
  exit 1
fi


# Track my pid as a way to kill on fatal errors. Not ideal (sub-shells won't be handled properly).
# see https://stackoverflow.com/a/9894126
PID=$$;

# Globals
PASSWORDLOG="";

function info {
  >&2 echo "$1";
}

function fatal {
  >&2 echo "FATAL ERROR: $1";
  kill -s TERM $PID;
}

function logpassword {
  info "Logging to $PASSWORDLOG: $1";
  echo "$1" >> $PASSWORDLOG;  
}

function progress {
  >&2 echo -n "."
}

function create {

#  num=$#
#  for order in $(seq 1 ${num}); do # `$(...)` is better than backticks
#    info "create: $order: ${!order}"               # indirection
#  done

  local LABEL="$1";
  local REGION="$2";
  local TYPE="$3";
  local IMAGE="$4";
  local ROOTPASS="$5";
  
  info "Attempt create linode type='$TYPE' region='$REGION' image='$IMAGE' --label='$LABEL'";
  LINODEID=$(linode-cli linodes create --text --format=id --no-headers --type="$TYPE" --region="$REGION" --image="$IMAGE" --root_pass="$ROOTPASS" --label="$LABEL" --authorized_keys="$(cat /home/as/.ssh/id_rsa.pub)")
  if [[ -n "$LINODEID" ]]; then
    info "Created linode, ID: $LINODEID; label: $LABEL"
  else 
    # fatal "Linode creation failed. See notes above."
    fatal "Linode creation failed. See notes above."
    
  fi

  echo $LINODEID;
}

function getlinodevalue {
  local NAME="$1"
  local LINODEID="$2"
  linode-cli linodes list --id=$LINODEID --format="$NAME" --text --no-headers;
}

function waitforstatus {
  local TARGETSTATUS="$1";
  local LINODEID="$2";
  local LIVESTATUS="";

  local TIMEOUTTIME=$(( $(date +%s) + $WAITTIME));
  
  info "Waiting for $TARGETSTATUS status on linode $LINODEID ...";
  while [[ "$LIVESTATUS" != "$TARGETSTATUS" ]]; do
    if [[ $(date +%s) -ge $TIMEOUTTIME ]]; then
      fatal "waitforstatus timed out waiting for $TARGETSTATUS status on linode $LINODEID";
    fi
    LIVESTATUS=$(getlinodevalue "status" $LINODEID);
    if [[ "$LIVESTATUS" != "$TARGETSTATUS" ]]; then
      progress;
      sleep 1; 
   fi
  done
  info "Linode $LINODEID has achieved status $LIVESTATUS.";
}

function generatepassword {
  local PASS=$(curl -s "https://www.random.org/strings/?num=2&len=20&digits=on&upperalpha=on&loweralpha=on&unique=on&format=plain&rnd=new" | tr -d '\n' 2>/dev/null);
  logpassword "$1: $PASS"; 
  echo $PASS;
}

function createlogfile {
  echo $(mktemp "/tmp/$1.XXXXXXXX");
}

function createsetupconfig {
  local LINODEID="$LINODEID";
  LINODEID="$1";
  SERVERNAME="$2";
  USER="$3";
  DOMAINNAME="$4";
  ADMINUSERNAME="$CREATE_ADMINUSERNAME";

  logpassword "adminuser_name: $ADMINUSERNAME";
  logpassword "customeruser_name: $USER";

  LOCALCONFIGFILE=$(mktemp "/tmp/linode_setup_config_${LINODEID}.sh.XXXXXXX");

  echo "# Used by setup.sh" >> $LOCALCONFIGFILE;
  echo "ADMINUSERNAME=\"$ADMINUSERNAME\";" >> $LOCALCONFIGFILE;
  echo "ADMINUSERPASS=\"$(generatepassword adminuser_pass)\";" >> $LOCALCONFIGFILE;
  echo "SERVERNAME=\"$SERVERNAME\";" >> $LOCALCONFIGFILE;
  echo "MYSQLROOTPASS=\"$(generatepassword mysql_root)\";" >> $LOCALCONFIGFILE;
  echo "" >> $LOCALCONFIGFILE;
  echo "# Used by customer_setup.sh" >> $LOCALCONFIGFILE;
  echo "USER=\"$USER\";" >> $LOCALCONFIGFILE;
  echo "PASS=\"$(generatepassword customeruser_pass)\";" >> $LOCALCONFIGFILE;
  echo "DOMAINNAME=\"$DOMAINNAME\";" >> $LOCALCONFIGFILE;

  echo $LOCALCONFIGFILE;
}

function waitforssh {
  # user = $1
  # host = $2

  # Ensure any existing key for this new server IP is removed. We've seen cases
  # in testing where IP addresses are re-used.
  ssh-keygen -R $2

  local TIMEOUTTIME=$(( $(date +%s) + $WAITTIME));
  
  info "Waiting for ssh active on $1@$2 ...";
  while [[ $(date +%s) -le $TIMEOUTTIME ]]; do
    # Option "StrictHostKeyChecking no" will add server key to local store without checking.
    # ":" is bash no-op.
    ssh -o "StrictHostKeyChecking no" $1@$2 ":"
    if [ $? -eq 0 ]; then
      info "ssh connection successful for $1@$2";
      return;
    fi
  done
  fatal "Timeout exceeded waiting on ssh connection for $1@$2";
}

function validateconfig {
  # Ensure complete config:
  MISSING_CONFIG="";
  for i in CREATE_ADMINUSERNAME CREATE_IMAGE PROVISION_SCRIPTS_DIR WAITTIME; do
    if [[ -z "${!i}" ]]; then
      MISSING_CONFIG=1;
      info "Missing required configuration value: $i";
    fi;
  done;
  if [[ -n "$MISSING_CONFIG" ]]; then
    fatal "Missing required configurations in ${MYDIR}/config.sh"
  fi;
}