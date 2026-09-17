# BookVault

BookVault is a KOReader plugin that creates a virtual reading-status library without moving or copying books.

## Version 2.1.0

BookVault 2.1.0 keeps the stable loader while adding a lazy visual library layer. Covers are rendered through KOReader's existing CoverBrowser mosaic components only when a BookVault library or collection is opened.

- Cover mosaic with real book covers.
- Visual mosaic applies to **Todos, Lendo, Em espera, Concluídos and Não iniciados**.
- The same visual mosaic applies to KOReader Collections opened inside BookVault.
- Cover metadata/progress presentation comes from KOReader's existing mosaic implementation.
- Cute BookVault cat icon in the visual library title bar.
- Tapping the cat icon opens search; holding it opens sorting.
- Sorting: title, most recently read, modified recently and size.
- Search and sorting operate on the current BookVault dataset without moving or changing books.
- If the CoverBrowser mosaic modules are unavailable on a KOReader build, BookVault automatically falls back to the stable native BookList instead of failing to load.
- Recursive library scan from a configurable folder.
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
- No global FileChooser, FileManager, ReaderUI or CoverBrowser monkey patches.
- No modification of book files or KOReader collection data.

## Stability design

The visual layer is intentionally lazy. `coverbrowser`, `covermenu` and `mosaicmenu` are not required while KOReader is loading the BookVault plugin. This is important because an incompatible optional UI dependency must not prevent BookVault from registering in Tools/Plugins.

When the library opens, BookVault creates a normal `BookList` instance and applies KOReader's current CoverBrowser mosaic implementation to that instance only. The integration also provides the `getBookInfo` callback expected by KOReader's mosaic items.

All visual integration is wrapped in protected calls and has a native BookList fallback. BookVault does not replace global FileChooser, FileManager, ReaderUI or CoverBrowser class methods.

The cat SVG is also copied lazily into KOReader's writable user icon directory only when a visual library is opened. If that write is unavailable, the title bar falls back to the standard search icon and the library continues working.

## Collections

Open **BookVault → Biblioteca → Coleções** to browse Collections already created in KOReader.

Collections are read from KOReader's native `ReadCollection` data. BookVault does not create a second collection database.

## Categories

Open **BookVault → Biblioteca → Categorias exibidas** to choose which reading-status categories appear. BookVault prevents the last visible status category from being disabled.

## Installation

Repository: `vitoriadalek/bookvault.koplugin`

Install from the KOReader community App Store when the repository is available to its index, or install the repository manually as a `.koplugin` folder for testing.

## Compatibility

Designed for current KOReader builds using standard plugin APIs. The cover mosaic follows the current KOReader CoverBrowser implementation and automatically falls back to native BookList if those optional modules are unavailable.

## Security limitation

Folder protection is KOReader UI access control, not filesystem encryption. Someone with direct filesystem access to the device can still access the files.

## License

AGPL-3.0-or-later.
