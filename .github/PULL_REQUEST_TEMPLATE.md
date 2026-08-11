## Summary

<!-- Brief summary of the changes introduced in this PR. -->

## Type of Change

- [ ] 🐛 Bug fix (non-breaking change fixing an issue)
- [ ] ✨ New feature (non-breaking change adding functionality)
- [ ] 🧩 Extension API / Catalog update
- [ ] 📚 Documentation update
- [ ] ⚙️ Infrastructure / CI / Build tooling

## Verification & Testing

<!-- Describe the tests and verification steps executed. -->

- [ ] Ran `./scripts/test.sh --unit` cleanly
- [ ] Tested via `./scripts/dev_run.sh` or `./scripts/package_app.sh`

## Code Checklist

- [ ] Adheres to architectural rules in `AGENTS.md` (Swift 6 complete strict concurrency, pure `Core`).
- [ ] Uses `Log` subsystem categories (no `print()` or raw `Logger()`).
- [ ] No raw `UserDefaults.standard` in new domain code (routes via `SettingsStore` / Keychain).
- [ ] Updated documentation in `docs/` if modifying APIs or architecture.
