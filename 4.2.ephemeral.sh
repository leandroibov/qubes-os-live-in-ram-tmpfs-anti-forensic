#!/bin/bash

#how use:
#open dom0 terminal
#open vault qube
#copy the script ephemeral.sh in /home/user/ of vault qube
#open the terminal of dom0
#run the command
#sudo qvm-run --pass-io vault 'cat "/home/user/ephemeral.sh"' > /home/user/ephemeral.sh;
#ls /home/user #see the ephemeral.sh
#sudo chmod +x ephemeral.sh
#sudo ./ephemeral.sh


check_root_ram ()
{

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root or use sudo."
    sleep 4
    exit 1
fi

# Determine which device is mounted as / , if is zram, the program will stop...
root_dev=$(findmnt -n -o SOURCE /)

# Strip the leading "/dev/" so we only keep the device name (e.g., "zram0").
# This makes the pattern match easier.
root_dev=${root_dev#/dev/}

# Abort if the device name starts with "zram".
if [[ $root_dev == zram* ]]; then
    echo "⚠️  dom0 is mounted on ZRAM ($root_dev)."
    echo "    Aborting to avoid creating a wrong GRUB or initramfs that could render the system unbootable."
    # Optional pause so the user can read the warning.
    sleep 6
    exit 1
else
    echo "✅  dom0 is NOT on ZRAM (root = $root_dev)."
    echo "    Continuing with the rest of the script."
fi

#obsolete but works in qubes 4.2, but not in qubes 4.3
#if [[ -e /sys/block/zram0 ]]; then
#    echo "Detected /sys/block/zram0 – zram is active on this system."
#   echo "Aborting script execution to avoid creating a faulty GRUB or initramfs."
#   echo "Ephemeral must be executed only in the persistent dom0, not when mounted in RAM!"
#sleep 6
#    exit 1
#fi
}


ephemeral_qubes ()
{
#check_root_ram

# Calculating the total RAM in Qubes OS from hardware memory using dmidecode
total_ram=$(sudo dmidecode -t memory \
    | awk '/Size:/ && $2 != "No" {
            gsub(/GB|MB/, "", $2);
            sum += ($2 ~ /MB/ ? $2/1024 : $2)
        }
        END { printf "%.2f", sum }')

total_ram_mb=$(awk "BEGIN { printf \"%d\", $total_ram * 1024 }")

# Calculate the total size of the dom0 file and ensure the used space does not exceed the RAM value chosen by the user
mount_point=$(df --output=target /var/lib/qubes | tail -n1)
used_human=$(df -h "$mount_point" | awk 'NR==2 {print $3}')
size_gb=${used_human%G}
size_gb=${size_gb/,/.}

if ! [[ "$size_gb" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "“Could not interpret the size.”: '$used_human'"
sleep 3
    exit 1
fi

size_mb=$(awk "BEGIN { printf \"%d\", $size_gb * 1024 }")


# Prompt for the desired amount of RAM in megabytes
#/dev/qubes_dom0/root – need to check the size used to choose the RAM memory required for running other Qubes beyond it.

#treatment to do...
#if total RAM is less than 8 GB the program will warning and turn off
#no while se  if (( ram_input < size_mb )); then , avisa e volta o loop do while sem break...

echo;
echo "Total RAM available is $total_ram GB or $total_ram_mb megabytes"
echo "Dom0 total size used: $size_gb GB ($size_mb MB)"
echo "Enter the amount of RAM tmpfs for dom0 in megabytes"
echo "It must be no larger than the used size of dom0 and no larger than the total available RAM"
echo "Minimum recommended: 8 GB = 8000 megabytes"
echo "Ideally suited for systems with 16 GB of RAM or more"
echo "Recommended Minimum 10240 for 16 GB of RAM"
echo "Recommended Minimum 16240 for 32 GB of RAM"
echo

#anchient code
#read -p "Enter the RAM amount (megabytes):" ram

# Validate the input
#if ! [[ "$ram" =~ ^[0-9]+$ ]] || [ "$ram" -lt 10240 ]; then
#    echo "Invalid value. The minimum is 10240 megabytes. Try Again!"
#    exit 1
#fi

while true; do
        # Ask the user
        read -p "Enter the RAM amount (megabytes): " ram_input

        # Strip any whitespace the user might have typed
        ram_input=$(echo "$ram_input" | tr -d '[:space:]')

        # ----- Validate that the input is a positive integer -----
        if ! [[ $ram_input =~ ^[0-9]+$ ]]; then
            echo "Please enter a positive integer number."
            continue
        fi

        # ----- Compare against the total RAM -----
        if (( ram_input > total_ram_mb )); then
            echo "Requested memory ($ram_input MB) exceeds the total RAM ($total_ram_mb MB)."
            echo "Please enter a value **at most** $total_ram_mb MB."
            continue
        fi

# ----- Compare against the total size of files in dom0 -----
        if (( ram_input < size_mb )); then
        echo "Requested memory ($ram_input MB) is less than the total size of all files in dom0 ($size_mb MB)."
        echo "Please enter a value **equal to or greater than** $size_mb MB."

            continue
        fi

        # If we reach this point the value is acceptable
        ram=$ram_input
        break
    done
echo

# Set the maxram variable
maxram="$ram"
zram_size=$(( maxram / 1000 * 1000 / 1000 ))


#to test
#echo "ZRAM size (GB): $zram_size"

# Backup the grub file
echo "Backup the grub file";
sudo cp /etc/default/grub /etc/default/grub.bak

# New line to be inserted in /etc/default/grub
new_line="GRUB_CMDLINE_XEN_DEFAULT=\"console=none dom0_mem=min:1096M dom0_mem=max:${maxram}M ucode=scan smt=off gnttab_max_frames=2048 gnttab_max_maptrack_frames=4096\""

# Remove the existing line in the grub file
sudo sed -i "/^GRUB_CMDLINE_XEN_DEFAULT=/d" /etc/default/grub
echo "$new_line" >> /etc/default/grub
echo "GRUB configuration updated successfully."
echo;

# Backup the fstab file
echo "Backup the fstab file";
sudo cp /etc/fstab /etc/fstab.bak

# New line 2 to be inserted in /etc/fstab to disable swap
#new_line2="#/dev/mapper/qubes_dom0-swap none                    swap    defaults,x-systemd.device-timeout=0 0 0"

# Remove the swap line in the fstab file
sudo sed -i '\|/dev/mapper/qubes_dom0-swap none\s\+swap\s\+defaults,x-systemd.device-timeout=0 0 0|d' /etc/fstab
#echo "$new_line" >> /etc/fstab
echo "fstab file configuration without swap updated successfully."
echo;


# Function to display options
function show_options {
    echo "Choose the Qubes version:"
    echo "1) Qubes 4.1"
    echo "2) Qubes 4.2"
}

# Loop until the user makes a valid choice
while true; do
    show_options
    read -p "Enter your choice (1 or 2): " choice

    case $choice in
        1)
            echo "Executing commands for Qubes 4.1..."
            sudo grub2-mkconfig -o /boot/grub2/grub.cfg
            sudo grub2-mkconfig -o /boot/efi/EFI/grub.cfg
            echo "GRUB configuration for Qubes 4.1 completed."
            break
            ;;
        2)
            echo "Executing commands for Qubes 4.2..."
            sudo grub2-mkconfig -o /boot/grub2/grub.cfg
            echo "GRUB configuration for Qubes 4.2 completed."
            break
            ;;
        *)
            echo "Invalid option. Please choose 1 or 2."
            ;;
    esac
done
echo;

# Create new directory for Dracut Automation Module
echo "Creating new directory for Dracut Automation Module..."
sudo mkdir -p /usr/lib/dracut/modules.d/01ramboot

# Create new Dracut script file module-setup.sh
echo "Creating new Dracut script file module-setup.sh..."
sudo touch /usr/lib/dracut/modules.d/01ramboot/module-setup.sh

# Write content to module-setup.sh using EOF
sudo tee /usr/lib/dracut/modules.d/01ramboot/module-setup.sh > /dev/null <<'EOF'
#!/usr/bin/bash
check() {
return 0
}
depends() {
return 0
}
install() {
inst_simple "$moddir/tmpfs.sh" "/usr/bin/tmpfs"
inst_hook cleanup 00 "$moddir/pass.sh"
}
EOF

# Make the script executable
echo "Making module-setup.sh executable..."
sudo chmod +x /usr/lib/dracut/modules.d/01ramboot/module-setup.sh

echo "Dracut automation module setup completed."
echo;


# Create pass.sh
echo "Creating pass.sh..."
sudo touch /usr/lib/dracut/modules.d/01ramboot/pass.sh
sudo chmod 755 /usr/lib/dracut/modules.d/01ramboot/pass.sh

# Write content to pass.sh using EOF
sudo tee /usr/lib/dracut/modules.d/01ramboot/pass.sh > /dev/null <<'EOF'
#!/usr/bin/bash
command -v ask_for_password >/dev/null || . /lib/dracut-crypt-lib.sh
PROMPT="Boot to RAM? (y/n)"
CMD="/usr/bin/tmpfs"
TRY="3"
ask_for_password --cmd "$CMD" --prompt "$PROMPT" --tries "$TRY" --ply-cmd "$CMD" --ply-prompt "$PROMPT" --ply-tries "$TRY" --tty-cmd "$CMD" --tty-prompt "$PROMPT" --tty-tries "$TRY" --tty-echo-off
EOF

# Make the pass.sh script executable
echo "Making pass.sh executable..."
sudo chmod +x /usr/lib/dracut/modules.d/01ramboot/pass.sh

echo "pass.sh setup completed."
echo;


# Create tmpfs.sh
echo "Creating tmpfs.sh..."
sudo touch /usr/lib/dracut/modules.d/01ramboot/tmpfs.sh
sudo chmod 755 /usr/lib/dracut/modules.d/01ramboot/tmpfs.sh

# Write content to tmpfs.sh using EOF
sudo tee /usr/lib/dracut/modules.d/01ramboot/tmpfs.sh > /dev/null <<'EOF'
#!/usr/bin/bash
read line
case "${line:-Nn}" in
[Yy]* )
mkdir /mnt
umount /sysroot
mount /dev/mapper/qubes_dom0-root /mnt
modprobe zram
#----------------------------
#----------------------------
#below line to replace after
echo "$zram_size"G
#end - below line to replace
#----------------------------
#----------------------------
/mnt/usr/sbin/mkfs.ext2 /dev/zram0
mount /dev/zram0 /sysroot
cp -a /mnt/* /sysroot
exit 0
;;
[Nn]* )
exit 0
;;
* )
exit 1
;;
esac
EOF


#replacing zram_size variable content to tmpfs.sh with sed
sed -i "s|^echo \"\$zram_size\"G.*$|echo ${zram_size}G > /sys/block/zram0/disksize|" /usr/lib/dracut/modules.d/01ramboot/tmpfs.sh



# Make the tmpfs.sh script executable
echo "Making tmpfs.sh executable..."
sudo chmod +x /usr/lib/dracut/modules.d/01ramboot/tmpfs.sh

echo "tmpfs.sh setup completed."
echo;



# Create Config File ramboot.conf
echo "Creating Config File ramboot.conf..."
sudo touch /etc/dracut.conf.d/ramboot.conf

# Write content to ramboot.conf using EOF
sudo tee /etc/dracut.conf.d/ramboot.conf > /dev/null <<'EOF'
add_drivers+=" zram "
add_dracutmodules+=" ramboot "
EOF
echo;

# Regenerate Dracut
echo "Regenerating Dracut..."
sudo dracut --verbose --force

echo "ramboot.conf setup completed and Dracut regenerated."
echo "";

# Define expected hashes and file paths
declare -A files
files=(
    ["/usr/lib/dracut/modules.d/01ramboot/module-setup.sh"]="cb3e802e9604dc9b681c844d6e8d72a02f2850909ede9feb7587e7f3c2f11b8a"
    ["/usr/lib/dracut/modules.d/01ramboot/pass.sh"]="a2750fa31c216badf58d71abbc5b92097e8be21da23bbae5779d9830e2fdd144"
    #["/usr/lib/dracut/modules.d/01ramboot/tmpfs.sh"]="d9e85c06c3478cc0cf65a4e017af1a4f9f9dd4ad87c71375e8d4604399f5217d"
    ["/etc/dracut.conf.d/ramboot.conf"]="60d69ee8f27f68a5ff66399f63a10900c0ea9854ea2ff7a77c68b2a422df4bef"
)

# Initialize a flag to track if any hash is incorrect
all_ok=true

# Check each file
for file in "${!files[@]}"; do
    expected_hash=${files[$file]}
    if [ -f "$file" ]; then
        actual_hash=$(sha256sum "$file" | awk '{ print $1 }')
        if [ "$actual_hash" != "$expected_hash" ]; then
            echo "Hash mismatch for $file: expected $expected_hash, got $actual_hash"
            all_ok=false
        fi
    else
        echo "File not found: $file"
        all_ok=false
    fi
done

# Final message
if $all_ok; then
    echo "All files are OK."
else
    echo "Some files have incorrect hashes or are missing."
fi
echo;

#ephemeral_qubes END OF METHOD
}


restore_original_qubes ()
{

#check_root_ram


# for testing: add `set -euo pipefail` at the beginning to abort immediately on error.

echo "Deleting /usr/lib/dracut/modules.d/01ramboot directory and Dracut configuration files..."
sudo rm -rf /usr/lib/dracut/modules.d/01ramboot;
echo "Deleting /etc/dracut.conf.d/ramboot.conf configuration file..."
sudo rm -rf /etc/dracut.conf.d/ramboot.conf;
echo "Regenerating Dracut..."
sudo dracut --verbose --force
echo;


echo "Restore original grub configuration..."
GRUB_BAK="/etc/default/grub.bak"


if [[ ! -e "$GRUB_BAK" ]]; then
    echo "⚠️  Warning: $GRUB_BAK does not exist."
    echo "The script cannot continue without this backup file."
    sleep 2;
    exit 1   # non‑zero exit code signals failure
fi

# If we reach this point the file exists
echo "✅  $GRUB_BAK found. Continuing with the program..."
#restore .bak of grub
sudo cp -r /etc/default/grub.bak /etc/default/grub;

echo "Restore original fstab configuration..."
fstab_bak="/etc/fstab.bak"
if [[ ! -e "$fstab_bak" ]]; then
    echo "⚠️  Warning: $fstab_bak does not exist."
    echo "The script cannot continue without this backup file."
    sleep 2;
    exit 1   # non‑zero exit code signals failure
fi

# If we reach this point the file exists
echo "✅  $fstab_bak found. Continuing with the program..."
#restore .bak of fstab
sudo cp -r /etc/fstab.bak /etc/fstab;

# Function to display options
function show_options {
    echo "Choose the Qubes version:"
    echo "1) Qubes 4.1"
    echo "2) Qubes 4.2"
}

# Loop until the user makes a valid choice
while true; do
    show_options
    read -p "Enter your choice (1 or 2): " choice

    case $choice in
        1)
            echo "Executing commands for Qubes 4.1..."
            sudo grub2-mkconfig -o /boot/grub2/grub.cfg
            sudo grub2-mkconfig -o /boot/efi/EFI/grub.cfg
            echo "GRUB configuration for Qubes 4.1 completed."
            break
            ;;
        2)
            echo "Executing commands for Qubes 4.2..."
            sudo grub2-mkconfig -o /boot/grub2/grub.cfg
            echo "GRUB configuration for Qubes 4.2 completed."
            break
            ;;
        *)
            echo "Invalid option. Please choose 1 or 2."
            ;;
    esac
done
echo;
echo "Reboot to verify...";

#restore_original_qubes END OF METHOD
}

anti_cold_boot()
{
echo
# Script to install dracut ram-wipe module
# from qubes forum post: https://forum.qubes-os.org/t/ram-wipe-in-dom0-protection-against-cold-boot-attack-in-qubes/39375

echo "Creating dracut ram-wipe module directories and files..."

# Create module directory
mkdir /usr/lib/dracut/modules.d/40ram-wipe/

# module-setup.sh
cat > /usr/lib/dracut/modules.d/40ram-wipe/module-setup.sh << 'EOF'
#!/bin/bash
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh

## Copyright (C) 2023 - 2025 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

# called by dracut
check() {
   require_binaries sync || return 1
   require_binaries sleep || return 1
   require_binaries dmsetup || return 1
   return 0
}

# called by dracut
depends() {
   return 0
}

# called by dracut
install() {
   inst_simple "/usr/libexec/ram-wipe/ram-wipe-lib.sh" "/lib/ram-wipe-lib.sh"
   inst_multiple sync
   inst_multiple sleep
   inst_multiple dmsetup
   inst_hook shutdown 40 "$moddir/wipe-ram.sh"
   inst_hook cleanup 80 "$moddir/wipe-ram-needshutdown.sh"
}

# called by dracut
installkernel() {
   return 0
}
EOF

chmod +x /usr/lib/dracut/modules.d/40ram-wipe/module-setup.sh

# wipe-ram-needshutdown.sh
cat > /usr/lib/dracut/modules.d/40ram-wipe/wipe-ram-needshutdown.sh << 'EOF'
#!/bin/sh

## Copyright (C) 2023 - 2025 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

type getarg >/dev/null 2>&1 || . /lib/dracut-lib.sh

. /lib/ram-wipe-lib.sh

ram_wipe_check_needshutdown() {
   ## 'local' is unavailable in 'sh'.
   #local kernel_wiperam_setting

   kernel_wiperam_setting="$(getarg wiperam)"

   if [ "$kernel_wiperam_setting" = "skip" ]; then
      force_echo "wipe-ram-needshutdown.sh: Skip, because wiperam=skip kernel parameter detected, OK."
      return 0
   fi

   true "wipe-ram-needshutdown.sh: Calling dracut function need_shutdown to drop back into initramfs at shutdown, OK."
   need_shutdown

   return 0
}

ram_wipe_check_needshutdown
EOF

chmod +x /usr/lib/dracut/modules.d/40ram-wipe/wipe-ram-needshutdown.sh

# wipe-ram.sh
cat > /usr/lib/dracut/modules.d/40ram-wipe/wipe-ram.sh << 'EOF'
#!/bin/sh

## Copyright (C) 2023 - 2025 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## Credits:
## First version by @friedy10.
## https://github.com/friedy10/dracut/blob/master/modules.d/40sdmem/wipe.sh

## Use '.' and not 'source' in 'sh'.
. /lib/ram-wipe-lib.sh

drop_caches() {
   sync
   ## https://gitlab.tails.boum.org/tails/tails/-/blob/master/config/chroot_local-includes/usr/local/lib/initramfs-pre-shutdown-hook
   ### Ensure any remaining disk cache is erased by Linux' memory poisoning
   echo 3 > /proc/sys/vm/drop_caches
   sync
}

ram_wipe() {
   ## 'local' is unavailable in 'sh'.
   #local kernel_wiperam_setting dmsetup_actual_output dmsetup_expected_output

   ## getarg returns the last parameter only.
   kernel_wiperam_setting="$(getarg wiperam)"

   if [ "$kernel_wiperam_setting" = "skip" ]; then
      force_echo "wipe-ram.sh: Skip, because wiperam=skip kernel parameter detected, OK."
      return 0
   fi

   force_echo "wipe-ram.sh: RAM extraction attack defense... Starting RAM wipe pass during shutdown..."

   drop_caches

   force_echo "wipe-ram.sh: RAM wipe pass completed, OK."

   ## In theory might be better to check this beforehand, but the test is
   ## really fast.
   force_echo "wipe-ram.sh: Checking if there are still mounted encrypted disks..."

   ## TODO: use 'timeout'?
   dmsetup_actual_output="$(dmsetup ls --target crypt 2>&1)"
   dmsetup_expected_output="No devices found"

   if [ "$dmsetup_actual_output" = "$dmsetup_expected_output" ]; then
      force_echo "wipe-ram.sh: Success, there are no more mounted encrypted disks, OK."
   elif [ "$dmsetup_actual_output" = "" ]; then
      force_echo "wipe-ram.sh: Success, there are no more mounted encrypted disks, OK."
   else
      ## dracut should unmount the root encrypted disk cryptsetup luksClose during shutdown
      ## https://github.com/dracutdevs/dracut/issues/1888
      force_echo "\\
wipe-ram.sh: There are still mounted encrypted disks! RAM wipe incomplete!

debugging information:
dmsetup_expected_output: '$dmsetup_expected_output'
dmsetup_actual_output: '$dmsetup_actual_output'"
      ## How else could the user be informed that something is wrong?
      sleep 5
   fi
}

ram_wipe
EOF

chmod +x /usr/lib/dracut/modules.d/40ram-wipe/wipe-ram.sh

# dracut.conf.d
cat > /usr/lib/dracut/dracut.conf.d/30-ram-wipe.conf << 'EOF'
add_dracutmodules+=" ram-wipe "
EOF

# ram-wipe-lib.sh
mkdir /usr/libexec/ram-wipe
cat > /usr/libexec/ram-wipe/ram-wipe-lib.sh << 'EOF'
#!/bin/sh

## Copyright (C) 2023 - 2025 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## Based on:
## /usr/lib/dracut/modules.d/99base/dracut-lib.sh
if [ -z "$DRACUT_SYSTEMD" ]; then
    force_echo() {
        echo "<28>dracut INFO: $*" > /dev/kmsg
        echo "dracut INFO: $*" >&2
    }
else
    force_echo() {
        echo "INFO: $*" >&2
    }
fi
EOF

chmod +x /usr/libexec/ram-wipe/ram-wipe-lib.sh

# Update INITRAMFS
dracut --verbose --force
echo "ram-wipe module created successfully!"
echo "Use a shortcut key like Control + Alt + Space to activate fast shutdown against physical attackers."
echo "Manually configure the settings manager / Keyboard."
echo "Dom0 does not support USB drives to create a USB kill switch like Tails OS does."


echo;

# Just for testing at the beginning of the creation of the algorithm
# Commented out now to be used in the future if something is modified to change the remove_anti_cold_boot() function with new hashes
#remove : << 'END_COMMENT' and END_COMMENT to apply again...

: << 'END_COMMENT'
#echo "Hash of the files created"
# Define the directory and files to check
files=(
    "/usr/lib/dracut/modules.d/40ram-wipe/module-setup.sh"
    "/usr/lib/dracut/modules.d/40ram-wipe/wipe-ram-needshutdown.sh"
    "/usr/lib/dracut/modules.d/40ram-wipe/wipe-ram.sh"
    "/usr/lib/dracut/dracut.conf.d/30-ram-wipe.conf"
    "/usr/libexec/ram-wipe/ram-wipe-lib.sh"
)

# Iterate through the files and calculate the SHA-256 hash
for file in "${files[@]}"; do
    if [[ -f "$file" ]]; then
        hash=$(sha256sum "$file" | awk '{ print $1 }')
        echo "File: $file"
        echo "SHA-256 Hash: $hash"
        echo "-----------------------------"
    else
        echo "File: $file does not exist."
        echo "-----------------------------"
    fi
done
END_COMMENT


}

remove_anti_cold_boot()
{
echo
# Define the files and their expected hashes
declare -A files_hashes
files_hashes=(
    ["/usr/lib/dracut/modules.d/40ram-wipe/module-setup.sh"]="246d9f7fb41d7f2361d0e086889a1570625c4468ee17ccf06fdd8c3044cb6049"
    ["/usr/lib/dracut/modules.d/40ram-wipe/wipe-ram-needshutdown.sh"]="55be0355df0cdf9eb4f135602a87e2b47f6807e00baf24becea41a478064795d"
    ["/usr/lib/dracut/modules.d/40ram-wipe/wipe-ram.sh"]="a1a121e7faaaf5b4a042a8a63887fdfd4e4891c9ccdb976bcafc0a228c0b1a48"
    ["/usr/lib/dracut/dracut.conf.d/30-ram-wipe.conf"]="60463385aff5cf70d815a0b399f0c8142a8eef6b8a5e643da82e4a59e7fa73c4"
    ["/usr/libexec/ram-wipe/ram-wipe-lib.sh"]="1fdd83475d59f1942492cac643d63a607339190c11bda4a401a51c34112a871d"
)

# Check each file's existence and hash
all_exist=true
all_match=true

for file in "${!files_hashes[@]}"; do
    if [[ -f "$file" ]]; then
        # Calculate the SHA-256 hash
        calculated_hash=$(sha256sum "$file" | awk '{ print $1 }')
        expected_hash=${files_hashes[$file]}

        echo "File: $file"
        echo "Calculated Hash: $calculated_hash"
        echo "Expected Hash: $expected_hash"

        if [[ "$calculated_hash" != "$expected_hash" ]]; then
            echo "Warning: Hash does not match for $file."
            all_match=false
        else
            echo "Hash matches for $file."
        fi
        echo "-----------------------------"
    else
        echo "File: $file does not exist."
        all_exist=false
    fi
done

# Check the status of files and hashes
if $all_exist; then
    echo "All files exist."
else
    echo "Some files are missing."
fi

if $all_match; then
    echo "All hashes correspond."
else
    echo "Some hashes do not correspond."
fi

echo "Anti cold boot attack modules are already installed."

# Prompt to continue or cancel the operation
read -p "Do you wish to continue or cancel the operation? (type 'y' or 'n'): " user_input
echo

if [[ "$user_input" == "y" ]]; then
    echo "Continuing the operation..."

# Inform the user about the deletion process
echo "Deleting Dracut Anti Cold Boot Attack Modules..."

# List of directories and files to delete
items=(
    "/usr/lib/dracut/modules.d/40ram-wipe/"
    "/usr/lib/dracut/modules.d/40ram-wipe/"  # Appears multiple times
    "/usr/lib/dracut/modules.d/40ram-wipe/"
    "/usr/lib/dracut/modules.d/40ram-wipe/"
    "/usr/libexec/ram-wipe/"
    "/usr/lib/dracut/dracut.conf.d/30-ram-wipe.conf"
)

# Loop through the items and delete each one
for item in "${items[@]}"; do
    if [[ -e "$item" ]]; then
        echo "Deleting: $item"
        sudo rm -rf "$item"
    else
        echo "Warning: $item does not exist or cannot be deleted."
    fi
done
echo
# Regenerate Dracut
echo "Regenerating Dracut..."
sudo dracut --verbose --force
echo "Operation completed."

else
    echo "Operation canceled."
fi

}

echo;
echo "-----------------------";
echo " Qubes Ephemeral Vault ";
echo "-----------------------";
echo "leandroibov developer";
echo;
check_root_ram


    while true; do
        echo ""
        echo "Menu:"
        echo "1. Set up Qubes dom0 for 100% RAM (Ephemeral)"
        echo "2. Restore original Qubes settings"
        echo "3. Install Anti-Cold Boot Attack Dracut Modules"
        echo "4. Remove Anti-Cold Boot Attack Dracut Modules for maintenance"
        echo "5. Exit"
        read -p "Enter your choice (1-3): " choice
        
        case $choice in
            1)
                ephemeral_qubes
                ;;
            2)
                restore_original_qubes
                ;;
            3)
                anti_cold_boot
                ;;
            4)
                remove_anti_cold_boot
                ;;
            5)
                echo "Exiting the menu."
                break
                ;;
            *)
                echo "Invalid choice. Please try again."
                ;;
        esac
    done



