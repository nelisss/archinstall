#!/bin/bash
set -eo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

# Vars
packages="base linux linux-firmware vi vim neovim man-db man-pages texinfo iwd reflector sudo grub efibootmgr bash-completion openssh util-linux"
boot_size=1024
locale="en_GB.UTF-8" # Without last UTF-8, for example: en_GB.UTF-8

### Import config
config_path=$1
if [[ ${config_path} != "" ]]; then
    if [[ ! -f "${config_path}" ]]; then
        echo "Error: supplied path to config file does not exist." >&2
        exit 1
    fi
    echo "Using ${config_path} as a config file, skipping input for variables defined there."
    source "${config_path}"
fi

### USER INPUT

# hostname
valid_input=false
while [[ $valid_input == false ]]; do
    if [[ ${hostname} == "" ]]; then
        echo -n "Hostname: "
        read hostname
        hostname=${hostname,,}
    fi
    if [[ ${hostname} == "" ]]; then
        echo "Error: please enter a hostname."
    elif ( echo "${hostname}" | grep -P '[^a-z0-9-\.]' > /dev/null ); then
        echo "Error: please enter a valid hostname (a-z, 0-9, -, .)." >&2
        hostname=""
    elif ( echo "${hostname}" | grep -P '^-.*' > /dev/null ); then
        echo "Error: please enter a valid hostname (should not start with hyphen)." >&2
        hostname=""
    elif ( echo "${hostname}" | grep -P '.*-$' > /dev/null ); then
        echo "Error: please enter a valid hostname (should not end with hyphen)." >&2
        hostname=""
    else
        valid_input=true
        echo "Using hostname ${hostname}."
    fi
done

# username
echo ""
valid_input=false
while [[ $valid_input == false ]]; do
    if [[ ${username} == "" ]]; then
        echo -n "Username (will get sudo privileges): "
        read username
    fi
    if [[ ${username} == "" ]]; then
        echo "Error: please enter a username."
    elif ( echo "${username}" | grep -P '[^a-zA-Z0-9-_\.]' > /dev/null ); then
        echo "Error: please enter a valid username (a-z, A-Z, 0-9, -, .)." >&2
        username=""
    elif ( echo "${username}" | grep -P '^-.*' > /dev/null ); then
        echo "Error: please enter a valid username (should not start with hyphen)." >&2
        username=""
    else
        valid_input=true
        echo "Using username ${username}."
    fi
done

# password
echo ""
valid_input=false
while [[ $valid_input == false ]]; do
    if [[ ${password} == "" ]]; then
        echo -n "Password for user ${username}: "
        read -s password
        echo ""
        if [[ ${password} == "" ]]; then
            echo "Please enter a password." >&2
        else
            echo -n "Repeat password: "
            read -s password2
            echo ""
            if [[ ! ${password} == ${password2} ]]; then
                echo "Error: passwords do not match, try again." >&2
                password=""
                password2=""
            else
                echo "Password registered."
                valid_input=true
            fi
        fi
    else
        echo "Password registered."
        valid_input=true
    fi
done

# timezone
echo ""
valid_input=false
while [[ $valid_input == false ]]; do
    if [[ ${timezone} == "" ]]; then
        echo -n "Timezone for system: "
        read timezone
    fi
    if [[ ${timezone} == "" ]]; then
        echo "Error: please enter a timezone." >&2
    elif ( ! echo "${timezone}" | grep -P '^[A-Za-z]+\/[A-Za-z]+$' > /dev/null ); then
        echo "Error: please enter a valid timezone in IANA format (e.g. Europe/Paris)." >&2
        timezone=""
    elif ( ! timedatectl list-timezones | grep "${timezone}" > /dev/null ); then
        echo "Error: unknown timezone. See timedatectl list-timezones for valid timezones." >&2
        timezone=""
    else
        valid_input=true
        echo "Using timezone ${timezone}."
    fi
done

# wifi
echo ""
valid_input=false
while [[ $valid_input == false ]]; do
    if [[ ${enable_wifi} == "" ]]; then
        echo -n "Wifi (true/false)?: "
        read enable_wifi
    fi
    enable_wifi=${enable_wifi,,}
    if [[ ! ${enable_wifi} == true ]] && [[ ! ${enable_wifi} == false ]]; then
        echo "Error: input should be \"true\" or \"false\"." >&2
        enable_wifi=""
    elif [[ ${enable_wifi} == true ]]; then
        if [[ ${wifi_name} == "" ]]; then
            echo -n "Wifi name: "
            read wifi_name
        fi
        if [[ ${wifi_name} == "" ]]; then
            echo "Error: please enter a wifi name." >&2
        else
            if [[ ${wifi_password} == "" ]]; then
                echo -n "Wifi password: "
                read -s wifi_password
            fi
            if [[ ${wifi_password} == "" ]]; then
                echo "Error: please enter a wifi password." >&2
            else
                echo "Will attempt to connect to network ${wifi_name}"
                valid_input=true
            fi
        fi
    else
        echo "Not using wifi."
        valid_input=true
    fi
done

echo ""
echo "Currently installed disks:"
lsblk

disks=$( fdisk -l | grep -oP '(?<=^Disk )\/dev\/[a-z0-9]+(?=:)' )
echo ""
echo "Which disk to install on (will erase all data!)?"
num_disks=$( echo "${disks}" | wc -l )
iter=1
while read -r disk_name; do
    echo "(${iter}) ${disk_name}"
    iter=$(( ${iter} + 1 ))
done <<< "${disks}"

valid_input=false
while [[ ${valid_input} == false ]]; do
    if [[ ${disk} == "" ]]; then
        echo -n "Insert number of disk: "
        read disk_number
        if [[ ${disk_number} == "" ]]; then
            echo "Error: please enter a disk number." >&2
        elif ( ! echo "${disk_number}" | grep -P "^[0-${num_disks}]$" > /dev/null ); then
            echo "Error: invalid input, choose a number from 1 to ${num_disks}." >&2
        else
            disk=$( echo "${disks}" | sed -n "${disk_number}p" )
            echo -n "Are you sure you want to format disk ${disk} (yes/no)? "
            read disk_confirm
            if [[ ! ${disk_confirm,,} == "yes" ]]; then
                echo "Not formatting ${disk}. Choose another."
            else
                echo "Will use ${disk}."
                valid_input=true
            fi
        fi
    else
        if ( ! echo "${disks}" | grep -P "^${disk}$" > /dev/null ); then
            echo "Error: provided disk does not exist." >&2
        else
            echo -n "Are you sure you want to format disk ${disk} (yes/no)? "
            read disk_confirm
            if [[ ! ${disk_confirm,,} == "yes" ]]; then
                echo "Not formatting ${disk}. Choose another."
                disk=""
            else
                echo "Will use ${disk}."
                valid_input=true
            fi
        fi
    fi
done

# encryption
echo ""
valid_input=false
while [[ ${valid_input} == false ]]; do
    if [[ ${encrypt_partitions} == "" ]]; then
        echo -n "Encrypt root and swap partitions (true/false)? "
        read encrypt_partitions
    fi
    encrypt_partitions=${encrypt_partitions,,}
    if [[ ! ${encrypt_partitions} == true ]] && [[ ! ${encrypt_partitions} == false ]]; then
        echo "Error: input should be \"true\" or \"false\"." >&2
    elif [[ ${encrypt_partitions} == true ]]; then
        if [[ ${encryption_password} == "" ]]; then
            echo -n "Encryption password to use: "
            read -s encryption_password
            echo ""
            if [[ ${encryption_password} == "" ]]; then
                echo "Please enter an encryption password." >&2
            else
                echo -n "Repeat encryption password: "
                read -s encryption_password2
                echo ""
                if [[ ! ${encryption_password} == ${encryption_password2} ]]; then
                    echo "Error: encryption passwords do not match, try again." >&2
                    encryption_password=""
                    encryption_password2=""
                else
                    echo "Encryption password registered."
                    valid_input=true
                fi
            fi
        else
            echo "Encryption password registered."
            valid_input=true
        fi
    else
        echo "Not encrypting partitions."
        valid_input=true
    fi
done

# intel/amd
echo ""
valid_input=false
while [[ ${valid_input} == false ]]; do
    if [[ ${intel_amd} == "" ]]; then
        echo -n "Intel or amd (intel/amd)?: "
        read intel_amd
    fi
    if [[ ! ${intel_amd,,} == "intel" ]] && [[ ! ${intel_amd,,} == "amd" ]]; then
        echo "Error: please enter \"intel\" or \"amd\"." >&2
        intel_amd=""
    elif [[ ${intel_amd,,} == "intel" ]]; then
        echo "Using intel-ucode."
        packages="${packages} intel-ucode"
        valid_input=true
    else [[ ${intel_amd,,} == "amd" ]]
        echo "Using amd-ucode."
        packages="${packages} amd-ucode"
        valid_input=true
    fi 
done

# github keys
echo ""
valid_input=false
while [[ ${valid_input} == false ]]; do
    if [[ ${github_user} == "" ]]; then
        echo -n "GitHub user to get SSH keys from (empty for none): "
        read github_user
    fi
    if [[ ${github_user} == "" ]]; then
        import_github=false
        echo "Not importing GitHub SSH keys."
        valid_input=true
    elif ( curl --silent https://api.github.com/users/${github_user} | grep 'Not Found' > /dev/null ); then
        echo "Error: GitHub user does not exist." >&2
        github_user=""
    else
        import_github=true
        echo "Will import keys from GitHub user ${github_user}."
        valid_input=true
    fi
done

### env to file
echo ""
echo "Saving settings to ./archinstall.env, can be used in subsequent runs if an error is encountered by running \"archinstall.sh archinstall.env\"."
cat <<EOF > archinstall.env
hostname="${hostname}"
username="${username}"
password="${password}"
timezone="${timezone}"
enable_wifi="${enable_wifi}"
wifi_name="${wifi_name}"
wifi_password="${wifi_password}"
disk="${disk}"
encrypt_partitions="${encrypt_partitions}"
encryption_password="${encryption_password}"
intel_amd="${intel_amd}"
github_user="${github_user}"
EOF

# Logging
echo ""
echo "Logging to ./archinstall_stdout.log and ./archinstall_stderr.log"
exec 1> >(tee "archinstall_stdout.log")
exec 2> >(tee "archinstall_stderr.log")

loadkeys us

# Network config
if [[ ${enable_wifi} == true ]]; then
    wifi_interface=$( ip link | grep -oP '(?<=^\d: )[a-z0-9]+(?=:)' | grep -oP '^wl[a-z]*\d+$' )
    systemctl enable --now rfkill-unblock@all.service
    ip link set ${wifi_interface} up
    iwctl station ${wifi_interface} scan
    iwctl --passphrase="${wifi_password}" station ${wifi_interface} connect "${wifi_name}"
fi

while ( ! ping -c 1 google.com > /dev/null ); do
    echo "Error: could not ping google.com, retrying in 5 seconds." >&2
    sleep 5
done

# Timezone
timedatectl set-timezone ${timezone}
timedatectl set-local-rtc 0
timedatectl set-ntp true

# Partitions
total_memory=$( free --mebi | grep -oP "(?<=^Mem:)\s+\d+" | sed 's/\s//g' )
swap_end=$(( ${total_memory} + ${boot_size} + 1))MiB
parted --script ${disk} -- mklabel gpt \
    mkpart ESP fat32 1MiB ${boot_size}MiB \
    set 1 boot on \
    mkpart primary linux-swap ${boot_size}MiB ${swap_end}MiB \
    mkpart primary ext4 ${swap_end} 100%

efi_partition="$(ls ${disk}* | grep -E "^${disk}p?1$")"
swap_partition="$(ls ${disk}* | grep -E "^${disk}p?2$")"
root_partition="$(ls ${disk}* | grep -E "^${disk}p?3$")"

mkfs.fat -F 32 ${efi_partition}
if [[ ${encrypt_partitions} == true ]]; then
    cryptsetup luksFormat --type luks1 ${swap_partition} <<< "${encryption_password}"
    cryptsetup open ${swap_partition} swap <<< "${encryption_password}"
    mkswap /dev/mapper/swap

    cryptsetup luksFormat --type luks1 ${root_partition} <<< "${encryption_password}"
    cryptsetup open ${root_partition} rootfs <<< "${encryption_password}"
    mkfs.ext4 /dev/mapper/rootfs

    mount /dev/mapper/rootfs /mnt
    mount --mkdir ${efi_partition} /mnt/boot
    swapon /dev/mapper/swap
else
    mkswap ${swap_partition}
    mkfs.ext4 ${root_partition}

    mount ${root_partition} /mnt
    mount --mkdir ${efi_partition} /mnt/boot
    swapon ${swap_partition}
fi

# Packages
systemctl start reflector.service
pacstrap -K /mnt ${packages}

# Fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Timezone
arch-chroot /mnt ln -sf /usr/share/zoneinfo/${timezone} /etc/localtime
arch-chroot /mnt timedatectl set-timezone ${timezone}
arch-chroot /mnt timedatectl set-local-rtc 0
arch-chroot /mnt timedatectl set-ntp true

# Locales
sed -i -E "s/#${locale}/${locale}/" /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo "LANG=${locale}" > /mnt/etc/local.conf

# Network
ethernet_interface=$( ip link | grep -oP '(?<=^\d: )[a-z0-9]+(?=:)' | grep -oP '^e[a-z]*\d+$' )
arch-chroot /mnt ip link set ${ethernet_interface} up
cat <<EOF > /mnt/etc/systemd/network/20-wired.network
[Match]
Name=en*
Name=eth*

[Link]
RequiredForOnline=$( if [[ ${enable_wifi} == true ]]; then echo "no"; else echo "routable"; fi )

[Network]
DNS=1.1.1.1
DHCP=yes
MulticastDNS=no

[DHCPv4]
RouteMetric=100

[IPv6AcceptRA]
RouteMetric=100
EOF

if [[ ${enable_wifi} == true ]]; then
    arch-chroot /mnt systemctl enable rfkill-unblock@all.service
    arch-chroot /mnt ip link set ${wifi_interface} up
    arch-chroot /mnt iwctl station ${wifi_interface} scan
    arch-chroot /mnt iwctl --passphrase="${wifi_password}" station ${wifi_interface} connect "${wifi_name}"
    cat <<EOF > /mnt/etc/systemd/network/20-wireless.network
[Match]
Name=wl*

[Link]
RequiredForOnline=routable

[Network]
DNS=1.1.1.1
DHCP=yes
MulticastDNS=no

[DHCPv4]
RouteMetric=600

[IPv6AcceptRA]
RouteMetric=600
EOF
    arch-chroot /mnt systemctl enable iwd
fi
arch-chroot /mnt systemctl enable systemd-networkd
arch-chroot /mnt systemctl enable systemd-resolved

# Hostname
echo ${hostname} > /etc/hostname

# User
arch-chroot /mnt useradd -m ${username}
arch-chroot /mnt groupadd sudo
echo "${username}:${password}" | chpasswd --root /mnt
echo "%sudo  ALL=(ALL:ALL) ALL" >> /mnt/etc/sudoers
arch-chroot /mnt usermod -a -G sudo ${username}
arch-chroot /mnt passwd --lock root

# SSH
arch-chroot -u ${username} /mnt ssh-keygen -t ed25519 -f /home/${username}/.ssh/id_ed25519 -N "" -q
curl https://github.com/${github_user}.keys >> /mnt/home/${username}/.ssh/authorized_keys
arch-chroot /mnt chown ${username}:${username} /home/${username}/.ssh/authorized_keys
arch-chroot /mnt chmod 600 /home/${username}/.ssh/authorized_keys
arch-chroot /mnt systemctl enable sshd

# SSH before root mounting for encrypted partitions
# This requires a custom .iso with the AUR mkinicpio-systemd-extras package
if [[ ${encrypt_partitions} == true ]]; then
    pacstrap -K /mnt mkinitcpio-systemd-extras tinyssh
    #sed -i -E 's/^FILES=\(\)/FILES=(\/usr\/lib\/udev\/rules.d\/75-net-desription.rules \/usr\/lib\/udev\/rules.d\/80-net-setup-link.rules \/usr\/lib\/systemd\/network\/99-default.link)/' /mnt/etc/mkinitcpio.conf
    if ( ! cat /mnt/etc/mkinitcpio.conf | grep -E '^SD_TINYSSH_COMMAND=.*$' > /dev/null ); then
        echo 'SD_TINYSSH_COMMAND="systemd-tty-ask-password-agent --query --watch"' >> /mnt/etc/mkinitcpio.conf
    else
        sed -i -E 's/^SD_TINYSSH_COMMAND=.*$/SD_TINYSSH_COMMAND="systemd-tty-ask-password-agent --query --watch"/' /mnt/etc/mkinitcpio.conf
    fi
    if ( ! cat /mnt/etc/mkinitcpio.conf | grep -E '^SD_TINYSSH_AUTHORIZED_KEYS=.*$' > /dev/null ); then
        echo "SD_TINYSSH_AUTHORIZED_KEYS=\"/home/${username}/.ssh/authorized_keys\"" >> /mnt/etc/mkinitcpio.conf
    else
        sed -i -E 's/^SD_TINYSSH_COMMAND=.*$/SD_TINYSSH_COMMAND="systemd-tty-ask-password-agent --query --watch"/' /mnt/etc/mkinitcpio.conf
    fi

    if [[ ${enable_wifi} == true ]]; then
        pacstrap -K /mnt mkinitcpio-wifi broadcom-wl
        wpa_passphrase "${wifi_name}" "${wifi_password}" > /mnt/etc/wpa_supplicant/initcpio.conf
        sed -i -E 's/^HOOKS=\(.*\)$/HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block wifi sd-network sd-tinyssh sd-encrypt filesystems resume fsck)/' /mnt/etc/mkinitcpio.conf
    else
        sed -i -E 's/^HOOKS=\(.*\)$/HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-network sd-tinyssh sd-encrypt filesystems resume fsck)/' /mnt/etc/mkinitcpio.conf
    fi
    echo "KEYMAP=us" > /mnt/etc/vconsole.conf
    arch-chroot /mnt mkinitcpio -P
fi

# GRUB
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
sed -i -E 's/GRUB_TIMEOUT=[0-9]+/GRUB_TIMEOUT=0/' /mnt/etc/default/grub

swap_uuid=$( blkid ${swap_partition} -o value | head -1 )
if [[ ${encrypt_partitions} == true ]]; then
    root_uuid=$( blkid ${root_partition} -o value | head -1 )
    swap_open_uuid=$( blkid /dev/mapper/swap -o value | head -1 )
    if [[ ${enable_wifi} == true ]]; then
        grub_uuid_line="GRUB_CMDLINE_LINUX_DEFAULT=\"rd.luks.name=${root_uuid}=root rl.luks.name=${swap_uuid}=swap resume=UUID=${swap_open_uuid} rootflags=x-systemd.device-timeout=0 ip=:::::wlan0:dhcp loglevel=3 quiet\""
    else
        grub_uuid_line="GRUB_CMDLINE_LINUX_DEFAULT=\"rd.luks.name=${root_uuid}=root rl.luks.name=${swap_uuid}=swap resume=UUID=${swap_open_uuid} rootflags=x-systemd.device-timeout=0 loglevel=3 quiet\""
    fi
    sed -i -E 's/#GRUB_ENABLE_CRYPTODISK=.*/GRUB_ENABLE_CRYPTODISK=y/' /mnt/etc/default/grub
else
    grub_uuid_line="GRUB_CMDLINE_LINUX_DEFAULT=\"resume=UUID=${swap_uuid} loglevel=3 quiet\""
fi
sed -i -E "s/GRUB_CMDLINE_LINUX_DEFAULT=.*/${grub_uuid_line}/" /mnt/etc/default/grub
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
echo "lz4" > /mnt/sys/module/hibernate/parameters/compressor
cat <<EOF > /mnt/etc/tmpfiles.d/hibernation_image_size.conf
#    Path                   Mode UID  GID  Age Argument
w    /sys/power/image_size  -    -    -    -   $(( ${total_memory} * 1048576 ))
EOF

# SSD
arch-chroot /mnt systemctl enable fstrim.timer

# Finish
umount -R /mnt
if [[ ${encrypt_partitions} == true ]]; then
    cryptsetup close rootfs
    swapoff /dev/mapper/swap
    cryptsetup close swap
else
    swapoff ${swap_partition}
fi

echo "All seems to be well, you can reboot and try to enter the system."
