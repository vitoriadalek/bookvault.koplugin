# BookVault

BookVault is a KOReader plugin that combines a virtual reading-status library with protected folders and private content.

## Features

- Virtual library: books stay in their original folders and are never moved, copied, renamed or duplicated.
- Recursive scanning of a configurable root folder.
- Reading statuses from KOReader's own `BookList.getBookStatus()`:
  - Lendo
  - Em espera
  - Concluídos
  - Não iniciados
- Native KOReader CoverBrowser mosaic integration when the built-in CoverBrowser modules are available.
- Opens the original book file directly.
- Numeric password with masked input.
- Salted password hash stored in BookVault settings; the password itself is never stored.
- Protected folders: navigation and file opening are gated by the same password.
- Private folders: hidden from the public BookVault library and available through `◉ Acessar conteúdo`.
- `◉ Ocultar conteúdo` relocks the private library.
- Private access is relocked on suspend/resume.
- No physical collection management and no changes to book files.

## Compatibility

Designed for current KOReader builds on Kindle, Kobo, PocketBook, reMarkable, Android and desktop where the standard KOReader plugin APIs used by BookVault are available.

The cover grid uses KOReader's existing CoverBrowser modules when they are loaded. If those modules are unavailable, the plugin keeps its library functional with KOReader's standard BookList rendering instead of failing to load.

## Installation

BookVault is distributed as a standard `.koplugin` directory through KOReader AppStore.

The repository must have the GitHub topic `koreader-plugin` for discovery by the current AppStore catalogue. The AppStore searches that topic as well as certain repository naming patterns. See the AppStore documentation for the current discovery rules.

## Data and privacy

BookVault stores only its configuration under KOReader's settings directory. Book files and their locations are not modified by the plugin.

Private/protected folder configuration is local to the KOReader installation. The password is stored as a salted hash.

## License

AGPL-3.0-or-later.
