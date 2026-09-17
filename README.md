# BookVault

BookVault is a KOReader plugin that creates a virtual reading-status library without moving or copying your books.

## Version 1.6.0

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
- Uses KOReader's standard BookList, ReaderUI and ReadCollection APIs for stability.
- Does not monkey-patch the file manager, reader, FileChooser or CoverBrowser.
- Does not modify book files or KOReader's collection data.

## Collections

Open **BookVault → Biblioteca → Coleções** to browse the Collections already created in KOReader.

Collections are read from KOReader's native `ReadCollection` data, so BookVault does not create a second collection system or duplicate the collection database.

Open **BookVault → Biblioteca → Coleções exibidas** to choose which Collections are shown in the BookVault main chooser.

## Customizing the category buttons

Open **BookVault → Biblioteca → Categorias exibidas**.

Each reading-status category has a checkbox-style toggle. Changes are saved immediately, and BookVault prevents the last visible reading-status category from being disabled.

## Stability note

Version 1.6.0 keeps the stability changes from 1.4.0: no global FileChooser/FileManager/ReaderUI hooks and no CoverBrowser method replacement. Collection support is read-only and uses KOReader's native `ReadCollection` data.

## Installation

Repository: `vitoriadalek/bookvault.koplugin`

Install from KOReader's App Store when the repository is available to the App Store index, or install the repository manually as a `.koplugin` folder for testing.

## Compatibility

Designed for current KOReader builds using standard plugin APIs.

## Security limitation

Folder protection is KOReader UI access control, not filesystem encryption. Someone with direct filesystem access to the device can still access the files.

## License

AGPL-3.0-or-later.
