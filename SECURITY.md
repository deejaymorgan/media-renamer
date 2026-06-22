# Security Policy

Media Renamer is a local macOS app with no servers, accounts, or network calls —
it reads a folder you choose and renames/moves files on your own disk. The main
risk surface is therefore the file operations themselves (renames, empty-folder
cleanup, and sending junk to the Trash).

## Supported versions

This is a personal project, so only the latest `main` is supported. Fixes land
there; there are no backported releases.

## Reporting a vulnerability

Please **report privately first** rather than opening a public issue:

- Use GitHub's **[Private vulnerability reporting](https://github.com/deejaymorgan/media-renamer/security/advisories/new)**
  (the *Security* tab → *Report a vulnerability*).

Helpful things to include:

- what the issue is and its impact (e.g. data loss, a path that escapes the
  chosen folder, an unexpected deletion),
- the smallest steps or sample folder layout that reproduces it,
- the macOS and app/commit version you saw it on.

## Expectations

This is maintained as-is, on a best-effort basis, with **no guaranteed response
time or fix**. Reports are still very welcome and will be looked at when time
allows. As always, **keep a backup of media you care about** before running bulk
file operations, and try the app on a copy first.
