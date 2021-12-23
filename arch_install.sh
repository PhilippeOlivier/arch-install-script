#!/bin/bash


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
# Some parts of this script are somewhat inspired by https://github.com/classy-giraffe/easy-arch
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
# +---+---------+---------+------------+------------+
# | # | Label   | Size    | Mountpoint | Filesystem |
# +---+---------+---------+------------+------------+
# | 1 | ESP     | 512 MiB | /boot      | FAT32      |
# | 2 | PRIMARY | Rest    | /          | Btrfs      |
# +---+---------+---------+------------+------------+
#
#
# Btrfs subvolumes layout
# =======================
#
# The following layout is used, as suggested for Snapper here:
# https://wiki.archlinux.org/title/Snapper#Suggested_filesystem_layout
#
# +------------+-------------+
# | Name       | Mountpoint  |
# +------------+-------------+
# | @          | /           |
# | @home      | /home       |
# | @snapshots | /.snapshots |
# | @var_log   | /var/log    |
# +------------+-------------+


DRIVE="/dev/sda"
LUKS_PASSPHRASE="asdf"
ROOT_PASSWORD="asdf"
USER_NAME="pholi"
USER_PASSWORD="asdf"

LUKS_MAPPING="cryptroot"
HOSTNAME="pholi-arch"
LOCALE="en_CA.UTF-8 UTF-8"
TIME_ZONE="Canada/Eastern"
# MODULES="btrfs"
# HOOKS="base systemd autodetect keyboard keymap modconf block sd-encrypt filesystems"

MARKER="=====> "


################################################################################
# Wipes everything from the drive.
# Globals:
#   DRIVE
# Arguments:
#   None
# Outputs:
#   General status
###############################################################################
wipe_everything() {
	echo "${MARKER}Wiping everything on ${DRIVE}... "
	wipefs -af $(lsblk -lpoNAME | grep -P "${DRIVE}" | sort -r)
    sgdisk -Zo "${DRIVE}"
}


################################################################################
# Checks for internet connectivity.
# Arguments:
#   None
# Outputs:
#   General status
###############################################################################
internet_connectivity() {
	echo -n "${MARKER}Checking for internet connection... "
	if ping -q -c 1 -W 1 8.8.8.8 > /dev/null; then
		echo "OK."
	else
		echo "Error."
		exit
	fi
}


################################################################################
# Checks for UEFI boot mode.
# Arguments:
#   None
# Outputs:
#   General status
###############################################################################
boot_mode() {
	echo -n "${MARKER}Checking for UEFI boot mode... "
	if [[ -d "/sys/firmware/efi/efivars" ]]; then
		echo "OK."
	else
		echo "Error."
		exit
	fi
}


################################################################################
# Partitions the drive and identifies the partitions.
# Globals:
#   BOOT_PARTITION
#   DRIVE
#   PRIMARY_PARTITION
# Arguments:
#   None
# Outputs:
#   General status
###############################################################################
partition_drive() {
	echo -n "${MARKER}Partitioning drive ${DRIVE}... "
	parted -s "${DRIVE}" \
		   mklabel gpt \
		   mkpart ESP fat32 1MiB 513MiB \
		   set 1 esp on \
		   mkpart PRIMARY 513MiB 100%
	# Inform the kernel of the changes.
	partprobe "${DRIVE}"
	# Identify partitions.
	BOOT_PARTITION="/dev/disk/by-partlabel/ESP"
	PRIMARY_PARTITION="/dev/disk/by-partlabel/PRIMARY"
	echo "OK."
	echo -e "\tBoot partition: ${BOOT_PARTITION}"
	echo -e "\tPrimary partition: ${PRIMARY_PARTITION}"
}


################################################################################
# Encrypts the primary partition.
# Globals:
#   LUKS_MAPPING
#   LUKS_PASSPHRASE
#   PRIMARY_PARTITION
# Arguments:
#   None
# Outputs:
#   General status
###############################################################################
encrypt_primary_partition() {
	# If no LUKS password is provided, prompt the user for one.
	if [[ -z "${LUKS_PASSPHRASE}" ]]; then
		read -r -s -p "${MARKER}Enter the LUKS passphrase: " LUKS_PASSPHRASE
	fi

	echo "${MARKER}Encrypting primary partition ${PRIMARY_PARTITION}... "
	echo -n "${LUKS_PASSPHRASE}" | cryptsetup luksFormat --type luks2 "${PRIMARY_PARTITION}" -d -
	echo -n "${LUKS_PASSPHRASE}" | cryptsetup open --type luks2 "${PRIMARY_PARTITION}" "${LUKS_MAPPING}" -d -
}



################################################################################
# Formats the partitions.
# Globals:
#   BOOT_PARTITION
#   LUKS_MAPPING
# Arguments:
#   None
# Outputs:
#   General status
###############################################################################
format_partitions() {
	echo "${MARKER}Formatting partitions... "
	mkfs.vfat -F 32 "${BOOT_PARTITION}"
	mkfs.btrfs "/dev/mapper/${LUKS_MAPPING}"
}


################################################################################
# Creates Btrfs subvolumes and mounts them.
# Globals:
#   BOOT_PARTITION
#   LUKS_MAPPING
# Arguments:
#   None
# Outputs:
#   General status
###############################################################################
create_btrfs_subvolumes() {
	echo "${MARKER}Creating Btrfs subvolumes... "
	mount "/dev/mapper/${LUKS_MAPPING}" /mnt
	for volume in @ @home @snapshots @var_log; do
		btrfs subvolume create /mnt/$volume
	done
	umount /mnt

	echo "${MARKER}Mounting Btrfs subvolumes..."
	local mount_options
	# # TODO: Look at the following options and make sure that this is what I want.
	# mount_options="noatime,nodiratime,compress=zstd:1,space_cache,ssd"
	# mount -o "${mount_options},subvol=@" "/dev/mapper/${LUKS_MAPPING}" "/mnt"
	# mkdir -p /mnt/{boot,home}
	# mount -o "${mount_options},subvol=@home" "/dev/mapper/${LUKS_MAPPING}" "/mnt/home"
	# mount "${BOOT_PARTITION}" "/mnt/boot"

	mount -o ssd,noatime,compress-force=zstd:3,discard=async,subvol=@ "/dev/mapper/${LUKS_MAPPING}" /mnt
	mkdir -p /mnt/{boot,home,.snapshots,/var/log}
	mount -o ssd,noatime,compress-force=zstd:3,discard=async,subvol=@home "/dev/mapper/${LUKS_MAPPING}" /mnt/home
	mount -o ssd,noatime,compress-force=zstd:3,discard=async,subvol=@snapshots "/dev/mapper/${LUKS_MAPPING}" /mnt/.snapshots
	mount -o ssd,noatime,compress-force=zstd:3,discard=async,subvol=@var_log "/dev/mapper/${LUKS_MAPPING}" /mnt/var/log
	# Note sure I need the chattr command...?
	chattr +C /mnt/var/log
	mount "${BOOT_PARTITION}" /mnt/boot
}


################################################################################
# Installs base packages. Linux-LTS is installed as a backup kernel.
# Arguments:
#   None
# Outputs:
#   General status
###############################################################################
install_base_packages() {
	echo "${MARKER}Installing base packages..."
	# todo: remove vim
	pacstrap /mnt base base-devel btrfs-progs efibootmgr grub grub-btrfs intel-ucode linux linux-firmware linux-lts snap-pac snapper vim
	genfstab -U /mnt >> /mnt/etc/fstab
}


################################################################################
# Performs some basic configurations.
# Globals:
#   LOCALE
#   HOOKS
#   HOSTNAME
#   MODULES
#   ROOT_PASSWORD
#   TIME_ZONE
#   USER_NAME
#   USER_PASSWORD
# Arguments:
#   None
# Outputs:
#   General status
###############################################################################
basic_configuration() {
	# If no root password is provided, prompt the user for one.
	if [[ -z "${ROOT_PASSWORD}" ]]; then
		read -r -s -p "${MARKER}Enter the root_password: " ROOT_PASSWORD
	fi
	# If no user password is provided, prompt the user for one.
	if [[ -z "${USER_PASSWORD}" ]]; then
		read -r -s -p "${MARKER}Enter the user password: " USER_PASSWORD
	fi
	
	#cat > /mnt/basic_configuration.sh <<EOFAC
	arch-chroot /mnt /bin/bash <<EOFAC
	echo "${MARKER}Updating system clock and synching time... "
	systemctl enable systemd-timesyncd.service
    systemctl start systemd-timesyncd.service
	timedatectl set-ntp true
	
	echo "${MARKER}Setting time zone..."
	ln -sf "/usr/share/zoneinfo/${TIME_ZONE}" /etc/localtime
	hwclock --systohc

	echo "${MARKER}Setting locale..."
	# Uncomment relevant locale in /etc/locale.gen.
	sed -i "/^#${LOCALE}/c${LOCALE}" /etc/locale.gen
	locale-gen
	echo "LANG=en_CA.UTF-8" > /etc/locale.conf

	echo "${MARKER}Setting hostname..."
	echo "${HOSTNAME}" > /etc/hostname
	cat > /etc/hosts <<EOF
127.0.0.1 localhost
::1 localhost
127.0.1.1 ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

	echo "${MARKER}Setting user and passwords..."
	echo "root:${ROOT_PASSWORD}" | chpasswd
	useradd -m -G wheel -s /bin/bash "${USER_NAME}"
	echo "${USER_NAME} ALL=(ALL) ALL" >> /etc/sudoers
	echo "${USER_NAME}:${USER_PASSWORD}" | chpasswd
	echo "${MARKER}Setting mkinitcpio options..."
	sed -i "/^MODULES=(/cMODULES=(btrfs)" /etc/mkinitcpio.conf
	sed -i "/^HOOKS=(/cHOOKS=(base systemd autodetect keyboard keymap modconf block sd-encrypt filesystems)" /etc/mkinitcpio.conf
	sed -i "/^COMPRESSION=(/cCOMPRESSION=(zstd)" /etc/mkinitcpio.conf

	exit
EOFAC

	# echo "${MARKER}Chroot... "
	# arch-chroot /mnt ./basic_configuration.sh
}


################################################################################
# Sets up the bootloader.
# Globals:
#   LUKS_MAPPING
#   PRIMARY_PARTITION
#   PRIMARY_PARTITION_UUID
# Arguments:
#   None
# Outputs:
#   General status
###############################################################################
bootloader() {
	# I used to have these 3 lines below "initrd /initramfs-linux.img"
	# options rd.luks.name=${PRIMARY_PARTITION_UUID}=${LUKS_MAPPING} root=/dev/mapper/${LUKS_MAPPING}
	# rootflags=subvol=@ rd.luks.options=${PRIMARY_PARTITION_UUID}=discard rw quiet
	# lsm=lockdown,yama,apparmor,bpf
	
	# the 2 lines are TEMP:
	BOOT_PARTITION="/dev/disk/by-partlabel/ESP"
	PRIMARY_PARTITION="/dev/disk/by-partlabel/PRIMARY"
	# the following line is not temp
	PRIMARY_PARTITION_UUID="$(blkid -s UUID -o value ${PRIMARY_PARTITION})"
	echo "================prim1: ${PRIMARY_PARTITION_UUID}"
	# TODO: grub and grub-btrfs, and luks1?
	arch-chroot /mnt /bin/bash <<EOFAC
	echo "${MARKER}Setting up the bootloader... "
	echo "================prim2: ${PRIMARY_PARTITION_UUID}"

sed -i "s,quiet,quiet rd.luks.name=${PRIMARY_PARTITION_UUID}=cryptroot root=/dev/mapper/${LUKS_MAPPER},g" /etc/default/grub

    # Snapper configuration
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
    grub-install --target=x86_64-efi --efi-directory=/boot/ --bootloader-id=GRUB &>/dev/null
    # Creating grub config file.
    echo "Creating GRUB config file."
    grub-mkconfig -o /boot/grub/grub.cfg &>/dev/null


	mkinitcpio -P
exit
EOFAC

	# echo "${MARKER}Chroot... "
	# arch-chroot /mnt ./bootloader.sh
}


################################################################################
# Rebooting.
# Arguments:
#   None
# Outputs:
#   General status
###############################################################################
reboot() {
	echo "${MARKER}Preparing for reboot... "
	# exit
	umount -a
	shutdown now
}



wipe_everything
internet_connectivity
boot_mode
partition_drive
encrypt_primary_partition
format_partitions
create_btrfs_subvolumes
install_base_packages
basic_configuration
bootloader
# reboot
