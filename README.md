# solaris_dc_netstat

A simple utility that will create 2 files based on netstat output.

File 1 contains output based on the following
  1. Run netstat
  2. Get all endpoints that are ESTABLISHED status (i.e. the ip address of the endpoint)
  3. Ping the endpoint 3 times
  4. Record to a csv file the ping statistics

File 2 contains output based on the following rules
  1. Run netstat
  2. Get all endpoints that are in 'ESTABLISHED', 'TIME_WAIT', 'CLOSE_WAIT' or 'SYN_SENT' status
  3. Record the output to a csv file  
