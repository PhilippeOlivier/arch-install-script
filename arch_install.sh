#!/usr/bin/env -S bash -e


# Author: Philippe Olivier
#
#
# Introduction
# ============
#
# The following is a basic Arch Linux installation script that provides the following:
# - Btrfs filesystem
# - LUKS2 encryption
# - GRUB bootloader that handles bootable snapshots
#
# As always, make sure to validate this script against the current official installation guide that
# can be found on the Arch Wiki, to ensure that the installation proceeds reliably.
#
# This script is a heavily based off the work of Tommaso Chiti. His script can be found here:
# https://github.com/classy-giraffe/easy-arch
#
# This script is a stripped-down version of Tommaso's script, custom tailored to my specific needs.
# If you want a more general script, you should definitely use Tommaso's script.
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
# | 2 | ROOT  | Rest    | /          | Btrfs      |
# +---+-------+---------+------------+------------+
#
#
# Btrfs subvolumes layout
# =======================
#
# The following layout is used, as suggested for Snapper here:
# https://wiki.archlinux.org/title/Snapper#Suggested_filesystem_layout
#
# +------------+-----------------------+
# | Name       | Mountpoint            |
# +------------+-----------------------+
# | @          | /                     |
# | @home      | /home                 |
# | @snapshots | /.snapshots           |
# | @var_log   | /var/log              |
# | @var_pkgs  | /var/cache/pacman/pkg |
# +------------+-----------------------+


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
    mkpart ${ROOT_LABEL} 513MiB 100% \

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

# Formatting the LUKS Container as Btrfs.
print "Formatting the LUKS container as Btrfs."
mkfs.btrfs ${CRYPTROOT} &>/dev/null
mount ${CRYPTROOT} /mnt

# Creating Btrfs subvolumes.
print "Creating Btrfs subvolumes."
for VOLUME in @ @home @snapshots @var_log @var_pkgs
do
    btrfs subvolume create /mnt/${VOLUME}
done

# Mounting the newly created subvolumes.
umount /mnt
print "Mounting the newly created subvolumes."
# Notes:
# - The flag `nodiratime` is not necessary, it is implied by `noatime`.
# - The flag `ssd` is not necessary, as Btrfs will automatically detect if a device is an SSD.
# - The flag `compress-force=zstd:1` is used instead of `compress=zstd:1`, because: https://www.reddit.com/r/archlinux/comments/npppg5/how_do_i_safely_switch_from_lzo_compression_to/
# - The flag `discard=async` is not used, and instead fstrim is used.
BTRFS_MOUNT_OPTIONS="noatime,compress-force=zstd:1,autodefrag,subvol="
# TODO: before changing the mount options to my variable thing, they were: ssd,noatime,compress-force=zstd:3,discard=async,subvol=@home
mount -o ${BTRFS_MOUNT_OPTIONS}@ ${CRYPTROOT} /mnt
mkdir -p /mnt/{home,.snapshots,/var/log,/var/cache/pacman/pkg,boot}
mount -o ${BTRFS_MOUNT_OPTIONS}@home ${CRYPTROOT} /mnt/home
mount -o ${BTRFS_MOUNT_OPTIONS}@snapshots ${CRYPTROOT} /mnt/.snapshots
mount -o ${BTRFS_MOUNT_OPTIONS}@var_log ${CRYPTROOT} /mnt/var/log
mount -o ${BTRFS_MOUNT_OPTIONS}@var_pkgs ${CRYPTROOT} /mnt/var/cache/pacman/pkg
chattr +C /mnt/var/log
mount ${BOOT_PARTITION} /mnt/boot

# Pacstrap (setting up a base sytem onto the new root).
print "Installing the base system (it may take a while)."
pacstrap /mnt base base-devel btrfs-progs efibootmgr grub grub-btrfs intel-ucode linux linux-firmware linux-headers rsync snapper snap-pac zram-generator

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
sed -i "/^MODULES=(/cMODULES=(btrfs)" /mnt/etc/mkinitcpio.conf
sed -i "/^HOOKS=(/cHOOKS=(base systemd autodetect keyboard sd-vconsole modconf block sd-encrypt filesystems)" /mnt/etc/mkinitcpio.conf
sed -i "/^COMPRESSION=(/cCOMPRESSION=(zstd)" /mnt/etc/mkinitcpio.conf

# Setting up LUKS2 encryption in GRUB.
print "Setting up GRUB config."
UUID=$(blkid -s UUID -o value ${ROOT_PARTITION})
sed -i "s,quiet,quiet rd.luks.name=${UUID}=${LUKS_MAPPING} root=${CRYPTROOT},g" /mnt/etc/default/grub

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
    
    # Snapper configuration.
    echo "Configuring Snapper."
    umount /.snapshots
    rm -r /.snapshots
    snapper --no-dbus -c root create-config /
    btrfs subvolume delete /.snapshots &>/dev/null
    mkdir /.snapshots
    mount -a
    chmod 750 /.snapshots
    
    # Installing GRUB.
    echo "Installing GRUB on /boot."
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB &>/dev/null

    # Creating GRUB config file.
    echo "Creating GRUB config file."
    grub-mkconfig -o /boot/grub/grub.cfg &>/dev/null
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

# Boot backup hook.
print "Configuring /boot backup when pacman transactions are made."
mkdir /mnt/etc/pacman.d/hooks
cat > /mnt/etc/pacman.d/hooks/50-bootbackup.hook <<EOF
[Trigger]
Operation = Upgrade
Operation = Install
Operation = Remove
Type = Path
Target = usr/lib/modules/*/vmlinuz

[Action]
Depends = rsync
Description = Backing up /boot...
When = PostTransaction
Exec = /usr/bin/rsync -a --delete /boot /.bootbackup
EOF

# ZRAM configuration.
print "Configuring zram."
cat > /mnt/etc/systemd/zram-generator.conf <<EOF
[zram0]
zram-fraction = 1
max-zram-size = 8192
EOF

# Enabling various services.
print "Enabling automatic snapshots, Btrfs scrubbing, and systemd-oomd."
for SERVICE in snapper-timeline.timer snapper-cleanup.timer btrfs-scrub@-.timer btrfs-scrub@home.timer btrfs-scrub@var-log.timer btrfs-scrub@\\x2esnapshots.timer grub-btrfs.path systemd-oomd
do
    systemctl enable "${SERVICE}" --root=/mnt &>/dev/null
done

# Finishing up.
umount -a &>/dev/null
print "The installer script is done."
exit
