#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin

DISKS=$( lsblk -nio NAME,MAJ:MIN,MOUNTPOINT 2>/dev/null \
    | sed 's=\s\+[0-9]\+:[0-9]\+\s\+=;=g' \
    | sed -e ':a;N;$!ba;s=\n[ |`][^\n]*;=;=g' -e 's/;\+/ /g' \
    | grep ' / ' \
    | cut -d' ' -f 1
)

do_createGrub(){
    local DEVICE=$1
    cat <<EOF1
cat <<EOF | grub
device (hd0) $DEVICE
root (hd0,0)
setup (hd0)
EOF
EOF1
}

for DISK in $DISKS; do
    DISK_PATH="/dev/$DISK"
    if [[ -b $DISK_PATH ]]; then
        do_createGrub $DISK_PATH
    fi
done
