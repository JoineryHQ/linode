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

# Source functions file or exit.
if [ -e ${MYDIR}/functions.sh ]; then
  source ${MYDIR}/functions.sh
else
  echo "Could not find required functions file at ${MYDIR}/functions.sh. Exiting."
  exit 1
fi

validateconfig;


function usage {
  echo "Usage: $0 [options]"
  echo "  Create a linode with image $CREATE_IMAGE, and peform hosting setup on that linode."
  echo "  Will prompt for required options if not provided."
  echo "  Options:"
  echo "    -h: (Optional, null) Display this help message."
  echo "    -l: (Required, string) linode label"
  echo "    -r: (Required, string) linode region; reference:"
  echo "        https://www.linode.com/docs/api/regions/#regions-list"
  echo "    -t: (Required, string) linode type; reference:"
  echo "        https://www.linode.com/docs/api/linode-types/#types-list"
  echo "    -s: (Required, string) Server/host name"
  echo "    -u: (Required, string) Customer user name"
  echo "    -d: (Required, string) Customer domain name"
  echo "    -y: (Optional, null) If given, script will not prompt for confirmation"
  echo "        before creating the linode."
  echo 
  echo "See also: config.sh in $MYDIR.";
  exit 1;
}

while getopts l:r:t:s:u:d:y FLAG; do
  case $FLAG in
    l)
      LABEL=$OPTARG
      ;;
    r)
      REGION=$OPTARG
      ;;
    t)
      TYPE=$OPTARG
      ;;
    s)
      SERVERNAME=$OPTARG
      ;;
    u)
      USERNAME=$OPTARG
      ;;
    d)
      DOMAINNAME=$OPTARG
      ;;
    h)
      usage;
      ;;
    y)
      SKIP_CONFIRMATION=1;
      ;;
    \?) #unrecognized option - show help
      info "Option -$OPTARG not allowed."
      usage;
      ;;
  esac
done

declare -A OPTIONS;
OPTIONS[LABEL]="-"
OPTIONS[REGION]="regions list"
OPTIONS[TYPE]="linodes types"
OPTIONS[SERVERNAME]="-"
OPTIONS[USERNAME]="-"
OPTIONS[DOMAINNAME]="-"
for i in LABEL REGION TYPE SERVERNAME USERNAME DOMAINNAME ; do
  while [[ -z "${!i}" ]]; do
    NOTE="";
    if [[ "${OPTIONS[$i]}" != "-" ]]; then
      info "========= Options for $i: ";
      info "========= (For more info run: linode-cli ${OPTIONS[$i]})";
      OPTFILE=$(mktemp);
      linode-cli ${OPTIONS[$i]} --text --no-headers --format=id | sort >> $OPTFILE;
      cat --number $OPTFILE;
      read -p "Please provide $i (required) (Enter the number of your selection from options above): " INPUT;
      printf -v "$i" '%s' $(sed "${INPUT}q;d" $OPTFILE);
    else
      read -p "Please provide $i (required): " $i;
    fi;
    if [[ -z "${!i}" ]]; then
      info "$i is a required value. Trying again...";
    fi;
  done;
done;

# Just in case, test all required args again.
MISSING_REQUIRED="";
for i in LABEL REGION TYPE SERVERNAME USERNAME DOMAINNAME ; do
  if [[ -z "${!i}" ]]; then
    MISSING_REQUIRED=1;
    info "Missing required value for $i";
  fi;
  if [[ -n "$MISSING_REQUIRED" ]]; then
    usage;
  fi
done;

# Notify user we're about to begin.
info "Beginning linode creation with these values:"
for i in LABEL REGION TYPE SERVERNAME USERNAME DOMAINNAME ; do
  info "$i ${!i}";
done
info "IMAGE: $CREATE_IMAGE"

# If not SKIP_CONFIRMATION, get confirmation before continuing:
if [[ -z "$SKIP_CONFIRMATION" ]]; then
  read -p "Strike ENTER to continue or CTRL+C to abort." continue;
  info "Continuing."
fi;

PASSWORDLOG=$(createlogfile "linode_passwords");
info "Password log created at $PASSWORDLOG";

#LINODEID=$(create "$LABEL" "$REGION" "$TYPE" $CREATE_IMAGE $(generatepassword "root"));
LINODEID=34133621;
waitforstatus "running" $LINODEID;
IP=$(getlinodevalue ipv4 $LINODEID);
info "IP: $IP";
#waitforssh root $IP

CONFIGFILE=$(createsetupconfig "$LINODEID" "$SERVERNAME" "$USERNAME" "$DOMAINNAME");
info "configfile: $CONFIGFILE";
cat $CONFIGFILE;


scp ${PROVISION_SCRIPTS_DIR}/*setup*sh root@$IP:.
scp $CONFIGFILE root@$IP:config.sh
ssh root@$IP ls -la

# Run setup scripts in background (ref https://stackoverflow.com/a/2831449).
info "Starting setupall.sh on $IP."
ssh root@$IP "sh -c 'nohup ./setupall.sh > /dev/null 2>&1 &'"

info "Passwords in $PASSWORDLOG";
