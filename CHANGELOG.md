# Changelog

## 1.0.0 — 2026-10-10

First release. Navidrome in Container Manager:
- it plays your music folder, read-only;
- your account is made at the first start, with the password shown once;
- a package administrator handles the window's work.

The DSM window adds:
- **Library:**
  - counts and the last scan;
  - scan now or read everything again, and how often to look;
  - change the music folder: missing folders are refused, never created;
  - songs that left the folder are counted separately;
  - share links on or off.
- **Phones:** a QR code and recommended apps.
- **Users:** add people, new passwords (shown once), administrator on or off,
  remove.
- **Site address:** HTTPS with DSM's certificate.

Also included: consistent backups, updates and removal. If the music folder
isn't there yet, Navidrome starts on an empty placeholder and picks the folder
up when it appears.
