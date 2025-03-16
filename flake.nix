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
        version = "3.20.0";

        src = pkgs.fetchurl {
          url = "https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/n/nordvpn/nordvpn_3.20.0_amd64.deb";
          sha256 = "0fq0zfygn9disi2d1h61xg7qskbb0snhymdsmslm1zzd6c4x5wfz";
        };

        nativeBuildInputs = with pkgs; [ dpkg patchelf makeWrapper ];

        buildInputs = with pkgs; [
          glibc
          libgcc
          systemd
          iptables
          iproute2
          procps
          libxml2
          zlib
          openssl
          sqlite.out  # Explicitly use the out output with lib/
        ];

        unpackPhase = "dpkg-deb -x $src .";

        installPhase = ''
          mkdir -p $out/bin $out/lib/nordvpn $out/share
          cp -r usr/bin/* $out/bin/ || echo "Error: Failed to copy usr/bin"
          cp -r usr/lib/nordvpn/* $out/lib/nordvpn/ || echo "Error: Failed to copy usr/lib/nordvpn"
          cp -r usr/share/* $out/share/ || echo "Error: Failed to copy usr/share"

          # Define RPATH
          rpath="$out/lib/nordvpn:${pkgs.sqlite.out}/lib:${pkgs.lib.makeLibraryPath buildInputs}"
          echo "Setting RPATH: $rpath"

          # Patch binaries
          for bin in $out/bin/nordvpn $out/bin/nordvpnd; do
            if [ -f "$bin" ]; then
              patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" "$bin" || echo "Error: patchelf interpreter failed for $bin"
              patchelf --set-rpath "$rpath" "$bin" || echo "Error: patchelf rpath failed for $bin"
              echo "RPATH for $bin:"
              readelf -d "$bin" | grep RPATH || echo "Error: readelf failed for $bin"
            else
              echo "Error: $bin not found"
            fi
          done

          # Wrap programs
          wrapProgram $out/bin/nordvpn \
            --prefix PATH : "${pkgs.lib.makeBinPath [ pkgs.iptables pkgs.iproute2 pkgs.procps ]}" || echo "Error: wrapProgram failed for nordvpn"
          wrapProgram $out/bin/nordvpnd \
            --prefix PATH : "${pkgs.lib.makeBinPath [ pkgs.iptables pkgs.iproute2 pkgs.procps ]}" || echo "Error: wrapProgram failed for nordvpnd"
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

    nixosModules.nordvpn = { config, lib, pkgs, ... }: {
      options.services.nordvpn.enable = lib.mkEnableOption "NordVPN service";

      config = lib.mkIf config.services.nordvpn.enable {
        environment.systemPackages = [ self.packages.${system}.nordvpn ];
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
