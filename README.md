# BookVault

BookVault is a KOReader plugin that creates a virtual reading-status library without moving or copying your books.

## Version 2.0.0

Version 2.0.0 adds a visual library interface while preserving the stable BookVault 1.6 architecture.

- Cover grid for Todos, Lendo, Em espera, Concluídos and Não iniciados.
- The same visual presentation is used for KOReader Collections opened inside BookVault.
- Uses KOReader's CoverBrowser cover/metadata cache when its bundled modules are available.
- Falls back to the standard BookList instead of crashing if CoverBrowser modules are unavailable.
- Book covers are loaded through KOReader's existing cover extraction/cache system; BookVault does not modify book files.
- Reading status, opened-book indicators and other native mosaic details can be displayed by KOReader's CoverBrowser components.
- Decorative BookVault header with a small cat/moon visual, subtitle and book count.
- Search button in the header; long-pressing it opens sorting options.
- Search filters the current BookVault category or collection without changing the underlying library.
- Sorting options: title, most recently accessed, last modification and file size.
- Pagination remains native to KOReader's menu system.
- Books still open through KOReader's standard ReaderUI.
- Recursive library scan from a configurable folder.
- Filters: Todos, Lendo, Em espera, Concluídos and Não iniciados.
- Displays KOReader Collections directly inside BookVault.
- Collection entries are limited to books inside the configured BookVault library root.
- Private books remain hidden from collection views until content is unlocked.
- Choose which reading-status categories appear in the BookVault chooser.
- Choose which KOReader Collections appear in the BookVault chooser.
- Collection visibility is saved between KOReader sessions.
- Books stay in their original folders.
- Private folders are hidden from the public BookVault view until unlocked.
- Protected/private entries can require a numeric password before opening from BookVault.
- Passwords use salted SHA-256; plaintext passwords are not stored.
- Password changes require the current password.
- Protected/private folder lists can be managed from the plugin menu.
- Unlock state is cleared when KOReader suspends or resumes.
- Uses KOReader's standard BookList, ReaderUI and ReadCollection APIs for core library behavior.
- Does not monkey-patch FileChooser, FileManager, ReaderUI or CoverBrowser classes.
- CoverBrowser's own menu modules are used only on the BookVault menu instance to provide the native mosaic renderer.
- Does not modify KOReader's collection data.

## Collections

Open **BookVault → Biblioteca → Coleções** to browse the Collections already created in KOReader.

Collections are read from KOReader's native `ReadCollection` data, so BookVault does not create a second collection system or duplicate the collection database.

Open **BookVault → Biblioteca → Coleções exibidas** to choose which Collections are shown in the BookVault main chooser.

## Customizing the category buttons

Open **BookVault → Biblioteca → Categorias exibidas**.

Each reading-status category has a checkbox-style toggle. Changes are saved immediately, and BookVault prevents the last visible reading-status category from being disabled.

## Visual library

The visual grid is designed to work with KOReader's bundled CoverBrowser plugin. Stock KOReader builds normally include CoverBrowser. If CoverBrowser's modules are unavailable or disabled, BookVault safely falls back to its standard list presentation instead of failing to open the library.

The grid dimensions use KOReader's existing CoverBrowser settings when available, with BookVault defaults of 3 columns × 2 rows in portrait and 4 × 2 in landscape.

## Stability note

Version 2.0.0 keeps the stability changes from 1.4.0 and 1.6.0: no global FileChooser/FileManager/ReaderUI hooks and no replacement of CoverBrowser class methods. The visual layer is attached only to the BookVault menu instance and uses KOReader's existing CoverBrowser mosaic renderer and cover cache.

Actual runtime testing on the target KOReader device is still required before treating a specific device/build combination as verified.

## Installation

Repository: `vitoriadalek/bookvault.koplugin`

Install from the KOReader community App Store when the repository is available to the App Store index, or install the repository manually as a `.koplugin` folder for testing.

## Compatibility

Designed for current KOReader builds using standard plugin APIs and the bundled CoverBrowser modules when available.

## Security limitation

Folder protection is KOReader UI access control, not filesystem encryption. Someone with direct filesystem access to the device can still access the files.

## License

AGPL-3.0-or-later.
