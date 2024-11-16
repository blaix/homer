{
  description = "Blaix Flakes";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:LnL7/nix-darwin";
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, home-manager, ... }: {

    # macs
    darwinConfigurations = {
      arwen = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [ 
          ./hosts/mac/arwen.nix
          home-manager.darwinModules.home-manager {
            home-manager.users.justin = import ./home.nix;
          }
        ];
      };
      bilbo = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [ 
          ./hosts/mac/bilbo.nix
          home-manager.darwinModules.home-manager {
            home-manager.users.justin = import ./home.nix;
          }
        ];
      };
    };

    # nixos
    nixosConfigurations = {
      orb = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [ 
          ./hosts/nixos/orb.nix
          home-manager.nixosModules.home-manager {
            home-manager.users.justin = import ./home.nix;
          }
        ];
      };
    };
  };
}
