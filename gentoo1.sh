#!/bin/bash

# Variables
DRIVE="/dev/sda"
EFI_SIZE="1G"
EFI_PART="${DRIVE}1"
EXT4_PART="${DRIVE}2"
MOUNT_POINT="/mnt/gentoo"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# Create GPT partition table
parted $DRIVE --script mklabel gpt

# Create EFI partition
parted $DRIVE --script mkpart primary fat32 1MiB $EFI_SIZE
parted $DRIVE --script set 1 boot on

# Create ext4 partition with remaining space
parted $DRIVE --script mkpart primary ext4 $EFI_SIZE 100%

# Format partitions
mkfs.fat -F32 $EFI_PART
mkfs.ext4 $EXT4_PART

# Mount partitions
mkdir -p $MOUNT_POINT
mount $EXT4_PART $MOUNT_POINT
mkdir -p $MOUNT_POINT/boot
mount $EFI_PART $MOUNT_POINT/boot

# Install Gentoo
# Note: This part is highly simplified. Adjust paths and options as necessary.

# Download stage3 tarball (adjust URL as necessary)
cd $MOUNT_POINT
wget https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/latest-stage3-amd64.txt
STAGE3=$(grep -v '^#' latest-stage3-amd64.txt | awk '{print $1}')
wget https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/$STAGE3

# Extract stage3 tarball
tar xpf $(basename $STAGE3) --xattrs-include='*.*' --numeric-owner

# Configure make.conf
cat <<EOF > $MOUNT_POINT/etc/portage/make.conf
COMMON_FLAGS="-O3 -march=native"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
MAKEOPTS="-j$(nproc)"
EOF

# Mount necessary filesystems
mount --types proc /proc $MOUNT_POINT/proc
mount --rbind /sys $MOUNT_POINT/sys
mount --make-rslave $MOUNT_POINT/sys
mount --rbind /dev $MOUNT_POINT/dev
mount --make-rslave $MOUNT_POINT/dev
mount --bind /run $MOUNT_POINT/run
mount --make-slave $MOUNT_POINT/run

# Chroot into Gentoo environment
chroot $MOUNT_POINT /bin/bash <<'EOF_CHROOT'
source /etc/profile
export PS1="(chroot) $PS1"

# Sync portage and update
emerge-webrsync
emerge --sync

# Install necessary packages
emerge gentoo-sources
emerge genkernel
genkernel all

# Install systemd and configure bootloader
emerge systemd
bootctl install

# Create boot entry
PARTUUID=$(blkid -s PARTUUID -o value /dev/sda2)
cat <<EOF_BOOT > /boot/loader/entries/gentoo.conf
title Gentoo Linux
linux /vmlinuz
initrd /initramfs
options root=PARTUUID=$PARTUUID rw
EOF_BOOT

# Update bootloader configuration
cat <<EOF_LOADER > /boot/loader/loader.conf
default gentoo
timeout 5
EOF_LOADER

EOF_CHROOT

# Unmount filesystems
umount -l $MOUNT_POINT/dev{/shm,/pts,}
umount -R $MOUNT_POINT

echo "Gentoo installation with SystemD boot is complete. Please review the configuration and complete the setup manually."
