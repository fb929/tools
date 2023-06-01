#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin

VG_NAME="vg"
LV_NAME="data"
LV_SIZE="1T"

do_usage(){
    cat <<EOF
generating commands for creating and mounting lvm volumes

usage: $0 [mount_dir] [vg_name] [lv_name] [lv_size]

options:
    mount_dir - path for mount dir (default /var/lib/<lv_name>)
    vg_name   - group name (default $VG_NAME)
    lv_name   - volume name (default $LV_NAME)
    lv_size   - volume size (default $LV_SIZE)

examples:
    $0
    $0 vgData
    $0 clickhouse 1G | bash
EOF
    exit 1
}
for ARG in $@; do
    if echo "$ARG" | grep -qP -- "^(--help|-h|help)$"; then
        do_usage
    elif echo $ARG | grep -qP "^/[a-zA-Z0-9_]+"; then
        MOUNT_DIR="$ARG"
    elif echo $ARG | grep -qP "^vg[a-zA-Z0-9_]+$"; then
        VG_NAME="$ARG"
    elif echo $ARG | grep -qP "^[0-9\.]+[TGM]$"; then
        LV_SIZE="$ARG"
    elif echo $ARG | grep -qP "^[a-zA-Z0-9_]+$"; then
        LV_NAME="$ARG"
    fi
    shift
done
if [[ -z $MOUNT_DIR ]]; then
    MOUNT_DIR="/var/lib/$LV_NAME"
fi

cat <<EOF
# create lv
lvcreate -L $LV_SIZE -n $LV_NAME $VG_NAME &&

# create fs
mkfs.ext4 -m 0 /dev/$VG_NAME/$LV_NAME &&
echo -e "/dev/$VG_NAME/$LV_NAME\t$MOUNT_DIR\text4\tdefaults,noatime,nodiratime,nofail\t0 0" >> /etc/fstab &&
install -d $MOUNT_DIR &&
mount $MOUNT_DIR
EOF
