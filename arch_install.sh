#!/usr/bin/env -S bash -e


# Author: Philippe Olivier
#
#
# Introduction
# ============
#
# The following is a simplistic Arch Linux installation script that provides the following:
# - Single-volume LUKS encryption with ext4
# - Booting is managed with systemd-boot
#
# As always, make sure to validate this script against the current official installation guide that
# can be found on the Arch Wiki, to ensure that the installation proceeds reliably.
#
# Many parts of this script are based off the work of Tommaso Chiti. His script can be found here:
# https://github.com/classy-giraffe/easy-arch
#
#
# Usage
# =====
#
# $ bash <(curl -sL URL_OF_THIS_SCRIPT)
#
# This script is mostly automated, but still requires some user input. Please fill some data in the
# global variables below.
#
#
# Partitions layout
# =================
#
# +---+-------+---------+------------+------------+
# | # | Label | Size    | Mountpoint | Filesystem |
# +---+-------+---------+------------+------------+
# | 1 | ESP   | 512 MiB | /boot      | FAT32      |
# | 2 | ROOT  | Rest    | /          | Ext4       |
# +---+-------+---------+------------+------------+


USERNAME="pholi"
HOSTNAME="pholi-arch"

BOOT_LABEL="ESP"
ROOT_LABEL="ROOT"
BOOT_PARTITION="/dev/disk/by-partlabel/${BOOT_LABEL}"
ROOT_PARTITION="/dev/disk/by-partlabel/${ROOT_LABEL}"
LUKS_MAPPING="cryptroot"
CRYPTROOT="/dev/mapper/${LUKS_MAPPING}"


# Pretty print.
print () {
    echo -e "\e[1m\e[93m[ \e[92m•\e[93m ] \e[4m$1\e[0m"
}


clear
print "The script to install Arch Linux begins."

# Making sure that there is internet connectivity.
print "Checking for internet connection."
if ping -q -c 1 -W 1 8.8.8.8 &>/dev/null; then
	print "Connected to the internet."
else
	print "Error: No internet connection. Quitting."
	exit
fi

# Checking for UEFI boot mode.
print "Checking for UEFI boot mode."
if [[ -d "/sys/firmware/efi/efivars" ]]; then
	print "UEFI boot mode detected."
else
	print "Error: UEFI boot mode not detected. Quitting."
	exit
fi

# Selecting the target for the installation.
PS3="Select the device where Arch Linux is going to be installed: "
select ENTRY in $(lsblk -dpnoNAME|grep -P "/dev/sd|nvme|vd");
do
    DEVICE=${ENTRY}
    print "Installing Arch Linux on ${DEVICE}."
    break
done

# Deleting old partition scheme.
read -r -p "Delete the current partition table on ${DEVICE}? [y/N] " RESPONSE
RESPONSE=${RESPONSE,,}
if [[ "${RESPONSE}" =~ ^(yes|y)$ ]]; then
    print "Wiping ${DEVICE}."
	wipefs -af $(lsblk -lpoNAME | grep -P "${DEVICE}" | sort -r) &>/dev/null
    sgdisk -Zo "${DEVICE}" &>/dev/null
else
    print "Quitting."
    exit
fi

# Creating a new partition scheme.
print "Creating the partitions on ${DEVICE}."
parted -s "${DEVICE}" \
    mklabel gpt \
    mkpart ${BOOT_LABEL} fat32 1MiB 513MiB \
    set 1 esp on \
    mkpart ${ROOT_LABEL} ext4 513MiB 100% \

# Informing the Kernel of the changes.
print "Informing the Kernel about the disk changes."
partprobe "${DEVICE}"

# Formatting the boot partition as FAT32.
print "Formatting the boot partition as FAT32."
mkfs.fat -F 32 ${BOOT_PARTITION} &>/dev/null

# Creating a LUKS Container for the root partition.
print "Creating LUKS Container for the root partition."
read -r -s -p "Enter a password for the LUKS container: " LUKS_PASSPHRASE
echo -n "${LUKS_PASSPHRASE}" | cryptsetup luksFormat --type luks2 "${ROOT_PARTITION}" -d -
echo -n "${LUKS_PASSPHRASE}" | cryptsetup open --type luks2 "${ROOT_PARTITION}" "${LUKS_MAPPING}" -d -    

# Formatting the LUKS Container as Ext4.
print "Formatting the LUKS container as Ext4."
mkfs.ext4 ${CRYPTROOT} &>/dev/null

# Mounting the partitions.
mount ${CRYPTROOT} /mnt
mkdir /mnt/boot
mount ${BOOT_PARTITION} /mnt/boot

# Pacstrap (setting up a base sytem onto the new root).
print "Installing the base system (it may take a while)."
pacstrap /mnt base base-devel intel-ucode iwd linux linux-firmware linux-headers

# Setting up the hostname.
echo "${HOSTNAME}" > /mnt/etc/hostname

# Generating /etc/fstab.
print "Generating a new fstab."
genfstab -U /mnt >> /mnt/etc/fstab

# Setting up the locale.
sed -i "/^#en_CA.UTF-8 UTF-8/cen_CA.UTF-8 UTF-8" /mnt/etc/locale.gen
echo "LANG=en_CA.UTF-8" > /mnt/etc/locale.conf

# Setting up keyboard layout.
echo "KEYMAP=us" > /mnt/etc/vconsole.conf

# Setting hosts file.
print "Setting hosts file."
cat > /mnt/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain   ${HOSTNAME}
EOF

# Configuring /etc/mkinitcpio.conf.
print "Configuring /etc/mkinitcpio.conf."
sed -i "/^HOOKS=(/cHOOKS=(base systemd autodetect keyboard sd-vconsole modconf block sd-encrypt filesystems fsck)" /mnt/etc/mkinitcpio.conf

# Setting up the bootloader.
print "Setting up systemd-boot."
bootctl --path=/mnt/boot install

cat > /mnt/boot/loader/loader.conf <<EOF
default  arch.conf
timeout  5
console-mode max
editor   no
EOF

UUID=$(blkid -s UUID -o value ${ROOT_PARTITION})

cat > /mnt/boot/loader/entries/arch.conf <<EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /initramfs-linux.img
options root=${CRYPTROOT} rd.luks.name=${UUID}=${LUKS_MAPPING} rw
EOF

cat > /mnt/boot/loader/entries/arch-fallback.conf <<EOF
title   Arch Linux (fallback initramfs)
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /initramfs-linux-fallback.img
options root=${CRYPTROOT} rd.luks.name=${UUID}=${LUKS_MAPPING} rw
EOF

# Configuring the system.    
arch-chroot /mnt /bin/bash -e <<EOF
    # Setting up timezone.
    echo "Setting up the timezone."
    ln -sf /usr/share/zoneinfo/Canada/Eastern /etc/localtime &>/dev/null
    
    # Setting up clock.
    echo "Setting up the system clock."
    hwclock --systohc
	systemctl enable systemd-timesyncd.service
    systemctl start systemd-timesyncd.service
	timedatectl set-ntp true

    # Generating locales.
    echo "Generating locales."
    locale-gen &>/dev/null
    
    # Generating a new initramfs.
    echo "Creating a new initramfs."
    mkinitcpio -P &>/dev/null
EOF

# Setting root password.
print "Setting root password."
arch-chroot /mnt /bin/passwd

# Setting user password.
print "Adding user \"${USERNAME}\" to the system with root privileges."
arch-chroot /mnt useradd -m -G wheel -s /bin/bash "${USERNAME}"
echo "${USERNAME} ALL=(ALL) ALL" >> /mnt/etc/sudoers
print "Setting user password for ${USERNAME}." 
arch-chroot /mnt /bin/passwd "${USERNAME}"

# Configuration of network interfaces through systemd-networkd.
WIRED_INTERFACE=$(ls /sys/class/net | grep enp)
cat > /mnt/etc/systemd/network/20-wired.network <<EOF
[Match]
Name=${WIRED_INTERFACE}

[Network]
DHCP=yes
EOF

WIRELESS_INTERFACE=$(ls /sys/class/net | grep wl)
cat > /mnt/etc/systemd/network/25-wireless.network <<EOF
[Match]
Name=${WIRELESS_INTERFACE}

[Network]
DHCP=yes
EOF

# Configuring systemd-resolved.
sed -i "/^#DNS=/cDNS=8.8.8.8" /mnt/etc/systemd/resolved.conf

# Enabling various services.
print "Enabling various services."
for SERVICE in systemd-boot-update.service systemd-oomd systemd-networkd.service systemd-resolved.service iwd.service; do
    systemctl enable "${SERVICE}" --root=/mnt &>/dev/null
done

# Finishing up.
umount -a &>/dev/null
print "The installer script is done."
exit


# TODO:
# - removing rsync from this script, so add it to the installation instructions
# - still need efibootmgr?
