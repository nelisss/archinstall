# archinstall.sh

This is the script I use to automatically install arch linux to my liking. Would not recommend using. The only reason this is public is so that I can easily pull it off of github without authentication.

## Usage

Just chmod +x and run the script, all settings will be prompted. As there will probably be errors, the script saves the settings to archinstall.env. When you run the script again, use `./archinstall.sh /path/to/archinstall.env` to use the same settings.

## Notes

When applying LUKS encryption, the script assumes [mkinitcpio-systemd-extras](https://aur.archlinux.org/packages/mkinitcpio-systemd-extras) (AUR, see [here](https://wiki.archlinux.org/title/Dm-crypt/Specialties#Remote_unlocking_of_root_(or_other)_partition) for explanation) is added to a custom pacman library on the .iso. See [here](https://wiki.archlinux.org/title/Archiso) for instructions on how to create a custom .iso with a custom library. Basically, clone the AUR repo, run makepkg, add the .pkg.tar.zst to a directory, run repo-add to create a custom library, copy the library to the iso, create a custom pacman.conf with a reference to the library, build the iso with archiso.

In addition, if wifi is enabled, the script assumes [mkinitcpio-wifi](https://aur.archlinux.org/packages/mkinitcpio-wifi) is installed. This package can be added to a custom .iso as well.
