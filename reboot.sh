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

# Source functions file or exit.
if [ -e "${MYDIR}/functions.sh" ]; then
  source "${MYDIR}/functions.sh"
else
  echo "Could not find required functions file at ${MYDIR}/functions.sh. Exiting."
  exit 1
fi

validateconfig;

# Print usage.
function usage {
  echo "Usage: $0 LABEL"
  echo "  Reboot a linode with the given LABEL."
  echo "  LABEL: The label (as seen at https://cloud.linode.com/linodes of the linode to reboot."
  echo
  echo "See also: config.sh in $MYDIR.";
  exit 1;
}

LABEL=$1;

# Just in case, test all required args again.
MISSING_REQUIRED="";
for i in LABEL; do
  if [[ -z "${!i}" ]]; then
    MISSING_REQUIRED=1;
    info "Missing required value for $i";
  fi;
  if [[ -n "$MISSING_REQUIRED" ]]; then
    # We have missing required values; print usage (which will end execution).
    usage;
  fi
done;

# Get the ID for the compute instance matching $LABEL
ID=$(linode-cli linodes list --label $LABEL --text | tail -n+2 | awk '{print $1}');

RE='^[0-9]+$';
if [[ -z "$ID" || ! $ID =~ $RE ]]; then
  fatal "No linode compute instance found for label '$LABEL'";
fi

# Send the api request to reboot, and store output in variable.
output=$(linode-cli linodes reboot $ID --debug --text 2>&1);

# Test output for success and report appropriately.
if [[ -z $(echo "$output" | grep -P '^< HTTP/1.1 200 OK$') ]]; then 
  fatal "Linode CLI returned non-success code for reboot.";
else
  info "Rebooted linode $ID ($LABEL)";
fi

exit 0;
