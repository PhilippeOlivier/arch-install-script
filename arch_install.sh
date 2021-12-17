#!/bin/bash


# Make sure to follow the official installation guide in parallel to this one, in case some things
# changed in the official guide. If so, update the current guide.

# use shorturl.at to shorten this url, then: curl -L THEURL > install.sh, and then sh install.sh


DRIVE="/dev/sda" # TODO: CHANGE TO /dev/nm...
LUKS_MAPPING="cryptroot"
LUKS_PASSPHRASE="asdf"


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
	echo -n "Wiping everything on ${DRIVE}... "
	wipefs -af /dev/sda1 /dev/sda2 /dev/sda
    sgdisk -Zo "${DRIVE}"
	# wipefs -af "${DRIVE}"
    # sgdisk -Zo "${DRIVE}"
}


################################################################################
# Checks for internet connectivity.
# Arguments:
#   None
# Outputs:
#   General status
###############################################################################
internet_connectivity() {
	echo -n "Checking for internet connection... "
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
	echo -n "Checking for UEFI boot mode... "
	if [[ -d "/sys/firmware/efi/efivars" ]]; then
		echo "OK."
	else
		echo "Error."
		exit
	fi
}


################################################################################
# Updates system clock and synchs time.
# Arguments:
#   None
# Outputs:
#   General status
###############################################################################
set_system_clock() {
	echo "Updating system clock and synching time... "
	systemctl enable systemd-timesyncd.service
    systemctl start systemd-timesyncd.service
	timedatectl set-ntp true
	# Wait until those actions are complete before continuing.
	sleep 10
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
	# TODO: set 1 esp on was previously set 1 boot on. Does it still work now?
	echo -n "Partitioning drive ${DRIVE}... "
	parted -s "${DRIVE}" \
		   mklabel gpt \
		   mkpart ESP fat32 1MiB 513MiB \
		   set 1 esp on \
		   mkpart PRIMARY 513MiB 100%
	# Inform the OS of the changes.
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
	# If no password is provided, prompt the user for one.
	if [[ -z "${LUKS_PASSPHRASE}" ]]; then
		echo "Enter the LUKS passphrase: "
		stty -echo
		read LUKS_PASSPHRASE
		stty echo
	fi

	echo "Encrypting primary partition ${PRIMARY_PARTITION}... "
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
	echo "Formatting partitions... "
	mkfs.vfat -F 32 "${BOOT_PARTITION}"
	mkfs.btrfs "/dev/mapper/${LUKS_MAPPING}"
}


################################################################################
# Creates Btrfs subvolumes and mounts them.
# Globals:
#   LUKS_MAPPING
# Arguments:
#   None
# Outputs:
#   General status
###############################################################################
create_btrfs_subvolumes() {
	echo "Creating Btrfs subvolumes... "
	mount "/dev/mapper/${LUKS_MAPPING}" "/mnt"
	btrfs subvolume create "/mnt/@"
	btrfs subvolume create "/mnt/@home"
	echo "DOne creating subvolumes"
	umount "/mnt"

	# # Mounting Btrfs subvolumes...
	# local mount_options
	# # TODO: Look at the following options and make sure that this is what I want.
	# mount_options="noatime,nodiratime,compress=zstd:1,space_cache,ssd"
	# mount -o "${mount_options},subvol=@" "/dev/mapper/${LUKS_MAPPING}" "/mnt"
	# mkdir -p /mnt/{boot,home}
	# mount -o "${mount_options},subvol=@home" "/dev/mapper/${LUKS_MAPPING}" "/mnt/home"
	# mount "${BOOT_PARTITION}" "/mnt/boot"
	
	echo "OK."
}


################################################################################
# Installs base packages.
# Globals:
#   BOOT_PARTITION
#   LUKS_MAPPING
# Arguments:
#   None
# Outputs:
#   General status
###############################################################################
install_base_packages() {
	pacstrap /mnt base base-devel btrfs-progs intel-ucode linux linux-firmware linux-lts vim
	genfstab -U /mnt >> /mnt/etc/fstab
}


wipe_everything
internet_connectivity
boot_mode
# set_system_clock
partition_drive
encrypt_primary_partition
format_partitions
create_btrfs_subvolumes
#install_base_packages

#lsblk -lpoNAME | grep -P "/dev/nvme0n1" | sort -r

#
# 
# 
