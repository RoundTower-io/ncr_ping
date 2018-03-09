#!/usr/bin/ksh
##!/usr/bin/env bash
#
# Solaris Data Collection NetStat script
# A simple utility that will create 2 files based on netstat output.
#
# File 1 contains output based on the following
#   1. Run netstat
#   2. Get all endpoints that are ESTABLISHED status (i.e. the ip address of the endpoint)
#   3. Ping the endpoint x times
#   4. Record to a csv file the ping statistics (details below)
#
# File 2 contains output based on the following rules
#   1. Run netstat
#   2. Get all endpoints that are in 'ESTABLISHED', 'TIME_WAIT', 'CLOSE_WAIT' or 'SYN_SENT' status
#   3. Record the output to a csv file (details below)
#
# Version: 1.0
# Author: Tennis Smith <www.roundtower.com>, under GPL v2+
# (C) 2018 RoundTower Technologies, Inc. Confidential & Intellectual Property. All rights reserved.
#
# Version 2.0
# moved to POSIX shell
# added directory for ping binary location
# fixed defect in script failing under Solaris 10
# fixed defect in script failing under Solaris 11
# fixed defect in loss of data on reboot by moving archive to persistent home directory
# fixed defect in long running processes stepping on one another with PID locking & verbose exit
# logged errors in long running processes persistently
# hard ending date added with silent exit
# add cleanup of /tmp/netstat_tests collection point after completed run
# Author: David Halko <netmgt.blogspot.com> <www.ncr.com>
# (c) 2018 NCR Corporation Confidential & Intellectual Property. All rights reserved.
# -------------------------------------------------------

# added PATH for ping command
PATH=$PATH:/usr/sbin export PATH

# added for long running processes on servers which may reboot before collection, data cleanup, log file rotation
Num1=12960; Echo="F"; export Num1 Echo		# rotate archive files after 45 days with 5 min interval
Num2=10000; export Num2				# rotate persistent log files
EndDay="20180409"				# hard ending date for silent exit
EndTest="$(date +%Y%m%d)"			# test ending date 
[ "${EndTest}" -gt "${EndDay}" ] && exit 0	# silent end
ArchDir=tmp/solaris_dc_netstat;	export ArchDir
ArchPid=${ArchDir}/solaris_dc_netstat.pid
ArchPidOut=${ArchPid}.out
cd ; mkdir -p ${ArchDir}; echo "`date +%Y%m%d%H%M%S` - Pid: $$">>${ArchPidOut}
if [ -f ${ArchPid} ]; then
	ptree $(cat ${ArchPid}) >>${ArchPidOut} 2>&1 && { 
		echo "`date +%Y%m%d%H%M%S` - $(cat ${ArchPid}) still running, my pid $$, exiting">>${ArchPidOut} 2>&1; exit 0 
	} || {	echo "`date +%Y%m%d%H%M%S` - $(cat ${ArchPid}) not running, my pid $$, removing">>${ArchPidOut} 2>&1; rm ${ArchPid}; }
fi
rm -rf /tmp/netstat_tests			# clear temporary collection point
echo "$$" >${ArchPid}

set -o errexit   # force exit when a command fails
# pipefail will not work with standard shell
#set -o pipefail  # when piping, set exit code to last non-zero in pipeline

timestamp=$(date +'%Y%m%d_%H%M%S')
my_ip=$(/usr/sbin/ifconfig -a | awk 'BEGIN { count=0; } { if ( $1 ~ /inet/ ) { count++; if( count==2 ) { print $2; } } }' )
my_ip_addr=$(echo "${my_ip}" | sed 's/\./_/g')

# Extract the remote ip addr from the netstat output. It has a port # appended, so it has to be trimmed.
#netstat | grep ESTABLISHED | awk '{print $2}' | cut -d'.' -f1-4 | while read -r ip_addr; do
# added -n option so Solaris 11 will properly trim the port from the ip address
# conslidated unneeded grep to reduce complexity
# added sort to eliminate duplicate latency tests
netstat -n | awk '/ESTABLISHED/ {print $2}' | cut -d'.' -f1-4 | sort -u | while read -r ip_addr; do
    # Tells the world what we're doing
    echo "pinging ${ip_addr}"

    # create a dir name by using the remote ip address, but replacing dots with underscores
    ip_addr_dir=$(echo "${ip_addr}" | sed 's/\./_/g')

    # If the directory doesn't exist, create it.
    if ! [[ -d "/tmp/netstat_tests/${ip_addr_dir}" ]]; then
        mkdir -p "/tmp/netstat_tests/${ip_addr_dir}"
    fi

    #
    # Ping 3 times using a packet that is 100 bytes in length
    # From the output, get the following part of the line:
    #     round-trip (ms)  min/avg/max/stddev = 0.328/4.04/11.4/6.4
    #                                           ^^^^^^^^^^^^^^^^^^^
    # ...then replace the slashes with commas.
    # The "ping_result" var now contains "min,avg,max,stddev" values we can send to a csv file
    ping_result=$(ping -s ${ip_addr} 100 3 | grep round | cut -d' ' -f6 | sed 's/\//,/g')
    echo ${ping_result} > "/tmp/netstat_tests/${ip_addr_dir}/${timestamp}.csv"
done


# Run netstat to pickup certain session state information
#netstat | ggrep -e 'ESTABLISHED' -e 'TIME_WAIT' -e 'CLOSE_WAIT' -e 'SYN_SENT' - | while read -r line; do
# replaced missing & unsupported ggrep with multi-platform POSIX egrep
netstat | egrep '(ESTABLISHED|TIME_WAIT|CLOSE_WAIT|SYN_SENT)'			 | while read -r line; do

    # Extract the remote ip addr ONLY from the netstat output. It has a port # appended, so it has to be trimmed.
    ip_remote=$( echo "${line}" | cut -d' ' -f 2 | cut -d'.' -f1-4 )

    # Get the protocol state, which is the last field in the output
    state_out=$(echo ${line} | awk '{print $NF}')

    # Put a comma-separated line to a report file.
    # The line contains a timestamp, our local ip addr, the remote ip addr, and the state
    echo "${timestamp},${my_ip_addr},${ip_remote},${state_out}" >> "/tmp/netstat_tests/${my_ip_addr}_${timestamp}.csv"
done

# Finally we tar everything to a common file
#tar cvf - /tmp/netstat_tests | gzip -c > /tmp/${my_ip_addr}_${timestamp}_netstat_tests.tar.gz
# tar file was placed in volitile storage & lost during boot, making persistent, compress more aggressively
tar cvf - /tmp/netstat_tests | gzip -9c > ${ArchDir}/${my_ip_addr}_${timestamp}_netstat_tests.tar.gz

# cleanup of PID & old-archives beyond expiration for persistent storage
rm ${ArchDir}/solaris_dc_netstat.pid				# PID of current running collector
if [ "${ArchDir}" != ""  -a -d ${ArchDir} ]; then
 ls -1t ${ArchDir} | nawk  '
	BEGIN			{ Num1=ENVIRON["Num1"]; Echo=ENVIRON["Echo"]; ArchDir=ENVIRON["ArchDir"]; } 
	NR<=Num1 && Echo==""	{ print NR,$0 }
	NR>Num1 && Echo==""	{ print NR,$0,"\texpired" } 	# expired data from persistent store
	NR>Num1			{ Cmd="rm " ArchDir "/" $0 " 2>&1"; system(Cmd) }' >>${ArchPidOut} 2>&1
fi
[ -f "${ArchPidOut}" -a $(nawk 'END { print NR }' ${ArchPidOut}) -gt ${Num2} ] && mv ${ArchPidOut} ${ArchPidOut}.old
touch ${ArchPidOut}						# log file associated with collector PID
