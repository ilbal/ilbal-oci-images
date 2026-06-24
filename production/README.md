# Production Image — Extension Sync

## The Problem

The production image is built from `config.toml` — only the uncommented extension
sections are compiled into the image.  Meanwhile, the user runs `CREATE EXTENSION`
in their dev database to activate extensions.  Over time these two lists can drift:
extensions used in the app might be commented out in `config.toml`, or the config
might include extensions the app no longer needs.

Keeping them in sync ensures the production image contains exactly what the
application requires — nothing more, nothing less.

---

## Checking Extensions in PostgreSQL

These `psql` / SQL commands help inspect which extensions are present:

| Command | What it shows |
|---|---|
| `\dx` | Extensions **installed** in the current database (via `CREATE EXTENSION`) |
| `SELECT * FROM pg_extension;` | Same as `\dx`, query form |
| `SELECT * FROM pg_available_extensions;` | All extensions whose `.control` files exist on disk — i.e. compiled into the image and ready to `CREATE EXTENSION` |

The build is correct when `pg_available_extensions` contains every extension
uncommented in `config.toml`.

---

## Option 1: Database introspection (recommended)

A CLI subcommand (e.g. `ilbal scan-db`) connects to a running development
PostgreSQL instance and queries:

```sql
SELECT extname FROM pg_extension;
```

It then rewrites `config.toml`:

- Uncomments the section for every extension that is currently installed.
- Comments out every other extension.
- Leaves `[runtime_base]` untouched.

**Workflow:**

```
$ ilbal scan-db
  → config.toml updated: 3 extensions uncommented, 11 commented out
$ nix build .#pg18
  → production image contains only those 3 extensions
```

This is the simplest approach because the live database is always the true
source of truth for what the application uses.

---

## Option 2: Migration parsing

The CLI scans migration files (SQL, or a project's migration directory) for
`CREATE EXTENSION` statements and generates `config.toml` from those.

Useful when you want the source of truth to live in version-controlled migration
files rather than in a running database.

---

## Option 3: CI validation gate

During the production image build, a script spins up a temporary PostgreSQL
instance, runs the application migrations, queries `pg_extension`, and diffs
the result against the uncommented sections in `config.toml`.  If they don't
match, the build fails with a clear error message.

This prevents accidental drift from reaching production.

---

## Option 4: Entrypoint guard

The container entrypoint, on first start with a fresh `PGDATA`, queries
`pg_extension` after running the bootstrap and compares it against an expected
list baked into the image from `config.toml`.  If the image contains extensions
that are not in the config (or vice versa), a warning is logged.

This is a safety net rather than a prevention mechanism.

---

## Summary

| Option                | When to use                                           |
|-----------------------|-------------------------------------------------------|
| Database introspection | Everyday workflow — source of truth is the live DB   |
| Migration parsing     | Source of truth is version-controlled migration files |
| CI validation         | As a build-time safety gate                           |
| Entrypoint guard      | As a runtime safety net                               |

All four can be combined.  The recommended starting point is **Option 1**.
