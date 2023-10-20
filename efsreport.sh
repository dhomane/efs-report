#!/usr/bin/env bash
#
# Copyright 2018 Amazon.com, Inc. and its affiliates. All Rights Reserved.
#
# Licensed under the MIT License. See the LICENSE accompanying this file
# for the specific language governing permissions and limitations under
# the License.
#

trap "exit" INT TERM ERR
trap "kill 0" EXIT

PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"
timestamp="date --utc --iso-8601=seconds"

function print_banner()
{
    cat <<EOF

       __|  __|_  )
       _|  (     /   Amazon EFS Report
      ___|\___|___|

EOF
}


function print_msg()
{
    printf "%s\n" "$@"
}


function print_err()
{
    printf "%s\n" "[$($timestamp)]: $*"
    exit 1
}


function usage()
{
    cat <<-END >&2
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
END
exit
}


function verify_os()
{
    if [[ "$OSTYPE" =~ ^"linux-gnu"$ ]]; then
        if [[ -f /etc/os-release ]]; then
            source /etc/os-release
            local os=$ID
        else
            os="Linux"
        fi
    else
        print_err "Sorry, this operating system is not supported."
    fi

    if [[ -f /var/log/syslog ]]; then
        syslog="/var/log/syslog"
    else
        syslog="/var/log/messages"
    fi
} 2> /dev/null


function progress_bar()
{
    [[ "$seconds" -eq 1 ]] && seconds=2
    run()
    {
        (( barProgress="(${1}*100/${2}*100)/100" ))
        (( barDone="(barProgress*4)/10" ))
        (( barLeft=40-barDone ))
        barFill=$(printf "%${barDone}s")
        barEmpty=$(printf "%${barLeft}s")
        printf "\rProgress : [${barFill// /#}${barEmpty// /-}] ${barProgress}%%"
    }

    for number in $(seq $start $seconds); do
        sleep 1
        run "$number" "$seconds"
    done
    print_msg ""
}


function spinner_bar()
{
    print_msg "You can finish this process at any time, to do so just press ENTER."
    counter=1
    chars="\|/-"
    delay=0.1

    while :; do
        read -t 0 -r && { read -r; break; }
        printf "\b%s" "${chars:counter++%${#chars}:1}"
        sleep ${delay}
    done
} 2> /dev/null


function search_mount_target()
{
    print_banner
    nfs_mounts=$(findmnt -t nfs4 -o SOURCE,TARGET -n)

    if [[ -n "$nfs_mounts" ]]; then
        print_msg "$nfs_mounts" | awk 'BEGIN {print "Found the following nfs4 file system(s):"} {print $1,$2,"\n"}'
    else
        print_err "No nfs4 file system found on this system."
    fi

    exit
} 2> /dev/null


function validate_mount_target()
{
    if [[ "$mount_target" =~ ^.*amazonaws.com$ ]]; then
        mount_target=$(getent hosts "$mount_target" | awk '{print $1}')
    elif [[ "$mount_target" =~ ^((25[0-5]|2[0-4][0-9]|[01]?[1-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[1-9][0-9]?)$ ]]; then
        mount_target="$mount_target"
    else
        print_err "Invalid mount target IP address or DNS name: $mount_target"
    fi

    nfs_connection=$(ss -nt4 state established dst "$mount_target"/32 dport = :2049 2> /dev/null | grep -o "$mount_target:2049")
    if [[ -z "$nfs_connection" ]]; then
        print_err "Unable to find a nfs4 mounted file system for the mount target: $mount_target"
    fi
} 2> /dev/null


function start_data_collection()
{
    print_msg "Starting data collection ..."

    local interval=5
    archive="$(uname -n)_$($timestamp).tar.gz"
    readonly session="$(mktemp -u XXXXXXXXXXXXXXX)/$(uname -n)_$($timestamp)"

    if ! mkdir -p "$tmpdir/$session"/{files,commands,metadata,efs-utils} ; then
        print_err "Unable to write on directory $tmpdir"
    else
        mkdir -p "$tmpdir/$session"/{files,commands,metadata,efs-utils}
    fi

    if [[ "$rpcdebug" =~ ^(RPC)$ ]]; then
        rpcdebug -m rpc -s all > /dev/null
    elif [[ "$rpcdebug" =~ ^(NFS)$ ]]; then
        rpcdebug -m nfs -s all > /dev/null
    elif [[ "$rpcdebug" =~ ^(ALL)$ ]]; then
        rpcdebug -m rpc -s all > /dev/null
        rpcdebug -m nfs -s all > /dev/null
    fi

    if [[ -f /etc/sysconfig/clock ]]; then
        cp /etc/sysconfig/clock "$tmpdir/$session"/files/clock
    elif [[ -f /etc/timezone ]]; then
        cp /etc/timezone "$tmpdir/$session"/files/clock
    fi
    cp /proc/self/mountstats "$tmpdir/$session"/files/mountstats_before.raw
    cp /etc/fstab "$tmpdir/$session"/files/fstab
    cp /etc/mtab "$tmpdir/$session"/files/mtab
    cp /proc/mounts "$tmpdir/$session"/files/mounts
    cp /etc/os-release "$tmpdir/$session"/files/os-release
    cp /proc/cmdline "$tmpdir/$session"/files/cmdline

    awk '$2 !~ /\/proc\/fs\/nfsd/ && $3 ~ /nfs/ { print $2 }' /proc/mounts | \
        while read -r nfs_mounts; do
            local output="$tmpdir/$session/files/mountstats_before"
            exec 5>$output
            (
            $timestamp
            echo "NFS mount: $nfs_mounts"
            mountstats --rpc "$nfs_mounts"
            mountstats --nfs "$nfs_mounts"
            ) >&5
        done

    local tcpdump="tcpdump -s 512 -n -vvv -i any port 2049 -W 10 -C 1000 -w $tmpdir/$session/files/tcpdump.pcap -Z root -z gzip"
    GZIP="-f" $tcpdump > /dev/null &

    (
    while true; do
        ($timestamp; grep -E "(Dirty|Writeback|NFS_Unstable):" /proc/meminfo) >> "$tmpdir/$session"/commands/nfs_meminfo.txt
        ($timestamp; nfsiostat) >> "$tmpdir/$session"/commands/nfsiostat.txt
        ($timestamp; iostat -xty) >> "$tmpdir/$session"/commands/iostat.txt
        ($timestamp; iostat -cty) >> "$tmpdir/$session"/commands/nfs_cpu.txt
        ($timestamp; pidstat -tu) >> "$tmpdir/$session"/commands/pidstat.txt
        ($timestamp; lslocks) >> "$tmpdir/$session"/commands/lslocks.txt
        sleep "$interval"
    done
    ) &

    iptables -S > "$tmpdir/$session"/commands/iptables.txt
    uname -a > "$tmpdir/$session"/commands/uname.txt
    lsmod > "$tmpdir/$session"/commands/lsmod.txt

    netstat -antpl > "$tmpdir/$session"/commands/netstat_antpl.txt
    netstat -neopa > "$tmpdir/$session"/commands/netstat_neopa.txt
    netstat -s > "$tmpdir/$session"/commands/netstat_s.txt
    ps axjf > "$tmpdir/$session"/commands/ps_tree.txt
    ps -ef > "$tmpdir/$session"/commands/ps.txt
    netstat -i -e > "$tmpdir/$session"/commands/netstat_ie.txt
    ip route list > "$tmpdir/$session"/commands/iproute_list.txt

    for k in /sys/class/net/*; do
        dev=$(basename "$k")
        driver=$(readlink "$k"/device/driver/module)

        if [[ "$driver" ]]; then
            driver=$(basename "$driver")
        fi

        addr=$(cat "$k"/address)
        operstate=$(cat "$k"/operstate)

        if [[ "$dev" != "lo" ]]; then
            printf "%10s [%s]: %10s (%s)\n" "$dev" "$addr" "$driver" "$operstate" | xargs
            print_msg ""
            modinfo "$driver"
        fi
    done >> "$tmpdir/$session"/commands/modinfo_net.txt

    function print_metadata()
    {
        metadata=$2
        printf "\n  $1: "
        curl=$(curl -fs http://169.254.169.254/latest/${metadata}/)
        if [ $? == 0 ]; then
            print_msg  "$curl"
        else
            print_msg "not available"
        fi
    }

    (
    print_metadata ami-id meta-data/ami-id
    print_metadata instance-id meta-data/instance-id
    print_metadata instance-type meta-data/instance-type
    print_metadata local-hostname meta-data/local-hostname
    print_metadata local-ipv4 meta-data/local-ipv4
    print_metadata placement meta-data/placement/availability-zone
    print_metadata security-groups meta-data/security-groups
    print_block_device_mapping
    ) | sed -E "s/[[:space:]]+/ /g; N;s/\n/ /; /^$/d" > "$tmpdir/$session"/metadata/ec2metadata
} 2> /dev/null


function monitor_nfs_timeout()
{
    (sed '/not responding/q' <(exec tail -n 0 -f "$syslog") > /dev/null; print_msg "NFS timeout found, finishing background tasks ..."; sleep 60) &
    monitor_pid=$!
    print_msg "Monitoring NFS timeouts ..."
    print_msg "You can finish this process at any time, to do so just press ENTER, or wait until a NFS timeout is found ..."

    counter=1
    chars="\|/-"
    delay=0.1
    while kill -0 "$monitor_pid" > /dev/null; do
        read -t 0 -r && { read -r; break; }
        printf "\b%s" "${chars:counter++%${#chars}:1}"
        sleep "$delay"
    done
} 2> /dev/null


function stop_data_collection()
{
    cp /proc/self/mountstats "$tmpdir/$session"/files/mountstats_after.raw
    awk '$2 !~ /\/proc\/fs\/nfsd/ && $3 ~ /nfs/ { print $2 }' /proc/mounts | \

    while read -r nfs_mounts; do
        local output="$tmpdir/$session/files/mountstats_after"
        exec 5> $output
        (
        $timestamp
        echo "NFS mount: $nfs_mounts"
        mountstats --rpc "$nfs_mounts"
        mountstats --nfs "$nfs_mounts"
        ) >&5
    done

    if ! dmesg -T > /dev/null; then
        dmesg > "$tmpdir/$session"/commands/dmesg.txt
    else
        dmesg -T > "$tmpdir/$session"/commands/dmesg.txt
    fi

    if [[ -d /var/log/amazon/efs ]]; then
        GZIP="-f" tar -C /var/log/amazon/efs -czf "$tmpdir/$session"/efs-utils/amazon-efs-utils.tar.gz .
        stunnel -version |& tee -a > "$tmpdir/$session"/efs-utils/stunnel.txt
        openssl version > "$tmpdir/$session"/efs-utils/openssl.txt
        openssl ciphers > "$tmpdir/$session"/efs-utils/openssl_chiphers.txt
    fi

    tar -C /var/log -cf "$tmpdir/$session"/files/syslog.tar "$(awk -F'/' '{print $NF}' <<< "$syslog")"
    for k in $(ls $syslog* | egrep -v "messages|syslog"$); do
        tar -C /var/log -rf "$tmpdir/$session"/files/syslog.tar "$(awk -F'/' '{print $NF}' <<< "$k")"
    done
    gzip --best "$tmpdir/$session"/files/syslog.tar

    if [[ -d /var/log/sa ]]; then
        sysstat="sa"
    elif [[ -d /var/log/sysstat ]];then
        sysstat="sysstat"
    fi

    if [[ ! -z "$systat" ]]; then
        GZIP="-f" tar -C /var/log -czf "$tmpdir/$session"/files/sysstat.tar.gz $systat
    fi

    GZIP="-f" tar -C "$tmpdir/$session/.." --remove-files -czf "$tmpdir/$archive" $(sed -e 's/.tar.gz//' <<< "$archive")
    rmdir "$tmpdir"/"$(awk -F'/' '{print $(NF-1)}' <<< "$tmpdir/$session")"

    if [[ "$rpcdebug" =~ ^(RPC)$ ]]; then
        rpcdebug -m rpc -c all > /dev/null
    elif [[ "$rpcdebug" =~ ^(NFS)$ ]]; then
        rpcdebug -m nfs -c all > /dev/null
    elif [[ "$rpcdebug" =~ ^(ALL)$ ]]; then
        rpcdebug -m rpc -c all > /dev/null
        rpcdebug -m nfs -c all > /dev/null
    fi

    print_msg "Completed - please use the AWS Support S3 Uploader URL to upload the following efsreport archive file: $tmpdir/$archive"
} 2> /dev/null


if [[ "$EUID" -ne 0 ]]; then
    print_banner
    print_err "WARNING: Running as a non-root user. Functionality may be unavailable."
fi


while getopts ht:d:lp:wr: opt; do
    case $opt in
        t)
            mount_target=$OPTARG
            ;;
        d)
            seconds=$OPTARG
            ;;
        l)
            search_mount_target
            ;;
        p)
            tmpdir=$OPTARG
            ;;
        w)
            monitor=1
            ;;
        r)
            rpcdebug=$OPTARG
            ;;
        *)
            print_banner
            usage
            ;;
    esac
done
shift $(expr $OPTIND - 1)


if [[ "$OPTIND" -eq 1 ]]; then
    print_banner && usage
fi


if [[ -z "$monitor" ]]; then
    monitor=0
else
    monitor=1
fi


if [[ -z "$mount_target" ]] && [[ "$monitor" != 1 ]]; then
    print_banner
fi


if [[ "$seconds" == "forever" ]]; then
    seconds="-1"
elif [[ -z "$seconds" ]] && [[ "$monitor" == 0 ]]; then
    seconds=300
elif [[ -z "$seconds" ]] && [[ "$monitor" == 1 ]]; then
    seconds=-1
elif [[ "$seconds" =~ ^-?[0-9]+$ ]]; then
    seconds=$seconds
else
    print_banner
    print_err "The value for -d must be an integer greater than zero or forever to run indefinite"
fi


if [[ -z "$rpcdebug" ]] || [[ "$rpcdebug" =~ ^(RPC|NFS|ALL)$ ]]; then
    true
else
    print_banner
    print_err "The value for -r must be NFS, RCP or ALL"
fi


if [[ -z "$tmpdir" ]]; then
    tmpdir="/tmp"
elif [[ "$tmpdir" =~ /$ ]]; then
    tmpdir=$(sed 's:\/$::' <<< "$tmpdir" )
fi


if [[ "$seconds" -eq 0 ]]; then
    print_banner
    print_err "The value for -d must be an 'integer' or 'forever' to run indefinite"
fi


if [[ "$seconds" -gt 0 ]] && [[ "$monitor" == 0 ]]; then
    print_banner  && verify_os && validate_mount_target && start_data_collection && progress_bar && stop_data_collection
elif [[ "$seconds" -lt 0 ]] && [[ "$monitor" == 0 ]]; then
    print_banner && verify_os && validate_mount_target && start_data_collection && spinner_bar && stop_data_collection
elif [[ "$seconds" == "-1" ]] && [[ "$monitor" == 1 ]]; then
    print_banner && verify_os && validate_mount_target && start_data_collection && monitor_nfs_timeout && stop_data_collection
fi
