# ilbal-base

Shared Python + GDAL base OCI image for `development/` and `loaders/`.

Reduces duplication by providing a common base layer with GDAL (minimal),
Python (with numpy), and PROJ — so each downstream image doesn't bundle
them separately.

## Build

```bash
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
