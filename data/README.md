# data

This folder is for runtime configuration and generated exports only.

Application data is stored in PostgreSQL tables, not in JSON files.

Copy `db.env.example.ps1` to `db.env.ps1` and edit it for your local PostgreSQL connection. `db.env.ps1` is ignored by Git because it may contain a password.
