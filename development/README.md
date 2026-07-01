## Build

```bash
nix build          # default: PG 18
nix build .#pg16   # PG 16
nix build .#pg17   # PG 17
nix build .#pg18   # PG 18
./result | docker load
```

Produces `ilbal-postgresql:<major>` where `major` is the PostgreSQL major
version (16, 17, or 18).

## Run

```bash
docker run --rm --name ilbaldb \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=password \
  -p 5432:5432 \
  ilbal-postgresql:18
```
