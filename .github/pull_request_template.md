## Qué cambia

## Por qué

<!-- Fuente o medición. Hardline no acepta tweaks sin efecto demostrable. -->

## Cómo se probó

- [ ] `tests\validate.ps1` pasa
- [ ] `.\install.ps1 -DryRun` en Windows real
- [ ] Todo cambio al sistema pasa por `Set-HLRegistryValue` / `Set-HLServiceStart` / `Backup-HLFile` / `Add-HLManifestEntry` (revertible con `rollback.ps1`)
- [ ] Docs actualizadas (`docs/TWEAKS_EXPLAINED.md`, `CHANGELOG.md`)
