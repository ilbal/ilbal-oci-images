#!/bin/sh
set -e

if [ $# -eq 0 ] || [ "$1" = "--help" ]; then
  echo "Available tools:"
  echo "  dbcrossbar   — Copy data between databases, CSV, and cloud storage"
  echo "  ogr2ogr      — Convert and load vector geospatial data (GDAL)"
  echo "  pgferry      — Migrate MySQL/MariaDB/SQLite/MSSQL to PostgreSQL"
  echo "  scrubcsv     — Clean and standardize CSV files"
  echo "  catcsv       — Concatenate CSV files"
  echo "  fixed2csv    — Convert fixed-width fields to CSV"
  echo "  geochunk     — Group records by ZIP code into population chunks"
  echo "  hashcsv      — Add a hash-based ID column to CSV rows"
  echo "  geocode-csv  — Geocode CSV files using Smarty API or libpostal"
  echo ""
  echo "Usage: docker run --rm ilbal-ingest <tool> [args...]"
  exit 0
fi

exec "$@"
