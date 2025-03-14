{
  description = "A flake for installing NordVPN on NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config = {
        allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [
          "nordvpn"
        ];
      };
    };
  in
  {
    packages.${system} = {
      nordvpn = pkgs.stdenv.mkDerivation rec {
        pname = "nordvpn";
        version = "3.20.0"; # Replace with the latest version from NordVPN

        src = pkgs.fetchurl {
          url = "https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/n/nordvpn/nordvpn_3.20.0_amd64.deb";
          sha256 = "0fq0zfygn9disi2d1h61xg7qskbb0snhymdsmslm1zzd6c4x5wfz";
        };
        nativeBuildInputs = with pkgs; [ dpkg patchelf makeWrapper ];

        buildInputs = with pkgs; [ glibc libgcc systemd iptables iproute2 procps ];

        unpackPhase = "dpkg-deb -x $src .";

        installPhase = ''
          mkdir -p $out/bin $out/lib $out/share
          if [ -d usr/bin ]; then cp -r usr/bin/* $out/bin/; fi
          if [ -d usr/sbin ]; then cp -r usr/sbin/* $out/bin/; fi
          if [ -d usr/lib ]; then cp -r usr/lib/* $out/lib/; fi
          if [ -d usr/share ]; then cp -r usr/share/* $out/share/; fi

          for bin in $out/bin/nordvpn $out/bin/nordvpnd; do
            if [ -f "$bin" ]; then
              patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" "$bin"
              patchelf --set-rpath "${pkgs.lib.makeLibraryPath buildInputs}" "$bin"
            fi
          done

          wrapProgram $out/bin/nordvpn \
            --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath buildInputs}" \
            --prefix PATH : "${pkgs.lib.makeBinPath [ pkgs.iptables pkgs.iproute2 pkgs.procps ]}"

          wrapProgram $out/bin/nordvpnd \
            --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath buildInputs}" \
            --prefix PATH : "${pkgs.lib.makeBinPath [ pkgs.iptables pkgs.iproute2 pkgs.procps ]}"
        '';

        meta = with pkgs.lib; {
          description = "NordVPN CLI client";
          homepage = "https://nordvpn.com";
          license = licenses.unfree;
          platforms = platforms.linux;
          maintainers = [];
        };
      };

      default = self.packages.${system}.nordvpn;
    };

    # Optionally, provide a NixOS module to integrate it cleanly
    nixosModules.nordvpn = { config, lib, pkgs, ... }: {
      options.services.nordvpn.enable = lib.mkEnableOption "NordVPN service";

      config = lib.mkIf config.services.nordvpn.enable {
        environment.systemPackages = [ self.packages.${system}.nordvpn ];

        # Optional: Add systemd service for nordvpnd if needed
        systemd.services.nordvpnd = {
          description = "NordVPN Daemon";
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            ExecStart = "${self.packages.${system}.nordvpn}/bin/nordvpnd";
            Restart = "always";
          };
        };
      };
    };
  };
}
