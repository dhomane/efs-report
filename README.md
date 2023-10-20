# EFS Report

USAGE: efsreport [-hlw] [-t mount-target] [-d seconds] [-p tmp-dir] [-r NFS|RPC|ALL]

    efsreport -h
    efsreport -l
    efsreport -t 172.31.5.159 -d 300
    efsreport -t 172.31.5.159 -d forever
    efsreport -t file-system-id -d 300 -p /var/tmp
    efsreport -t file-system-id -w
    efsreport -t file-system-id -r NFS
    efsreport -t file-system-id -r RPC
    efsreport -t file-system-id -r ALL

    -d seconds       # trace duration; use '-d forever' to run indefinite
    -l               # search nfsv4 mounted file system(s)
    -t host          # mount target's IP address or DNS name
    -w               # monitor NFS timeout
    -r NFS|RPC|ALL   # enable rpcdebug
    -p tmp-dir       # temporary directory
    -h               # this usage message
