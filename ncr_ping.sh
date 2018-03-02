#!/usr/bin/env bash
#
#
#
set -o errexit   # force exit when a command fails
set -o pipefail  # when piping, set exit code to last non-zero in pipeline

timestamp=$(date +'%Y%m%d_%H%M%S')
my_ip=$(/usr/sbin/ifconfig -a | awk 'BEGIN { count=0; } { if ( $1 ~ /inet/ ) { count++; if( count==2 ) { print $2; } } }' )
my_ip_addr=$(echo "${my_ip}" | sed 's/\./_/g')

# Extract the remote ip addr from the netstat output. It has a port # appended, so it has to be trimmed.
netstat | grep ESTABLISHED | cut -d' ' -f 2 | cut -d'.' -f1-4 | while read -r ip_addr; do

    # Tells the world what we're doing
    echo "pinging ${ip_addr}"

    # create a dir name by using the remote ip address, but replacing dots with underscores
    ip_addr_dir=$(echo "${ip_addr}" | sed 's/\./_/g')

    # If the directory doesn't exist, create it.
    if ! [[ -d "/tmp/ping_tests/${ip_addr_dir}" ]]; then
        mkdir -p "/tmp/ping_tests/${ip_addr_dir}"
    fi

    #
    # Ping 3 times using a packet that is 100 bytes in length
    # From the output, get the following part of the line:
    #     round-trip (ms)  min/avg/max/stddev = 0.328/4.04/11.4/6.4
    #                                           ^^^^^^^^^^^^^^^^^^^
    # ...then replace the slashes with commas.
    # The "ping_result" var now contains "min,avg,max,stddev" values we can send to a csv file
    ping_result=$(ping -s ${ip_addr} 100 3 | grep round | cut -d' ' -f6 | sed 's/\//,/g')
    echo ${ping_result} > "/tmp/ping_tests/${ip_addr_dir}/${timestamp}.csv"
done

# Run netstat again to pickup certain session state information
netstat | ggrep -e 'TIME_WAIT' -e 'CLOSE_WAIT' -e 'SYN_SENT' - | while read -r line; do

    # Extract the remote ip addr ONLY from the netstat output. It has a port # appended, so it has to be trimmed.
    ip_remote=$( echo "${line}" | cut -d' ' -f 2 | cut -d'.' -f1-4 )

    # Get the protocol state, which is the last field in the output
    state_out=$(echo ${line} | awk '{print $NF}')

    # Put a comma-separated line to a report file.
    # The line contains a timestamp, our local ip addr, the remote ip addr, and the state
    echo "${timestamp},${my_ip_addr},${ip_remote},${state_out}" >> "/tmp/ping_tests/${my_ip_addr}_${timestamp}.csv"
done

# Finally we tar everything to a common file
tar cvf - /tmp/ping_tests | gzip -c > /tmp/ping_tests.tar.gz
