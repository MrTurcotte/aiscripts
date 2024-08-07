#!/bin/bash

# Variables
MOUNT_POINT="/mnt/gentoo"
EFI_PART="/dev/sda1"
EXT4_PART="/dev/sda2"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# Mount partitions
mkdir -p $MOUNT_POINT
mount $EXT4_PART $MOUNT_POINT
mkdir -p $MOUNT_POINT/boot
mount $EFI_PART $MOUNT_POINT/boot

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

# Copy DNS info
cp --dereference /etc/resolv.conf $MOUNT_POINT/etc/

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

# Set timezone
echo "UTC" > /etc/timezone
emerge --config sys-libs/timezone-data

# Set locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set en_US.utf8
env-update && source /etc/profile && export PS1="(chroot) $PS1"

# Install kernel sources and tools
emerge sys-kernel/gentoo-sources
emerge sys-kernel/genkernel
genkernel all

# Set up fstab
PARTUUID_EFI=$(blkid -s PARTUUID -o value $EFI_PART)
PARTUUID_EXT4=$(blkid -s PARTUUID -o value $EXT4_PART)
cat <<EOF > /etc/fstab
PARTUUID=$PARTUUID_EXT4  /       ext4    noatime         0 1
PARTUUID=$PARTUUID_EFI   /boot   vfat    defaults        0 2
EOF

# Install SystemD
emerge sys-apps/systemd

# Install and configure SystemD boot
bootctl install

# Create boot entry
cat <<EOF_BOOT > /boot/loader/entries/gentoo.conf
title Gentoo Linux
linux /vmlinuz-$(uname -r)
initrd /initramfs-$(uname -r).img
options root=PARTUUID=$PARTUUID_EXT4 rw
EOF_BOOT

# Update bootloader configuration
cat <<EOF_LOADER > /boot/loader/loader.conf
default gentoo
timeout 5
EOF_LOADER

# Set root password
echo "Set root password"
passwd

# Exit chroot
exit
EOF_CHROOT

# Unmount filesystems
umount -l $MOUNT_POINT/dev{/shm,/pts,}
umount -R $MOUNT_POINT

echo "Gentoo installation with SystemD boot is complete. Please review the configuration and complete the setup manually."
