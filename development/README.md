## Building with flake.nix
1. `nix build .#` # for building the default package
2. `nix build .#pg16` # for building a specific pg version package
3. `./result | docker load`



## For building ilbal18-image.nix
1. `nix build --file ilbal18-image.nix --show-trace`
2. `nix build --file ilbal18-image.nix`
3. `./result | docker load`
4. `docker images`
