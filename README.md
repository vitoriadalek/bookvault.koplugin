# BookVault

BookVault is a KOReader plugin that creates a virtual reading-status library without moving or copying your books.

## Version 1.4.0

- Recursive library scan from a configurable folder.
- Filters: Todos, Lendo, Em espera, Concluídos and Não iniciados.
- Books stay in their original folders.
- Private folders are hidden from the public BookVault view until unlocked.
- Protected/private entries can require a numeric password before opening from BookVault.
- Passwords use salted SHA-256; plaintext passwords are not stored.
- Password changes require the current password.
- Protected/private folder lists can be managed from the plugin menu.
- Unlock state is cleared when KOReader suspends or resumes.
- Uses KOReader's standard BookList and ReaderUI APIs for stability.
- Does not monkey-patch the file manager, reader, FileChooser or CoverBrowser.
- Does not modify book files.

## Stability note

Version 1.4.0 removes the previous global FileChooser/FileManager/ReaderUI hooks and the CoverBrowser method replacement. Those were fragile across KOReader versions and could cause crashes. BookVault now keeps its functionality inside the plugin and uses the standard reading/opening flow.

## Installation

Repository: `vitoriadalek/bookvault.koplugin`

Install from KOReader's App Store when the repository is available to the App Store index, or install the repository manually as a `.koplugin` folder for testing.

## Compatibility

Designed for current KOReader builds using standard plugin APIs.

## Security limitation

Folder protection is KOReader UI access control, not filesystem encryption. Someone with direct filesystem access to the device can still access the files.

## License

AGPL-3.0-or-later.
