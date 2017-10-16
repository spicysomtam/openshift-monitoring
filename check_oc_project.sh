#!/bin/bash

# A Munro: 6 Oct 2017: Openshift check a project nagios plugin. 
# Should work with Sensu, Icinga2 or anything else that supports nagios plugins.
# The idea is we don't have full cluster admin rights, but we do have rights on a project.
# Thus login to project and check its ok. Primarily check the state of the pods.

Usage() {
  echo $(basename $0):
  echo -e "\t-h - help."
  echo -e "\t-t <token>   - service account token used for login."
  echo -e "\t-n <project> - openshift project|namespace."
  echo -e "\t-o <cluster-url> - openshift cluster url; eg https://127.0.0.1:8443"
  echo -e "\t-w - No. pod restarts warning threshold. default 5."
  echo -e "\t-c - No. pod restarts critical threshold. default 10."
  echo -e "\t-l - Remain logged in to openshift."
  echo ""
}

Exit() {
  #[ $status -ne $ok ] && oc get po|awk '!/^NAME/ && (/0\/1/ || !/Running/ || $4 != "0") {print "po/"$0}'
  [ ! -z "$project" ] && {
    [ $1 -eq $ok ] && echo "OK PROJECT $project."
    [ $1 -eq $warn ] && echo "WARNING PROJECT $project."
    [ $1 -eq $crit ] && echo "CRITICAL PROJECT $project."
    [ $1 -eq $unk ] && echo "UNKNOWN PROJECT $project."
  }

  exit $1
}

# Main

ok=0
warn=1
crit=2
unk=3

logout=true

# Defaults:
podw=5
podc=10

! which oc > /dev/null 2>&1 && {
  echo "oc binary not in the path. It can be downloaded from https://github.com/openshift/origin/releases."
  exit $unk
}

while getopts "ht:n:w:c:o:l" opt; do
  case $opt in
    h) Usage
       Exit 0
      ;;
    t) token=$OPTARG
      ;;
    n) project=$OPTARG
      ;;
    w) podw=$OPTARG
      ;;
    c) podc=$OPTARG
      ;;
    o) cluster=$OPTARG
      ;;
    l) logout=false
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      Usage
      Exit $unk
      ;;
  esac
done

[ -z "$token" -o -z "$cluster" -o -z "$project" ] && {
  echo "Missing args."
  Usage
  Exit $unk
}

[ $podw -gt $podc ] && {
  echo "Warning is > critical!"
  Exit $unk
}

oc login $cluster --token="$token" --insecure-skip-tls-verify=true > /dev/null 2>&1 || {
  echo "Login to $cluster failed."
  Exit $crit
}

oc project $project > /dev/null 2>&1 || {
  echo "Error switching to project $project"
  oc logout
  Exit $crit
}

#oc get po # debug

status=0
IFS=$'\n'

for l in $(oc get po)
do
  [[ $l =~ ^NAME ]] && continue
  unset IFS
  a=($l)


  [ ${a[3]} -ge $podc ] && {
    echo "CRITICAL po/${a[0]} has restarted ${a[3]} times (>= CRITICAL threshold $podc)."
    [ $crit -gt $status ] && status=$crit
  }

  [ ${a[3]} -lt $podc -a ${a[3]} -ge $podw ] && {
    echo "WARNING po/${a[0]} has restarted ${a[3]} times (>= WARNING threshold $podw)."
    [ $warn -gt $status ] && status=$warn
  }

# Skip some checks if the pod life is less than a minute; prevents misreports
  [[ ${a[4]} =~ s ]] && continue

  [ ${a[2]} != "Running" ] && {
    echo "CRITICAL po/${a[0]} is state ${a[2]}."
    [ $crit -gt $status ] && status=$crit
  }

  [ ${a[1]} != "1/1" ] && {
    echo "CRITICAL po/${a[0]} is failing health checks."
    [ $crit -gt $status ] && status=$crit
  }
done

[ $logout = "true" ] && oc logout > /dev/null 2>&1

Exit $status
