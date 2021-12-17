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
	wipefs -af "${DRIVE}"
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
# Partitions the drive.
# Globals:
#   DRIVE
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
		   mkpart PRIMARY btrfs 513MiB 100%
	# Inform the OS of the changes.
	partprobe "${DRIVE}"
	echo "OK."
}



################################################################################
# Identifies drive partitions.
# Globals:
#   BOOT_PARTITION
#   PRIMARY_PARTITION
# Arguments:
#   None
# Outputs:
#   General status
###############################################################################
identify_partitions() {
	echo -n "Identifying partitions on drive ${DRIVE}... "
	BOOT_PARTITION="/dev/disk/by-partlabel/ESP"
	PRIMARY_PARTITION="/dev/disk/by-partlabel/PRIMARY"
	echo "OK."
	echo -e "\tBoot partition: ${BOOT_PARTITION}"
	echo -e "\tPrimary partition: ${PRIMARY_PARTITION}"
}


################################################################################
# Encrypts the primary partition.
# Globals:
#   LUKS_MAPPER
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
	echo "1-luksFormat"
	echo -n "${LUKS_PASSPHRASE}" | cryptsetup luksFormat --type luks2 "${PRIMARY_PARTITION}" -d -
	echo "2-luks open"
	echo -n "${LUKS_PASSPHRASE}" | cryptsetup open -q --type luks2 "${PRIMARY_PARTITION}" "${LUKS_MAPPER}" -d -
	# device-mapper: create ioctl on CRYPT-LUKS2-[uuid_of_the_partition]- failed: Invalid argument
	# sleep 5
	#TODO: only do luksformat automatically, then try to open manually
	# TODO: try to set passphrase manually in the script, and see if things change
	# TODO: if passphrase is empty ask for one, if there is a passphrase then use it without prompting the user
	# echo "3-mkfs btrfs"
	# mkfs.btrfs "/dev/mapper/${LUKS_MAPPER}"
}



################################################################################
# Formats the partition.
# Globals:
#   BOOT_PARTITION
#   PRIMARY_PARTITION
# Arguments:
#   None
# Outputs:
#   General status
###############################################################################
format_boot_partition() {
	echo "Formatting boot partition ${BOOT_PARTITION}... "
	mkfs.vfat -F 32 "${BOOT_PARTITION}"
		# TODO: format boot and primary should happen together, after LUKS stuff has been done
}


################################################################################
# Creates Btrfs subvolumes.
# Globals:
#   LUKS_MAPPER
# Arguments:
#   None
# Outputs:
#   General status
###############################################################################
create_btrfs_subvolumes() {
	echo -n "Creating Btrfs subvolumes... "
	mount "/dev/mapper/${LUKS_MAPPER}" "/mnt"
	btrfs subvolume create "/mnt/@"
	btrfs subvolume create "/mnt/@home"
	umount "/mnt"
	echo "OK."
}


################################################################################
# Installs base packages.
# Globals:
#   BOOT_PARTITION
#   LUKS_MAPPER
# Arguments:
#   None
# Outputs:
#   General status
###############################################################################
install_base_packages() {
	local mount_options
	# TODO: Look at the following options and make sure that this is what I want.
	mount_options="noatime,nodiratime,compress=zstd:1,space_cache,ssd"
	echo -n "Creating Btrfs subvolumes... "
	mount -o "${mount_options},subvol=@" "/dev/mapper/${LUKS_MAPPER}" "/mnt"
	mkdir -p /mnt/{boot,home}
	mount -o "${mount_options},subvol=@home" "/dev/mapper/${LUKS_MAPPER}" "/mnt/home"
	mount "${BOOT_PARTITION}" "/mnt/boot"
	pacstrap /mnt base base-devel btrfs-progs intel-ucode linux linux-firmware linux-lts vim
	genfstab -U /mnt >> /mnt/etc/fstab
	echo "OK."
}


wipe_everything
internet_connectivity
boot_mode
set_system_clock
partition_drive
indentify_partitions
encrypt_primary_partition


#format_boot_partition
# create_btrfs_subvolumes
# install_base_packages
