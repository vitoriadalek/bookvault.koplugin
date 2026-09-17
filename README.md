# BookVault

BookVault is a KOReader plugin that creates a virtual reading-status library without moving or copying books.

## Version 2.1.3

This release fixes the mosaic integration used by BookVault's status and collection views.

### Visual library

- Real book covers in a 3 × 3-style mosaic, using KOReader's bundled CoverBrowser/Mosaic components.
- The mosaic is used for **all reading-status categories**: Todos, Lendo, Em espera, Concluídos and Não iniciados.
- The same cover mosaic is used for **KOReader Collections** opened through BookVault.
- Cover extraction and caching are delegated to KOReader's BookInfoManager.
- Reading progress/status hints from KOReader's mosaic system are retained.
- Partial rows are centered for a cleaner bookshelf appearance.
- A BookVault cat icon is used as the title-bar button when the writable user icon directory is available.
- Tap the cat/search button to search the current BookVault view.
- Hold the cat/search button to choose sorting: title, most recent access, modification date or file size.
- The mosaic now deliberately keeps KOReader's native `BookList.getBookInfo()` for reading status/progress; CoverBrowser's BookInfoManager is used separately for cover extraction. This matches the way KOReader's own MosaicMenu is structured.
- BookVault performs a first visual redraw before displaying the menu. If that redraw fails, it restores the native BookList methods and displays the normal BookList instead of leaving a blank/error screen.

### Stability model

- The visual modules are loaded lazily, only after BookVault is opened.
- No global FileChooser, FileManager, ReaderUI or CoverBrowser methods are replaced.
- Visual methods are attached only to the BookVault BookList instance being displayed.
- The core plugin registration does not require CoverBrowser modules, so an incompatibility there cannot prevent BookVault from appearing in Tools/Plugins.
- BookVault continues to use KOReader's standard BookList and ReaderUI for navigation.
- Visual failures are contained with a native BookList fallback.

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

The visual layer targets the current KOReader CoverBrowser components. The implementation uses the same `bookinfomanager.lua`, `covermenu.lua` and `mosaicmenu.lua` modules shipped with KOReader's CoverBrowser plugin, loaded lazily and without changing their global classes.

### Security limitation

Folder protection is KOReader UI access control, not filesystem encryption. Someone with direct filesystem access to the device can still access the files.

### License

AGPL-3.0-or-later.
