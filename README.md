# NordVPN Flake for NixOS

A Nix flake that provides the NordVPN client for NixOS. It builds the NordVPN CLI tool from the official `.deb` package and configures it to work in NixOS's immutable environment.

## Usage

Add this flake as an input in your `flake.nix`:

```nix
inputs.nordvpn-flake.url = "github:your-username/nordvpn-flake";
