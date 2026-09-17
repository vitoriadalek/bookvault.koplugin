# BookVault

BookVault is a KOReader plugin that creates a virtual reading-status library without moving or copying books.

## Version 2.2.0

This release keeps the working visual mosaic from 2.1.x and adds a native, visible search button plus persistent custom ordering. The plugin continues to load KOReader's bundled CoverBrowser mosaic components lazily, only when a BookVault library or collection is opened.

### Visual library

- Real book covers in a 3 × 3-style mosaic, using KOReader's bundled CoverBrowser/Mosaic components.
- The mosaic is used for all reading-status categories: Todos, Lendo, Em espera, Concluídos and Não iniciados.
- The same cover mosaic is used for KOReader Collections opened through BookVault.
- Cover extraction and caching are delegated to KOReader's BookInfoManager.
- Reading progress/status hints from KOReader's mosaic system are retained.
- Partial rows are centered for a cleaner bookshelf appearance.
- KOReader's native search icon is now created directly in the BookVault BookList title bar, so search is visible instead of depending on a runtime icon replacement.
- Tap the search icon to search the current BookVault view.
- Hold the search icon to open sorting options.

### Sorting and custom order

- Sort by title.
- Sort by author when author metadata is available.
- Sort by most recent access.
- Sort by modification date.
- Sort by file size.
- Sort by page count when page metadata is available.
- **Custom order** is persistent and independent for each BookVault status category and each KOReader Collection.
- Custom order lets you move a book up, down, to the beginning or to the end, then saves the order for future sessions.
- Existing normal sorting remains available; custom order does not alter the files or KOReader's collections.

### Search

- Search is available from every visual library and collection screen.
- Search filters the current BookVault view without moving or modifying books.
- Clearing the search restores the complete current view.

### Stability model

- The visual modules are loaded lazily, only after BookVault is opened.
- No global FileChooser, FileManager, ReaderUI or CoverBrowser methods are replaced.
- Visual methods are attached only to the BookVault BookList instance being displayed.
- The core plugin registration does not require CoverBrowser modules, so an incompatibility there cannot prevent BookVault from appearing in Tools/Plugins.
- If the bundled CoverBrowser modules are unavailable on a particular KOReader build, BookVault falls back to the standard BookList instead of failing to register.
- BookVault continues to use KOReader's standard BookList and ReaderUI for navigation.
- Existing settings are preserved; custom-order data is stored as an additional BookVault setting and does not rewrite book files.

### Library and collections

- Recursive library scan from a configurable folder.
- Reading-status categories: Todos, Lendo, Em espera, Concluídos and Não iniciados.
- KOReader Collections are displayed directly inside BookVault.
- Collection entries are limited to books inside the configured BookVault library root.
- Private books remain hidden from collection views until content is unlocked.
- Choose which reading-status categories appear.
- Choose which KOReader Collections appear.
- Collection visibility is saved between sessions.
- Books stay in their original folders.

### Security and privacy

- Private folders are hidden from the public BookVault view until unlocked.
- Protected/private entries can require a numeric password before opening from BookVault.
- Passwords use salted SHA-256; plaintext passwords are not stored.
- Password changes require the current password.
- Protected/private folder lists can be managed from the plugin menu.
- Unlock state is cleared when KOReader suspends or resumes.

### Installation

Repository: `vitoriadalek/bookvault.koplugin`

Install from the KOReader community App Store when the repository is available to its index, or install the repository manually as a `.koplugin` folder for testing.

### Compatibility

The visual layer targets the current KOReader CoverBrowser components. The implementation uses the same `bookinfomanager.lua`, `covermenu.lua` and `mosaicmenu.lua` modules shipped with KOReader's CoverBrowser plugin, loaded lazily and without changing their global classes. The visible search button uses the standard KOReader `Menu` title-bar API (`title_bar_left_icon`) at BookVault menu construction time.

### Security limitation

Folder protection is KOReader UI access control, not filesystem encryption. Someone with direct filesystem access to the device can still access the files.

### License

AGPL-3.0-or-later.
