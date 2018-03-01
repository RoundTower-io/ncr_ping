#!/usr/bin/env bash
#
#
set -o errexit   # force exit when a command fails
set -o nounset   # force exit if we use undeclared variables
set -o pipefail  # when piping, set exit code to last non-zero in pipeline

timestamp=$(date +'%Y%m%d_%H%M%S')
netstat | grep ESTABLISHED | cut -d' ' -f 2 | cut -d'.' -f1-4 | while read -r ip_addr; do
  ping_result = $(ping -s ${ip_addr} 100 3 | grep round | cut -d' ' -f6 | sed 's/\//,/g')
  echo ${ping_result} > /tmp/${ip_addr}_${timestamp}.txt
done