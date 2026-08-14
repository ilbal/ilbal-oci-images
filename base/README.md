# ilbal-base

Shared Python + GDAL base OCI image for `development/` and `loaders/`.

Reduces duplication by providing a common base layer with GDAL (minimal),
Python (with numpy), and PROJ — so each downstream image doesn't bundle
them separately.

## Build

```bash
# Change `created` (on line 294) to current datetime (date now | date to-timezone Zulu | format date "%Y-%m-%dT%H:%M:%SZ")
# If desired, bump .version to e.g. 0.1.1
nix build
docker load -i result
docker tag ilbal-base:<version> ilbal-base:latest
```

The tag is set from `.version`. After loading, tag a copy as `:latest` for
convenience.

```bash
# Example: version 0.1.0
docker tag ilbal-base:0.1.0 ilbal-base:latest
```
