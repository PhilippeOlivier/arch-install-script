#!/bin/bash


# Make sure to follow the official installation guide in parallel to this one, in case some things
# changed in the official guide. If so, update the current guide.

# use shorturl.at to shorten this url, then: curl -L THEURL > install.sh, and then sh install.sh


DRIVE="/dev/sda" # TODO: CHANGE TO /dev/nm...
LUKS_MAPPING="cryptroot"
LUKS_PASSPHRASE="asdf"
MARKER="=====> "
HOSTNAME="pholi"


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
	# TODO: set 1 esp on was previously set 1 boot on. Does it still work now?
	echo -n "${MARKER}Partitioning drive ${DRIVE}... "
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
		echo "${MARKER}Enter the LUKS passphrase: "
		stty -echo
		read LUKS_PASSPHRASE
		stty echo
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
#   LUKS_MAPPING
# Arguments:
#   None
# Outputs:
#   General status
###############################################################################
create_btrfs_subvolumes() {
	echo "${MARKER}Creating Btrfs subvolumes... "
	mount "/dev/mapper/${LUKS_MAPPING}" "/mnt"
	btrfs subvolume create "/mnt/@"
	btrfs subvolume create "/mnt/@home"
	umount "/mnt"

	echo "${MARKER}Mounting Btrfs subvolumes..."
	local mount_options
	# # TODO: Look at the following options and make sure that this is what I want.
	# mount_options="noatime,nodiratime,compress=zstd:1,space_cache,ssd"
	# mount -o "${mount_options},subvol=@" "/dev/mapper/${LUKS_MAPPING}" "/mnt"
	# mkdir -p /mnt/{boot,home}
	# mount -o "${mount_options},subvol=@home" "/dev/mapper/${LUKS_MAPPING}" "/mnt/home"
	# mount "${BOOT_PARTITION}" "/mnt/boot"

	mount -o ssd,noatime,compress-force=zstd:3,discard=async,subvol=@ "/dev/mapper/${LUKS_MAPPING}" "/mnt"
	mkdir -p /mnt/{boot,home}
	mount -o ssd,noatime,compress-force=zstd:3,discard=async,subvol=@home "/dev/mapper/${LUKS_MAPPING}" "/mnt/home"
	mount "${BOOT_PARTITION}" "/mnt/boot"
}


################################################################################
# Installs base packages. Linux-LTS is installed as a backup kernel.
# Globals:
#   BOOT_PARTITION
#   LUKS_MAPPING
# Arguments:
#   None
# Outputs:
#   General status
###############################################################################
install_base_packages() {
	echo "${MARKER}Installing base packages..."
	pacstrap /mnt base base-devel btrfs-progs intel-ucode linux linux-firmware linux-lts vim
	genfstab -U /mnt >> /mnt/etc/fstab
}


################################################################################
# Performs some basic configurations.
# Arguments:
#   None
# Outputs:
#   General status
###############################################################################
basic_configuration() {
	echo "${MARKER}Updating system clock and synching time... "
	systemctl enable systemd-timesyncd.service
    systemctl start systemd-timesyncd.service
	timedatectl set-ntp true

	arch-chroot "/mnt"
	
	echo "${MARKER}Setting time zone..."
	ln -sf /usr/share/zoneinfo/Canada/Eastern /etc/localtime
	hwclock --systohc

	echo "${MARKER}Setting locale..."
}


wipe_everything
internet_connectivity
boot_mode
# set_system_clock
partition_drive
encrypt_primary_partition
format_partitions
create_btrfs_subvolumes
install_base_packages
basic_configuration
