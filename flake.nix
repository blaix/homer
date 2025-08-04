{
  description = "Blaix Flakes";

  inputs = {
    # unstable
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    home-manager.url = "github:nix-community/home-manager/master";
    
    # versioned
    #nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    #nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.05";
    #home-manager.url = "github:nix-community/home-manager/release-25.05";

    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    lix-module = {
      url = "https://git.lix.systems/lix-project/nixos-module/archive/2.93.3-1.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, home-manager, lix-module, ... }: {

    # macs
    darwinConfigurations = {
      arwen = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [ 
          lix-module.nixosModules.default
          ./hosts/mac/arwen.nix
          home-manager.darwinModules.home-manager {
            home-manager.users.justin = import ./home.nix;
          }
        ];
      };
      bilbo = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [ 
          lix-module.nixosModules.default
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
          lix-module.nixosModules.default
          ./hosts/nixos/orb.nix
          home-manager.nixosModules.home-manager {
            home-manager.users.justin = import ./home.nix;
          }
        ];
      };
    };
  };
}
