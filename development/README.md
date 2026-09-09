## Build

```bash
nix flake update base # if ilbal-base has been altered prior to building this image
```

```bash
# Change `created` (on line 457) to current datetime (date now | date to-timezone Zulu | format date "%Y-%m-%dT%H:%M:%SZ")
nix build          # default: PG 18
nix build .#pg16   # PG 16
nix build .#pg17   # PG 17
nix build .#pg18   # PG 18
./result | docker load
```

Produces `ilbal-postgresql:<major>` where `major` is the PostgreSQL major
version (16, 17, or 18).

After loading, tag a copy as `:latest` for convenience.

```bash
# Example: version 0.1.0
docker tag ilbal-postgresql:18 ilbal-postgresql:latest
```

## Run

```bash
docker run --rm --name ilbaldb \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=password \
  -p 5432:5432 \
  ilbal-postgresql:18
```
