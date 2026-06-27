# ilbal-postgresql-loaders

OCI image with data-loading tools for PostgreSQL.

## Build

```bash
nix build
./result | docker load
```

Produces `ilbal-postgresql-loaders-<version>:latest` where `version` is the content of `.version` (with trailing newline stripped). Increment `.version` and run `git add .version` before building to publish a new version.

## Usage

Mount data and run any tool:

```bash
docker run --rm -v /path/to/data:/data ilbal-postgresql-loaders:latest scrubcsv /data/input.csv
```

Default entrypoint shows available tools (dbcrossbar, ogr2ogr, pgferry, csv-tools, geocode-csv).

## Tools

- **dbcrossbar** — copy data between databases, CSV, and cloud storage
- **ogr2ogr** — convert and load vector geospatial data (GDAL)
- **pgferry** — migrate MySQL/MariaDB/SQLite/MSSQL to PostgreSQL
- **scrubcsv / catcsv / fixed2csv / geochunk / hashcsv** — CSV manipulation
- **geocode-csv** — geocode CSV files
