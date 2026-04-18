{ ... }:

{
  # Networking via systemd-networkd (DHCP from NAT)
  systemd.network = {
    enable = true;
    networks."10-virtio" = {
      matchConfig.Driver = "virtio_net";
      networkConfig = {
        DHCP = "yes";
        DNS = [
          "8.8.8.8"
          "8.8.4.4"
        ];
      };
    };
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  networking.useNetworkd = true;
  # The default hostname can be overridden at boot via systemd.hostname=<name>
  # on the kernel command line. Swift uses the same default for direct CLI mode.
  networking.hostName = "darwin-vz-guest";
}
