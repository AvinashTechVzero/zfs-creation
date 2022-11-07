apt-get update
apt install -y zfsutils-linux jq pv
DEVICES=( $(lsblk --fs --json | jq -r '.blockdevices[] | select(.children == null and .fstype == null) | .name') )
DEVICES_FULLNAME=()
for DEVICE in "${DEVICES[@]}"; do
    DEVICES_FULLNAME+=("/dev/$DEVICE")
done
zpool create -o ashift=12 tank "/dev/xvda1"
# The root tank dataset does not get mounted.
zfs set mountpoint=none tank

# Configures ZFS to be slightly more optimal for our use case.
zfs set compression=lz4 tank
# Note: You might be able to get better erigon performance by changing this to 16k.
zfs set recordsize=128k tank
zfs set sync=disabled tank
zfs set redundant_metadata=most tank
zfs set atime=off tank
zfs set logbias=throughput tank

# By creating a swap it won't hurt much unless it's running on a small instance.
# Under rare cases erigon might want to use an insane amount of ram (like if parlia database is
# missing). This will allow us to at least get beyond that point. Measuring shows it only uses
# about 48gb of ram when this happens. The vast majority of the time the swap will not be used.
zfs create -s -V 48G -b $(getconf PAGESIZE) \
    -o compression=zle \
    -o sync=always \
    -o primarycache=metadata \
    -o secondarycache=none \
    tank/swap
sleep 3 # It takes a moment for our zvol to be created.
mkswap -f /dev/zvol/tank/swap
swapon /dev/zvol/tank/swap

# Set zfs's arc to 4GB. Erigon uses mmap() to map files into memory which is a cache system itself.
echo 4147483648 > /sys/module/zfs/parameters/zfs_arc_max
