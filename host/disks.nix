# The disks install.sh may and may not touch, matched by serial number (`lsblk -do NAME,SERIAL,MODEL`).
# Kernel names like nvme0n1/nvme1n1 are deliberately not used anywhere: they follow probe order and can swap
# between boots, and between the live ISO and the installed system.
{
  # NixOS goes here: install.sh repartitions this disk (after you type ERASE) and puts the EFI system
  # partition, swap and root on it
  target = {
    serial = "MS8BN14451140BK45";
    description = "SK hynix PC401 NVMe 256GB";
  };

  # Never partitioned, formatted or mounted by install.sh (it refuses them even with --disk), and hidden from
  # udisks on the installed system (udiskie does not automount them, nemo does not list them)
  protected = [
    {
      serial = "50026B768790C1C4";
      description = "Kingston NV3 1TB (Artix Linux)";
    }
  ];
}
