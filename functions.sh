#!/bin/bash

# This script aims to adhere to the Google Shell Style Guide: https://google.github.io/styleguide/shellguide.html

# Full system path to the directory containing this file, with trailing slash.
# This line determines the location of the script even when called from a bash
# prompt in another directory (in which case `pwd` will point to that directory
# instead of the one containing this script).  See http://stackoverflow.com/a/246128
MYDIR="$( cd -P "$( dirname "$(readlink -f "${BASH_SOURCE[0]}")" )" && pwd )/"

# Source config file or exit.
if [ -e "${MYDIR}/config.sh" ]; then
  source "${MYDIR}/config.sh"
else
  echo "Could not find required config file at ${MYDIR}/config.sh. Exiting."
  exit 1
fi


# Track my pid as a way to kill on fatal errors. Not ideal (sub-shells won't be handled properly).
# see https://stackoverflow.com/a/9894126
PID=$$;

# Globals;
# Log file for auto-generated passwords.
PASSWORDLOG="";

# Print informative message to STDERR.
function info {
  >&2 echo "$1";
}

# Print fatal error to STDERR and kill script.
function fatal {
  info "FATAL ERROR: $1";
  kill -s TERM $PID;
}

# Log a message to the password log file.
function logpassword {
  info "Logging to $PASSWORDLOG: $1";
  echo "$1" >> "$PASSWORDLOG";
}

# Print a progress dot to STDERR.
function progress {
  >&2 echo -n "."
}

# Create a linode with the given parameters.
function create {

  local LABEL="$1";
  local REGION="$2";
  local TYPE="$3";
  local IMAGE="$4";
  local ROOTPASS="$5";

  info "Attempt create linode type='$TYPE' region='$REGION' image='$IMAGE' --label='$LABEL'";
  # Create the linode and store its id.
  LINODEID=$(linode-cli linodes create --text --format=id --no-headers --type="$TYPE" --region="$REGION" --image="$IMAGE" --root_pass="$ROOTPASS" --label="$LABEL" --authorized_keys="$(cat /home/as/.ssh/id_rsa.pub)");

  # Report status; die if creation failed.
  if [[ -n "$LINODEID" ]]; then
    info "Created linode, ID: $LINODEID; label: $LABEL"
  else
    # fatal "Linode creation failed. See notes above."
    fatal "Linode creation failed. See notes above."
  fi

  echo "$LINODEID";
}

# For a given linode (by id), retrieve a particalar value from the `linode-cli linodes list` api.
function getlinodevalue {
  local NAME="$1"
  local LINODEID="$2"
  linode-cli linodes list --id="$LINODEID" --format="$NAME" --text --no-headers;
}

# Wait (up to $WAITTIME seconds) for the given linode to have a given status.
function waitforstatus {
  local TARGETSTATUS="$1";
  local LINODEID="$2";
  local LIVESTATUS="";

  local TIMEOUTTIME=$(( $(date +%s) + $WAITTIME));

  info "Waiting for $TARGETSTATUS status on linode $LINODEID ...";
  while [[ "$LIVESTATUS" != "$TARGETSTATUS" ]]; do
    if [[ $(date +%s) -ge $TIMEOUTTIME ]]; then
      fatal "waitforstatus timed out waiting for $TARGETSTATUS status on linode $LINODEID (waited $WAITTIME seconds)";
    fi
    LIVESTATUS=$(getlinodevalue "status" "$LINODEID");
    if [[ "$LIVESTATUS" != "$TARGETSTATUS" ]]; then
      # print a dot to indicate passage of time.
      progress;
      # wait 1 second before trying again.
      sleep 1;
   fi
  done;
  info "Linode $LINODEID has achieved status $LIVESTATUS.";
}

# Generate a password based on values from random.org. Log the password, using the given label, in the password log file.
# generatepassword $label.
function generatepassword {
  local PASS=$(curl -s "https://www.random.org/strings/?num=2&len=20&digits=on&upperalpha=on&loweralpha=on&unique=on&format=plain&rnd=new" | tr -d '\n' 2>/dev/null);
  logpassword "$1: $PASS";
  echo "$PASS";
}

# Create a log file for any purpose using the given base-name, with template "/tmp/$1.XXXXXXXX"
function createlogfile {
  mktemp "/tmp/$1.XXXXXXXX";
}

# Create a config file to be used by setup scripts. Return the full path of that file.
function createsetupconfig {
  local LINODEID="$LINODEID";
  LINODEID="$1";
  SERVERNAME="$2";
  USER="$3";
  DOMAINNAME="$4";
  ADMINUSERNAME="$CREATE_ADMINUSERNAME";

  logpassword "admin_user_name: $ADMINUSERNAME";
  logpassword "customer_user_name: $USER";

  LOCALCONFIGFILE=$(mktemp "/tmp/linode_setup_config_${LINODEID}.sh.XXXXXXX");

  # Copy config from $PROVISION_SCRIPTS_DIR into new file; this will provide
  # default config vars; we'll then append to it in order to override those defaults.
  cat "${PROVISION_SCRIPTS_DIR}/config.sh" > "$LOCALCONFIGFILE";
  echo "
## End of default configs (above). Start of install-specific configs (below).
" >> "$LOCALCONFIGFILE";
  echo "# Used by setup.sh" >> "$LOCALCONFIGFILE";
  echo "ADMINUSERNAME=\"$ADMINUSERNAME\";" >> "$LOCALCONFIGFILE";
  echo "ADMINUSERPASS=\"$(generatepassword admin_user_pass)\";" >> "$LOCALCONFIGFILE";
  echo "SERVERNAME=\"$SERVERNAME\";" >> "$LOCALCONFIGFILE";
  echo "MYSQLROOTPASS=\"$(generatepassword mysql_root_pass)\";" >> "$LOCALCONFIGFILE";
  echo "" >> "$LOCALCONFIGFILE";
  echo "# Used by customer_setup.sh" >> "$LOCALCONFIGFILE";
  echo "USER=\"$USER\";" >> "$LOCALCONFIGFILE";
  echo "PASS=\"$(generatepassword customer_user_pass)\";" >> "$LOCALCONFIGFILE";
  echo "DOMAINNAME=\"$DOMAINNAME\";" >> "$LOCALCONFIGFILE";
  echo "MYSQL_CUSTOMER_USER=\"$USER\";" >> "$LOCALCONFIGFILE";
  echo "MYSQL_CUSTOMER_PASS=\"$(generatepassword mysql_customer_pass)\";" >> "$LOCALCONFIGFILE";
  echo "PROVISIONING_NOTIFY_EMAIL=\"$PROVISIONING_NOTIFY_EMAIL\";" >> "$LOCALCONFIGFILE";

  echo "$LOCALCONFIGFILE";
}

# Wait for ssh to be active on the given linode
# waitforssh $user $host
function waitforssh {
  # Ensure any existing key for this new server IP is removed. We've seen cases
  # in testing where IP addresses are re-used.
  ssh-keygen -R "$2"

  local TIMEOUTTIME=$(( $(date +%s) + $WAITTIME));

  info "Waiting for ssh active on $1@$2 ...";
  while [[ $(date +%s) -le $TIMEOUTTIME ]]; do
    # Option "StrictHostKeyChecking no" will add server key to local store without checking.
    # ":" is bash no-op.
    ssh -q -o "StrictHostKeyChecking no" "$1"@"$2" ":" > /dev/null 2>&1;
    if [[ $? -eq 0 ]]; then
      info "ssh connection successful for $1@$2";
      return;
    fi;
    progress;
    sleep 1;
  done
  fatal "Timeout exceeded waiting on ssh connection for $1@$2";
}

# Ensure that the required values from config.sh are all populated.
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