# BookVault

BookVault is a KOReader plugin that creates a virtual reading-status library without moving or copying books.

## Version 2.0.1

This release prioritizes the plugin loader and keeps the stable BookVault core after the experimental visual layer caused compatibility problems on some KOReader builds.

- Recursive library scan from a configurable folder.
- Reading-status categories: Todos, Lendo, Em espera, Concluídos and Não iniciados.
- KOReader Collections are displayed directly inside BookVault.
- Collection entries are limited to books inside the configured BookVault library root.
- Private books remain hidden from collection views until content is unlocked.
- Choose which reading-status categories appear.
- Choose which KOReader Collections appear.
- Collection visibility is saved between sessions.
- Books stay in their original folders.
- Private folders are hidden from the public BookVault view until unlocked.
- Protected/private entries can require a numeric password before opening from BookVault.
- Passwords use salted SHA-256; plaintext passwords are not stored.
- Password changes require the current password.
- Protected/private folder lists can be managed from the plugin menu.
- Unlock state is cleared when KOReader suspends or resumes.
- Uses KOReader's standard BookList, ReaderUI and ReadCollection APIs.
- No global FileChooser, FileManager, ReaderUI or CoverBrowser monkey patches.
- No modification of book files or KOReader collection data.
- BookList keeps `covers_fullscreen` enabled so the library remains compatible with KOReader's native cover presentation without replacing KOReader classes.

## Collections

Open **BookVault → Biblioteca → Coleções** to browse Collections already created in KOReader.

Collections are read from KOReader's native `ReadCollection` data. BookVault does not create a second collection database.

## Categories

Open **BookVault → Biblioteca → Categorias exibidas** to choose which reading-status categories appear. BookVault prevents the last visible status category from being disabled.

## Stability

The 2.0.1 loader intentionally uses only modules that were already part of the stable BookVault implementation. Experimental custom TitleBar, CoverBrowser module loading and per-instance mosaic method replacement were removed from the active loader because they could make the plugin fail to load on a KOReader build before BookVault could register itself in the Tools/Plugins menu.

The cat SVG remains in the repository for the future visual layer, but it is not loaded by the core plugin at startup.

## Installation

Repository: `vitoriadalek/bookvault.koplugin`

Install from the KOReader community App Store when the repository is available to its index, or install the repository manually as a `.koplugin` folder for testing.

## Compatibility

Designed for current KOReader builds using standard plugin APIs.

## Security limitation

Folder protection is KOReader UI access control, not filesystem encryption. Someone with direct filesystem access to the device can still access the files.

## License

AGPL-3.0-or-later.
