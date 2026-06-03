# data

This folder is for generated local artifacts and committed backup output.

Production application data is stored in Cloud Firestore:

```text
families/forhome/state/app
```

GitHub Actions writes dated backup files under:

```text
data/backups/YYYY-MM-DD/state.json
```

Files under `data/exports` are local integration artifacts and are not the primary application data store.
