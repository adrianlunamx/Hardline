# Contribuir

Gracias por querer mejorar Hardline. Tres reglas por encima de todo:

1. **Nada de placebo.** Cada cambio necesita una fuente (documentación oficial, medición, benchmark) o una forma de medirlo. Si un tweak circula mucho pero no tiene efecto, va a la sección "Lo que Hardline NO hace" de [TWEAKS_EXPLAINED.md](docs/TWEAKS_EXPLAINED.md), no al código.
2. **Todo revertible.** Ningún módulo toca el sistema directamente: usa `Set-HLRegistryValue`, `Set-HLServiceStart`, `Backup-HLFile` o `Add-HLManifestEntry` (en `src/core/common.ps1`). Si añades un tipo de cambio nuevo, añade también su caso en `Undo-HLManifestEntry`.
3. **No tocar el proceso del juego.** Ni memoria, ni prioridad, ni afinidad, ni archivos del juego. Solo la configuración de usuario que el propio juego guarda en `Documentos\Call of Duty\players`.

## Probar

```powershell
.\tests\validate.ps1        # sintaxis, codificación, EQ, parser de Warzone, AutoEq, rollback...
.\install.ps1 -DryRun       # recorre todo sin aplicar nada (en Windows real)
```

`tests/validate.ps1` también funciona con `pwsh` en Linux/macOS (omite los tests de registro). El CI lo ejecuta en Windows con PowerShell 5.1 y 7, más PSScriptAnalyzer.

## Codificación

- `install.ps1` es **ASCII puro**: llega por `irm | iex` y Windows PowerShell 5.1 corrompe cualquier carácter no ASCII sin BOM.
- El resto de `.ps1` con tildes van en **UTF-8 con BOM**. El test de codificación lo comprueba.

## Estilo

- Comentarios y mensajes en español, directos. Sin emojis ni lenguaje de marketing.
- Explica el *por qué* de cada tweak en un comentario y en `docs/TWEAKS_EXPLAINED.md`.
- Mensajes de consola con `Write-HLStep` / `Write-HLOk` / `Write-HLWarn` / `Write-HLSub`, resultados con `Add-HLResult` y lo que el usuario debe hacer a mano con `Add-HLManualStep`.

## Añadir un headset

Copia un bloque en `src/audio/profiles/headsets.json`, ajusta `match` y filtros, y ejecuta los tests: comprueban rangos, que el primer filtro sea un `LSC` y que el preamp calculado no deje clipping. Para modelos no incluidos, AutoEq ya cubre ~8800 auriculares desde el menú.

## Publicar una versión

1. Sube la versión en `src/core/common.ps1` (`$HLVersion`) y añade la entrada en `CHANGELOG.md`.
2. `git tag vX.Y.Z && git push origin vX.Y.Z`, o desde la web: Releases > *Draft a new release* > tag `vX.Y.Z` (crear al publicar) sobre `main` > *Publish*.
3. El workflow valida, empaqueta `hardline-X.Y.Z.zip` + `.sha256` y publica la release con las notas del CHANGELOG. El instalador descarga siempre la última release y verifica su hash.
