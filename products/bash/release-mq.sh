#!/bin/bash
#******************************************************************************
# Licensed Materials - Property of IBM
# (c) Copyright IBM Corporation 2020. All Rights Reserved.
#
# Note to U.S. Government Users Restricted Rights:
# Use, duplication or disclosure restricted by GSA ADP Schedule
# Contract with IBM Corp.
#******************************************************************************

#******************************************************************************
# PREREQUISITES:
#   - Logged into cluster on the OC CLI (https://docs.openshift.com/container-platform/4.4/cli_reference/openshift_cli/getting-started-cli.html)
#
# PARAMETERS:
#   -n : <namespace> (string), Defaults to "cp4i"
#   -r : <release_name> (string), Defaults to "demo"
#   -i : <image_name> (string)
#   -q : <qm_name> (string), Defaults to "QUICKSTART"
#   -t : optional flag to enable tracing
#   -a : <imageTag> (string) Defaults to "latest"
#
# USAGE:
#   With defaults values
#     ./release-mq.sh
#
#   Overriding the namespace and release-name
#     ./release-mq -n cp4i -r demo -i image-registry.openshift-image-registry.svc:5000/cp4i/mq-ddd -q mq-qm

function usage {
    echo "Usage: $0 -n <namespace> -r <release_name> -i <image_name> -q <qm_name> -a <imageTag>[-t]"
}

namespace="cp4i"
release_name="demo"
qm_name="QUICKSTART"
tracing="false"
imageTag="latest"
while getopts "n:r:i:q:a:t" opt; do
  case ${opt} in
    n ) namespace="$OPTARG"
      ;;
    r ) release_name="$OPTARG"
      ;;
    i ) image_name="$OPTARG"
      ;;
    q ) qm_name="$OPTARG"
      ;;
    a ) imageTag="$OPTARG"
      ;;
    t ) tracing=true
      ;;
    \? ) usage; exit
      ;;
  esac
done

if [ -z $image_name ]; then

cat << EOF | oc apply -f -
apiVersion: mq.ibm.com/v1beta1
kind: QueueManager
metadata:
  name: ${release_name}
  namespace: ${namespace}
spec:
  license:
    accept: true
    license: L-RJON-BN7PN3
    use: NonProduction
  queueManager:
    name: ${qm_name}
    storage:
      queueManager:
        type: ephemeral
  template:
    pod:
      containers:
        - env:
            - name: MQSNOAUT
              value: 'yes'
          name: qmgr
  version: 9.1.5.0-r2
  web:
    enabled: true
  tracing:
    enabled: ${tracing}
    namespace: ${namespace}
EOF

else

cat << EOF | oc apply -f -
apiVersion: mq.ibm.com/v1beta1
kind: QueueManager
metadata:
  name: ${release_name}
  namespace: ${namespace}
spec:
  license:
    accept: true
    license: L-RJON-BN7PN3
    use: NonProduction
  queueManager:
    image: ${image_name}
    imagePullPolicy: Always
    name: ${qm_name}
    storage:
      queueManager:
        type: ephemeral
  template:
    pod:
      containers:
        - env:
            - name: MQSNOAUT
              value: 'yes'
          name: qmgr
  version: 9.1.5.0-r2
  web:
    enabled: true
EOF

  # -------------------------------------- INSTALL JQ ---------------------------------------------------------------------

  echo -e "\n----------------------------------------------------------------------------------------------------------------------------------------------------------\n"

  echo -e "\nINFO: Checking if jq is pre-installed..."
  jqInstalled=false
  jqVersionCheck=$(jq --version)

  if [ $? -ne 0 ]; then
  jqInstalled=false
  else
    jqInstalled=true
  fi

  if [[ "$jqInstalled" == "false" ]]; then
    echo "INFO: JQ is not installed, installing jq..."
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
      echo "INFO: Installing on linux"
      wget -O jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
      chmod +x ./jq
    elif [[ "$OSTYPE" == "darwin"* ]]; then
      echo "INFO: Installing on MAC"
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
      brew install jq
    fi
  fi

  echo -e "\nINFO: Installed JQ version is $(./jq --version)"

  echo -e "\n----------------------------------------------------------------------------------------------------------------------------------------------------------\n"

  # -------------------------------------- CHECK FOR NEW IMAGE DEPLOYMENT STATUS ------------------------------------------

  echo "INFO: Image tag for '$release_name' is '$imageTag'"

  numberOfReplicas=1
  numberOfMatchesForImageTag=0
  time=0

  echo "INFO: Number of Replicas for $release_name should be $numberOfReplicas"

  # wait for 10 minutes for all replica pods to be deployed with new image
  while [ $numberOfMatchesForImageTag -ne $numberOfReplicas ]; do
    if [ $time -gt 10 ]; then
      echo "ERROR: Timed-out trying to wait for all $release_name demo pod(s) to be deployed with a new image containing the image tag '$imageTag-test'"
      echo -e "\n----------------------------------------------------------------------------------------------------------------------------------------------------------\n"
      exit 1
    fi

    numberOfMatchesForImageTag=0

    allCorrespondingPods=$(oc get pods -n $namespace | grep $release_name | grep 1/1 | grep Running | awk '{print $1}')
    for eachMQPod in $allCorrespondingPods
      do
        echo -e "\nINFO: For MQ demo pod '$eachMQPod':"
        imageInPod=$(oc get pod $eachMQPod -n $namespace -o json | ./jq -r '.spec.containers[0].image')
        echo "INFO: Image present in the pod '$eachMQPod' is '$imageInPod'"
        if [[ $imageInPod =~ "$imageTag-test" ]]; then
          echo "INFO: Image tag matches.."
          numberOfMatchesForImageTag=$((numberOfMatchesForImageTag + 1))
        else
          echo "INFO: Image tag '$imageTag-test' is not present in the image of the MQ demo pod '$mqDemoPod'"
        fi
    done

    echo -e "\nINFO: Total $release_name demo pods deployed with new image: $numberOfMatchesForImageTag"
    echo -e "\nINFO: All current $release_name demo pods are:\n"
    oc get pods -n $namespace | grep $release_name | grep 1/1 | grep Running
    if [[ $? -eq 1 ]]; then
      echo -e "No Ready and Running pods found for '$release_name' yet"
    fi
    if [[ $numberOfMatchesForImageTag != "$numberOfReplicas" ]]; then
      echo -e "\nINFO: Not all $release_name pods have been deployed with the new image having the image tag '$imageTag-test', retrying for upto 10 minutes for new $release_name demo pods te be deployed with new image. Waited ${time} minute(s)."
      sleep 60
    else
      echo -e "\nINFO: All $release_name demo pods have been deployed with the new image"
    fi
    time=$((time + 1))
    echo -e "\n----------------------------------------------------------------------------------------------------------------------------------------------------------"
  done

fi
