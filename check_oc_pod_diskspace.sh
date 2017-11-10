#!/bin/bash

# A Munro: 9 Nov 2017: Openshift check pod disk space
# Login to an openshift project using a token and check the pods disk space.
# Can limit the pods checked using -p arg.

Usage() {
  echo $(basename $0):
  echo -e "\t-h - help."
  echo -e "\t-t <token>   - service account token used for login."
  echo -e "\t-n <project> - openshift project|namespace."
  echo -e "\t-o <cluster-url> - openshift cluster url; eg https://127.0.0.1:8443"
  echo -e "\t-w - Warning disk usage % threshold. default 70."
  echo -e "\t-c - Critical disk usage % threshold. default 90."
  echo -e "\t-p - Pod name pattern match. default none: all pods."
  echo -e "\t-l - Remain logged in to openshift."
  echo -e "\t-d - Switch on debugging."
  echo ""
}

Exit() {
  [ ! -z "$pat" ] && pat=" (pod/s re \"$pat\")"
  [ ! -z "$project" ] && {
    [ $1 -eq $ok ] && echo "OK pod diskspace project $project$pat."
    [ $1 -eq $warn ] && echo "WARNING pod diskspace project $project$pat."
    [ $1 -eq $crit ] && echo "CRITICAL pod diskspace project $project$pat."
    [ $1 -eq $unk ] && echo "UNKNOWN pod diskspace project $project$pat."
  }

  IFS=$'\n'
  for m in ${mess[@]}
  do
    echo $m
  done
  unset IFS

  exit $1
}

# Main

ok=0
warn=1
crit=2
unk=3

logout=true
debug=false

# Defaults:
podw=70
podc=90

! which oc > /dev/null 2>&1 && {
  echo "oc binary not in the path. It can be downloaded from https://github.com/openshift/origin/releases."
  exit $unk
}

while getopts "ht:n:w:c:o:ldp:" opt; do
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
    p) pat=$OPTARG
      ;;
    l) logout=false
      ;;
    d) debug=true
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
  Exit $unk
}

oc project $project > /dev/null 2>&1 || {
  echo "Error switching to project $project"
  [ $logout = "true" ] && oc logout
  Exit $unk
}

status=0
msg=()

for p in $(oc get po --no-headers=true -o custom-columns=NAME:.metadata.name)
do
  [[ $p =~ $pat ]] || continue
  [ $debug = "true" ] && echo $p # debug

  IFS=$'\n' 
# Lowest common denominator df -P; even works with busybox df!!! Apparently df always rounds up.
  for d in $(oc rsh $p df -P|awk '!/^(Filesystem|tmpfs|shm|udev|cgmfs)/ && $6 !~ /^(\/etc|\/run|\/dev)/ {p=$3*100/$2; printf("%1.0f %s\n", (p == int(p) ? p : int(p)+1),$6)}'|tr -d '\r')
  do
    unset IFS
    f=($d)
    f[0]=${f[0]%%%} # Remove %
    [ $debug = "true" ] &&echo "Disk ${f[0]}% ${f[1]}" # debug

    [ ${f[0]} -ge $podc ] && {
      mess+=("CRITICAL pod $p filesystem ${f[1]} is ${f[0]}% used and >= threshold ${podc}%.")
      [ $crit -gt $status ] && status=$crit
      continue
    }

    [ ${f[0]} -ge $podw ] && {
      mess+=("WARNING pod $p filesystem ${f[1]} is ${f[0]}% used and >= threshold ${podw}%.")
      [ $warn -gt $status ] && status=$warn
      continue
    }

  done
done

[ $logout = "true" ] && oc logout > /dev/null 2>&1

Exit $status
