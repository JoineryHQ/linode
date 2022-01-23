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

# Wait timeout in seconds.
WAITTIME=100;

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
  info $LIVESTATUS;
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
  ADMINUSERNAME="$DEFAULT_ADMINUSERNAME";

  LOCALCONFIGFILE=$(mktemp "/tmp/linode_setup_config_${LINODEID}.sh.XXXXXXX");

  echo "# Used by setup.sh" >> $LOCALCONFIGFILE;
  echo "ADMINUSERNAME=\"$ADMINUSERNAME\";" >> $LOCALCONFIGFILE;
  echo "ADMINUSERPASS=\"$(generatepassword admin_user)\";" >> $LOCALCONFIGFILE;
  echo "SERVERNAME=\"$SERVERNAME\";" >> $LOCALCONFIGFILE;
  echo "MYSQLROOTPASS=\"$(generatepassword mysql_root)\";" >> $LOCALCONFIGFILE;
  echo "" >> $LOCALCONFIGFILE;
  echo "# Used by customer_setup.sh" >> $LOCALCONFIGFILE;
  echo "USER=\"$USER\";" >> $LOCALCONFIGFILE;
  echo "PASS=\"$(generatepassword user_pass)\";" >> $LOCALCONFIGFILE;
  echo "DOMAINNAME=\"$DOMAINNAME\";" >> $LOCALCONFIGFILE;

  echo $LOCALCONFIGFILE;
}


PASSWORDLOG=$(createlogfile "linode_passwords");
info "Password log created at $PASSWORDLOG";

LINODEID=$(create "0001-test" "us-east" "g6-nanode-1" "linode/ubuntu18.04" $(generatepassword "root"));
waitforstatus "running" $LINODEID;
IP=$(getlinodevalue ipv4 $LINODEID);
echo "IP: $IP";
# Add server key to local store; ":" is bash no-op.
ssh -o "StrictHostKeyChecking no" root@$IP ":";

CONFIGFILE=$(createsetupconfig "1234" theserver theuser thedomainname);
echo "configfile: $CONFIGFILE";
cat $CONFIGFILE;

echo "Passwords in $PASSWORDLOG";


# Region for operations.  Choices are:
#  1 - ap-west
#  2 - ca-central
#  3 - ap-southeast
#  4 - us-central
#  5 - us-west
#  6 - us-southeast
#  7 - us-east
#  8 - eu-west
#  9 - ap-south
#  10 - eu-central
#  11 - ap-northeast

# Type of Linode to deploy.  Choices are:
#  1 - g6-nanode-1
#  2 - g6-standard-1
#  3 - g6-standard-2
#  4 - g6-standard-4
#  5 - g6-standard-6
#  6 - g6-standard-8
#  7 - g6-standard-16
#  8 - g6-standard-20
#  9 - g6-standard-24
#  10 - g6-standard-32
#  11 - g7-highmem-1
#  12 - g7-highmem-2
#  13 - g7-highmem-4
#  14 - g7-highmem-8
#  15 - g7-highmem-16
#  16 - g6-dedicated-2
#  17 - g6-dedicated-4
#  18 - g6-dedicated-8
#  19 - g6-dedicated-16
#  20 - g6-dedicated-32
#  21 - g6-dedicated-48
#  22 - g6-dedicated-50
#  23 - g6-dedicated-56
#  24 - g6-dedicated-64
#  25 - g1-gpu-rtx6000-1
#  26 - g1-gpu-rtx6000-2
#  27 - g1-gpu-rtx6000-3
#  28 - g1-gpu-rtx6000-4

# Image to deploy to new Linodes.  Choices are:
#  1 - linode/almalinux8
#  2 - linode/alpine3.11
#  3 - linode/alpine3.12
#  4 - linode/alpine3.13
#  5 - linode/alpine3.14
#  6 - linode/alpine3.15
#  7 - linode/arch
#  8 - linode/centos7
#  9 - linode/centos8
#  10 - linode/centos-stream8
#  11 - linode/centos-stream9
#  12 - linode/debian10
#  13 - linode/debian11
#  14 - linode/debian9
#  15 - linode/fedora33
#  16 - linode/fedora34
#  17 - linode/fedora35
#  18 - linode/gentoo
#  19 - linode/debian11-kube-v1.20.7
#  20 - linode/debian9-kube-v1.20.7
#  21 - linode/debian11-kube-v1.21.1
#  22 - linode/debian9-kube-v1.21.1
#  23 - linode/debian11-kube-v1.22.2
#  24 - linode/debian9-kube-v1.22.2
#  25 - linode/opensuse15.2
#  26 - linode/opensuse15.3
#  27 - linode/rocky8
#  28 - linode/slackware14.2
#  29 - linode/ubuntu16.04lts
#  30 - linode/ubuntu18.04
#  31 - linode/ubuntu20.04
#  32 - linode/ubuntu21.04
#  33 - linode/ubuntu21.10
#  34 - linode/alpine3.10
#  35 - linode/alpine3.9
#  36 - linode/centos6.8
#  37 - linode/debian8
#  38 - linode/fedora31
#  39 - linode/fedora32
#  40 - linode/opensuse15.1
#  41 - linode/slackware14.1
#  42 - linode/ubuntu20.10
