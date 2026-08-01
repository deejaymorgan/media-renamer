#!/usr/bin/env bash
#
# make-scratch.sh — build a small throwaway fixture tree for exercising the
# app's Apply path end to end (preview → Apply → disk check).
#
#   ./scripts/make-scratch.sh /tmp/renamer-scratch
#
# Creates the given folder and fills it with tiny dummy files (a few printf'd
# bytes — no real media). Refuses to run if the target already exists, so it
# can never be pointed at a real library. It only generates fixtures: it never
# launches the app and never deletes anything.
#
# What each piece of the tree exercises:
#   - a two-season show split across two source folders, one episode with a
#     subtitle sidecar — the Folders tree, sidecar renaming, and the cleanup
#     of emptied source folders;
#   - a movie in its own folder — the Flat pull-up;
#   - sample.mkv + inception.nfo INSIDE that movie folder — the junk → Trash
#     path. Placement is load-bearing: junk is only detected on a node being
#     renamed, so at the root neither file would reach it;
#   - one loose, already-correctly-named movie at the root — should plan
#     unchanged. Movie-shaped on purpose: it inherits the global Flat layout,
#     where a TV-shaped file would fold into the show and be moved by the
#     run's TV override. A different title from the movie folder's, so it
#     cannot merge into that node.

set -euo pipefail

[ $# -eq 1 ] || { echo "usage: $0 <scratch-folder-to-create>" >&2; exit 2; }
TARGET="$1"

if [ -e "$TARGET" ]; then
  echo "error: $TARGET already exists — refusing to touch it." >&2
  echo "This script only creates fresh scratch trees; point it at a path that" >&2
  echo "does not exist yet (e.g. /tmp/renamer-scratch)." >&2
  exit 1
fi

dummy() { printf 'scratch fixture — not real media\n' > "$1"; }

mkdir -p "$TARGET/The.Bear.S01.Complete" \
         "$TARGET/The.Bear.S02E01.1080p" \
         "$TARGET/Inception.2010.1080p"

dummy "$TARGET/The.Bear.S01.Complete/the.bear.s01e01.1080p.mkv"
dummy "$TARGET/The.Bear.S01.Complete/the.bear.s01e01.1080p.en.srt"
dummy "$TARGET/The.Bear.S01.Complete/the.bear.s01e02.1080p.mkv"
dummy "$TARGET/The.Bear.S02E01.1080p/The.Bear.S02E01.mkv"
dummy "$TARGET/Inception.2010.1080p/inception.2010.1080p.mkv"
dummy "$TARGET/Inception.2010.1080p/sample.mkv"
dummy "$TARGET/Inception.2010.1080p/inception.nfo"
dummy "$TARGET/Heat (1995).mkv"

echo "Scratch tree created at $TARGET:"
find "$TARGET" | sort
