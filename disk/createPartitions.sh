#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin

MD_NAME="md0"
VG_NAME="vgData"
LV_NAME="data"
LV_SIZE="1T"
RAID_LEVEL="10"

do_usage(){
    cat <<EOF
generating commands for disk setup
steps:
 1. create partitions
 2. create raid
 3. create lvm group and volumes
 4. create fs, generate fstab and mount

usage: $0 [md_name] [mount_dir] [lv_name] [lv_size] [raid-level=n]

options:
    mount_dir - path for mount dir (default /var/lib/<lv_name>)
    md_name   - name for md raid (default $MD_NAME)
    vg_name   - group name (default $VG_NAME)
    lv_name   - volume name (default $LV_NAME)
    lv_size   - volume size (default $LV_SIZE)
    raid-level - raid level (default $RAID_LEVEL), supported 10,60

examples:
    $0
EOF
    exit 1
}

DEFAULT_DISKS=""
for ARG in $@; do
    if echo "$ARG" | grep -qP -- "^(--help|-h|help)$"; then
        do_usage
    elif echo "$ARG" | grep -qP "^(xfs|ext)"; then
        FILE_SYSTEM="$ARG"
    elif echo "$ARG" | grep -qP "^vg[a-zA-Z]+$"; then
        VG_NAME="$ARG"
    elif echo "$ARG" | grep -qP "^md[0-9]+$"; then
        MD_NAME="$ARG"
    elif echo "$ARG" | grep -qP "^/dev/[a-z]+$"; then
        DEFAULT_DISKS="$DEFAULT_DISKS $ARG"
    elif echo "$ARG" | grep -qP "^/[a-z0-9_]+"; then
        MOUNT_DIR="$ARG"
    elif echo "$ARG" | grep -qP "^[a-z0-9_]+$"; then
        LV_NAME="$ARG"
    elif echo "$ARG" | grep -qP "^[0-9\.]+[TGM]$"; then
        LV_SIZE="$ARG"
    elif echo "$ARG" | grep -qP "^(raid-level|raid_level|raidLevel)="; then
        RAID_LEVEL=$( echo "$ARG" | sed 's|.*=||' )
    fi
    shift
done
if [[ -z $MOUNT_DIR ]]; then
    MOUNT_DIR="/var/lib/$LV_NAME"
fi
if [[ -z $FILE_SYSTEM ]]; then
    FILE_SYSTEM="ext4"
fi
case $FILE_SYSTEM in
    ext*)
        FILE_SYSTEM_OPTS='-m 0'
    ;;
    *)
        FILE_SYSTEM_OPTS=''
    ;;
esac

SYSTEM_DISK=$( cat /proc/mdstat  | grep -P "md[0-9]{3}" | sed 's|.*raid[0-9]\+\s\+||; s|[0-9]\[[0-9]\]||g; s|\s|\n|g' | sort -u | xargs echo | sed 's/\s\+/\|/g; s|^|(|; s|$|)\$|' )
DATA_DISKS=$( ls /dev/sd[a-z] /dev/sd[a-z][a-z] /dev/nvme*n1 2>/dev/null | sort -u | grep -vP $SYSTEM_DISK | xargs echo )
if [[ -z $DEFAULT_DISKS ]]; then
    DISKS="$DATA_DISKS"
else
    DISKS="$DEFAULT_DISKS"
fi
CHECKED_DISKS=""
for DISK in $DISKS; do
    SMARTCTL_I=$( smartctl -i $DISK )
    if ( ! echo "$SMARTCTL_I" | grep -qi "Product:\s\+scsi_debug" ) && echo "$SMARTCTL_I" | egrep -qi '(User Capacity|Namespace 1 Size/Capacity)' ; then
        CHECKED_DISKS="$CHECKED_DISKS $DISK"
    fi
done
DISKS=$CHECKED_DISKS
DISKS_COUNT=$( echo $DISKS | sed 's|\s\+|\n|g' | wc -l )
# validate disks count
if [[ $DISKS_COUNT -lt 2 ]]; then
    echo "ERROR: disk count less than 2 ($DISKS_COUNT)" 1>&2
    exit 1
elif [[ $(( $DISKS_COUNT % 2 )) -ne 0 ]]; then
    echo "ERROR: odd numbers of disk ($DISKS_COUNT)" 1>&2
    exit 1
elif [[ $DISKS_COUNT == 2 ]]; then
    MD_RAID_LEVEL=1
elif [[ $DISKS_COUNT -ge 3 ]]; then
    MD_RAID_LEVEL=$RAID_LEVEL
fi

do_create_md(){
    local MD_NAME=$1
    local MD_RAID_LEVEL=$2
    local DISKS=$3
    local DISKS_COUNT=$( echo $DISKS | sed 's|\s\+|\n|g' | wc -l )
    cat <<EOF
# create md
echo y | mdadm --create --verbose --force --chunk=1024 /dev/$MD_NAME --level=$MD_RAID_LEVEL --raid-devices=$DISKS_COUNT $DISKS &&
mdadm --detail --scan --verbose | awk '/ARRAY/ {print}' | grep -w $MD_NAME >> /etc/mdadm.conf &&
EOF
}
do_create_lv(){
    local MD_PATH=$1
    local VG_NAME=$2
    local LV_NAME=$3
    local LV_SIZE=$4

    cat <<EOF
dracut -f &&

# create lv
pvcreate --force $MD_PATH &&
vgcreate $VG_NAME $MD_PATH &&
lvcreate -L $LV_SIZE -n $LV_NAME $VG_NAME &&
EOF
}
# 60 raid
if [[ $RAID_LEVEL == 60 ]]; then
    # 60 raid: making raid6 for 6 disk, raids adding in lvm stripe
    if [[ $(( $DISKS_COUNT % 6 )) -ne 0 ]]; then
        echo "ERROR: $DISKS_COUNT odd 6" 1>&2
        exit 1
    fi
    DISK_NUM=0
    MD_NUM=1
    for DISK in $DISKS; do
        DISK_NUM=$(($DISK_NUM + 1 ))
        DISKS_FOR_RAID="$DISKS_FOR_RAID $DISK"
        if [[ $DISK_NUM -eq 6 ]]; then
            MD_NAME="md6$MD_NUM"
            MD_PATHS="$MD_PATHS /dev/$MD_NAME"
            do_create_md $MD_NAME 6 "$DISKS_FOR_RAID"
            DISK_NUM=0
            DISKS_FOR_RAID=""
            MD_NUM=$(( $MD_NUM + 1 ))
        fi
    done
    do_create_lv "$MD_PATHS" $VG_NAME $LV_NAME $LV_SIZE
else
    do_create_md $MD_NAME $MD_RAID_LEVEL "$DISKS"
    do_create_lv "/dev/$MD_NAME" $VG_NAME $LV_NAME $LV_SIZE
fi

cat <<EOF

# create fs
mkfs.$FILE_SYSTEM $FILE_SYSTEM_OPTS /dev/$VG_NAME/$LV_NAME &&
echo -e "/dev/$VG_NAME/$LV_NAME\t$MOUNT_DIR\t$FILE_SYSTEM\tdefaults,noatime,nodiratime,nofail\t0 0" >> /etc/fstab &&
install -d $MOUNT_DIR &&
mount $MOUNT_DIR
EOF
