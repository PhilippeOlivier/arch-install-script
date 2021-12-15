#!/bin/bash


# Make sure to follow the official installation guide in parallel to this one, in case some things
# changed in the official guide. If so, update the current guide.


DRIVE="/dev/sda" # TODO: CHANGE TO /dev/nm...
MAPPING="cryptroot"


################################################################################
# Identifies drive partitions.
# Globals:
#   DRIVE
#   BOOT_PARTITION
#   ROOT_PARTITION
# Arguments:
#   None
# Outputs:
#   General status
###############################################################################
identify_partitions() {
	echo -n "Identifying partitions on drive ${DRIVE}... "
	if [[ "$DRIVE" =~ ^\/dev\/sd ]]; then
		BOOT_PARTITION="${DRIVE}1"
		ROOT_PARTITION="${DRIVE}2"
	elif [[ "$DRIVE" =~ ^\/dev\/nvm ]]; then
		BOOT_PARTITION="${DRIVE}p1"
		ROOT_PARTITION="${DRIVE}p2"
	else
		echo "Error.."
		exit
	fi
	echo "OK."
	echo -e "\tBoot partition: ${BOOT_PARTITION}"
	echo -e "\tRoot partition: ${ROOT_PARTITION}"
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
system_clock() {
	echo -n "Updating system clock and synching time... "
	systemctl enable systemd-timesyncd.service
    systemctl start systemd-timesyncd.service
	timedatectl set-ntp true
	echo "OK."
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
	echo -n "Partitioning drive ${DRIVE}... "
	parted -s "${DRIVE}" \
		   mklabel gpt \
		   mkpart ESP fat32 1MiB 513MiB \
		   set 1 boot on \
		   mkpart primary btrfs 513MiB 100%
	echo "OK."
}


################################################################################
# Formats the boot partition.
# Globals:
#   BOOT_PARTITION
# Arguments:
#   None
# Outputs:
#   General status
###############################################################################
format_boot_partition() {
	echo -n "Formatting boot partition ${BOOT_PARTITION}... "
	mkfs.vfat -F 32 "${BOOT_PARTITION}"
	echo "OK."
}


identify_partitions
internet_connectivity
boot_mode
# system_clock
# partition_drive
# format_boot_partition




# # Encrypt and format the root partition
# cryptsetup luksFormat $ROOT_PART
# cryptsetup open $ROOT_PART cryptroot
# mkfs.btrfs /dev/mapper/cryptroot

# # Mount the file systems and create the subvolumes.
# mount /dev/mapper/cryptroot /mnt
# btrfs subvolume create /mnt/@
# btrfs subvolume create /mnt/@home
# umount /mnt

# # TODO: modify options below eventually
# mount -o noatime,nodiratime,compress=zstd:1,space_cache,ssd,subvol=@ /dev/mapper/cryptroot /mnt
# mkdir -p /mnt/{boot,home}
# mount -o noatime,nodiratime,compress=zstd:1,space_cache,ssd,subvol=@home /dev/mapper/cryptroot /mnt/home
# mount /dev/nvme0n1p1 /mnt/boot
