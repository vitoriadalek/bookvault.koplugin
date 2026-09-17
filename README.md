# BookVault

BookVault is a KOReader plugin that combines a virtual reading-status library with protected folders and private content.

## Version 1.2.0

- Virtual library with recursive scanning of a configurable root.
- Books remain in their original folders: no moving, copying, renaming or physical collections.
- Reading status is read from KOReader's `BookList.getBookStatus()`:
  - Lendo
  - Em espera
  - Concluídos
  - Não iniciados
- Protected folders remain represented in the BookVault status library, while opening/navigating to them requires the password.
- Private folders are excluded from the public library until `◉ Acessar conteúdo` is unlocked.
- `◉ Ocultar conteúdo` immediately relocks the private view.
- Numeric masked password with salted SHA-256 hash; the plaintext password is never stored.
- Changing the password requires the current password.
- Removing protected/private folder entries requires the password when one exists.
- File-manager book opening and folder navigation are password-gated through KOReader's standard file-opening/navigation routes.
- Unlock state is cleared on suspend/resume and when leaving a protected folder.
- Native CoverBrowser mosaic helpers are reused when available; if unavailable, BookVault falls back to standard BookList rendering instead of failing to load.
- Selecting a book opens the original file.

## Installation

KOReader AppStore installs repositories as `<name>.koplugin` folders and validates `_meta.lua`. The current AppStore searches GitHub's `koreader-plugin` topic and also repository naming patterns. See the AppStore documentation for current discovery behavior.

Repository: `vitoriadalek/bookvault.koplugin`

For an immediate test, use the AppStore's plugin installation-from-URL flow with the repository above, then restart KOReader when prompted.

## Compatibility

Designed for current KOReader builds on Kindle, Kobo, PocketBook, reMarkable, Android and desktop using standard KOReader plugin APIs.

## Data and privacy

BookVault stores only its settings under KOReader's settings directory. Book files themselves are not modified. Folder protection is a KOReader UI access control, not filesystem encryption: someone with direct filesystem access to the device can still access the files.

## License

AGPL-3.0-or-later.
