#!/usr/bin/env bash
#
#
set -o errexit   # force exit when a command fails
set -o pipefail  # when piping, set exit code to last non-zero in pipeline

timestamp=$(date +'%Y%m%d_%H%M%S')

netstat | grep ESTABLISHED | cut -d' ' -f 2 | cut -d'.' -f1-4 | while read -r ip_addr; do
    echo "pinging ${ip_addr}"
    ip_addr_dir=$(echo "${ip_addr}" | sed 's/\./_/g')
    if ! [[ -d "/tmp/ping_tests/${ip_addr_dir}" ]]; then
        mkdir -p "/tmp/ping_tests/${ip_addr_dir}"
    fi
    ping_result=$(ping -s ${ip_addr} 100 3 | grep round | cut -d' ' -f6 | sed 's/\//,/g')
    echo ${ping_result} > "/tmp/ping_tests/${ip_addr_dir}/${timestamp}.txt"
done

tar cvf - /tmp/ping_tests | gzip -c > /tmp/ping_tests.tar.gz
