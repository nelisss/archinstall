#!/bin/bash
set -ueo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

# Usage: get using curl https://filebrowser.nelisss.net/public/api/raw?hash= > arch_install.sh, chmod +x and execute

# Vars
packages="base linux linux-firmware vi vim neovim man-db man-pages texinfo iwd reflector sudo grub efibootmgr bash-completion openssh util-linux"
boot_size=1024
locale="en_GB.UTF-8" # Without last UTF-8, for example: en_GB.UTF-8

# User input
echo -n "Hostname: "
read hostname
: "${hostname:?"Missing hostname"}"

echo -n "User (will get sudo privileges): "
read username
: "${username:?"Missing username"}"

echo -n "User password: "
read -s password
echo
: "${password:?"Missing password"}"

echo -n "Repeat password: "
read -s password2
echo
: "${password2:?"Missing password"}"

if [[ ! ${password} == ${password2} ]]; then
    echo "Error: passwords do not match." >&2
    exit 1
fi

echo -n "Timezone: "
read timezone
: "${timezone:?"Missing timezone"}"
if ( ! echo "${timezone}" | grep -P '^[A-Za-z]+\/[A-Za-z]+$' > /dev/null ); then
    echo "Error: timezone is in the wrong format, should be in IANA format (e.g. Europe/Amsterdam)." >&2
    exit 1
fi

echo -n "Wifi (yes/no)?: "
read enable_wifi
: "${enable_wifi:?"Missing wifi enable"}"
if [[ ! ${enable_wifi,,} == "yes" ]] && [[ ! ${enable_wifi,,} == "no" ]]; then
    echo "Error: input should be \"yes\" or \"no\"." >&2
    exit 1
elif [[ ${enable_wifi} == "yes" ]]; then
    enable_wifi=true
    echo -n "Wifi name: "

    read wifi_name
    : "${wifi_name:?"Missing wifi network name"}"

    echo -n "Wifi password: "
    read wifi_password
    : "${wifi_password:?"Missing wifi network password"}"
else
    enable_wifi=false
fi

disks=$( fdisk -l | grep -oP '(?<=^Disk )\/dev\/[a-z0-9]+(?=:)' )
echo "Which disk to install on (will erase all data!)?"
iter=1
while read -r disk; do
    echo "(${iter}) ${disk}"
    iter=$(( ${iter} + 1 ))
done <<< "${disks}"
echo -n "Insert number of disk: "
read disk_number
: "${disk_number:?"Missing disk number"}"
disk=$( echo "${disks}" | sed -n "${disk_number}p" )
echo -n "Format disk ${disk} (yes/no)? "
read disk_confirm
: "${disk_confirm:?"Missing wifi enable"}"
if [[ ! ${disk_confirm,,} == "yes" ]] && [[ ! ${disk_confirm,,} == "no" ]]; then
    echo "Error: input should be \"yes\" or \"no\"." >&2
    exit 1
elif [[ ${disk_confirm,,} == "no" ]]; then
    echo "Not continuing" >&2
    exit 1
fi

echo -n "Intel or amd (intel/amd)?: "
read intel_amd
: "${intel_amd:?"Missing intel_amd"}"
if [[ ! ${intel_amd,,} == "intel" ]] && [[ ! ${intel_amd,,} == "amd" ]]; then
    echo "Error: input should be \"intel\" or \"amd\"." >&2
    exit 1
elif [[ ${intel_amd} == "intel" ]]; then
    packages="${packages} intel-ucode"
else
    packages="${packages} intel-ucode"
fi

echo -n "GitHub user to get SSH keys from: "
read github_user
: "${github_user:?"Missing github user"}"

# Logging
exec 1> >(tee "stdout.log")
exec 2> >(tee "stderr.log")

loadkeys us

# Network config
if [[ ${enable_wifi} == true ]]; then
    wifi_interface=$( ip link | grep -oP '(?<=^\d: )[a-z0-9]+(?=:)' | grep -oP '^wl[a-z]*\d+$' )
    systemctl enable --now rfkill-unblock@all.service
    ip link set ${wifi_interface} up
    iwctl station ${wifi_interface} scan
    iwctl --passphrase="${wifi_password}" station ${wifi_interface} connect "${wifi_name}"
fi

if ( ! ping -c 1 google.com > /dev/null ); then
    echo "Error: could not ping google.com." >&2
    exit 1
fi

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
mkswap ${swap_partition}
mkfs.ext4 ${root_partition}

# Mounts
mount ${root_partition} /mnt
mount --mkdir ${efi_partition} /mnt/boot
swapon ${swap_partition}

# Packages
systemctl start reflector.service
pacstrap -K /mnt ${packages}

# Fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Timezone
arch-chroot /mnt ln -sf /usr/share/zoneinfo/${timezone} /etc/localtime

# Locales
cat /mnt/etc/locale.gen | sed "s/#${locale}/${locale}/" > /mnt/etc/locale.gen
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

# GRUB
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
sed -i -E 's/GRUB_TIMEOUT=[0-9]+/GRUB_TIMEOUT=0' /mnt/etc/default/grub
swap_uuid=$( lsblk -f | grep swap | grep -oP '[a-z0-9]+-[a-z0-9-]+-[a-z0-9-]+' )
grub_uuid_line="GRUB_CMDLINE_LINUX_DEFAULT=\"resume=UUID=$swap_uuid loglevel=3 quiet\""
sed -i -E "s/GRUB_CMDLINE_LINUX_DEFAULT=.*/${grub_uuid_line}/" /mnt/etc/default/grub
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
echo "lz4" > /mnt/sys/module/hibernate/parameters/compressor
cat <<EOF > /mnt/etc/tmpfiles.d/hibernation_image_size.conf
#    Path                   Mode UID  GID  Age Argument
w    /sys/power/image_size  -    -    -    -   $(( ${total_memory} * 1048576 ))
EOF

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

# SSD
arch-chroot /mnt systemctl enable fstrim.timer

# Finish
umount -R /mnt
swapoff ${swap_partition}
reboot
