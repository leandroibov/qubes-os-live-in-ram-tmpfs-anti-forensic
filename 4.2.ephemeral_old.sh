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

#new algorith 2026 for qubes 4.3
# Determine which device is mounted as / , if is zram, the program will stop...
#root_dev=$(findmnt -n -o SOURCE /)

# Strip the leading "/dev/" so we only keep the device name (e.g., "zram0").
# This makes the pattern match easier.
#root_dev=${root_dev#/dev/}

# Abort if the device name starts with "zram".
#if [[ $root_dev == zram* ]]; then
#    echo "⚠️  dom0 is mounted on ZRAM ($root_dev)."
#    echo "    Aborting to avoid creating a wrong GRUB or initramfs that could render the system unbootable."
    # Optional pause so the user can read the warning.
#    sleep 6
#    exit 1
#else
#    echo "✅  dom0 is NOT on ZRAM (root = $root_dev)."
#    echo "    Continuing with the rest of the script."
#fi

#obsolete but works in qubes 4.2, but not in qubes 4.3
if [[ -e /sys/block/zram0 ]]; then
    echo "Detected /sys/block/zram0 – zram is active on this system."
  echo "Aborting script execution to avoid creating a faulty GRUB or initramfs."
   echo "Ephemeral must be executed only in the persistent dom0, not when mounted in RAM!"
sleep 6
    exit 1
fi
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
        echo "3. Exit"
        read -p "Enter your choice (1-3): " choice
        
        case $choice in
            1)
                ephemeral_qubes
                ;;
            2)
                restore_original_qubes
                ;;
            3)
                echo "Exiting the menu."
                break
                ;;
            *)
                echo "Invalid choice. Please try again."
                ;;
        esac
    done



















































































