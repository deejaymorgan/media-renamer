import Foundation

/// Read-only filesystem scanning. Ported from `list_dir` / `scan_folder_contents`.
public enum Scanner {

    /// Directory contents as URLs, sorted by name, skipping dotfiles by default.
    public static func listDir(_ directory: URL, includeHidden: Bool = false) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.sorted()
            .filter { includeHidden || !$0.hasPrefix(".") }
            .map { directory.appendingPathComponent($0) }
    }

    /// Recursively classify a folder's contents into (videos, sidecars, junk).
    /// Hidden files, ignored-library subfolders, and junk-named subfolders are
    /// not descended into; junk-named items are recorded as junk. Lists are
    /// returned sorted by path.
    public static func scanContents(_ folder: URL)
        -> (videos: [URL], sidecars: [URL], junk: [URL]) {
        var videos: [URL] = []
        var sidecars: [URL] = []
        var junk: [URL] = []

        func walk(_ dir: URL) {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?
                .sorted() ?? []
            for name in names {
                if name.hasPrefix(".") { continue }
                let path = dir.appendingPathComponent(name)
                if isDirectory(path) {
                    if Constants.ignoredFolderNames.contains(name.lowercased()) { continue }
                    if isJunk(name) { junk.append(path); continue }
                    walk(path)
                } else {
                    if isJunk(name) { junk.append(path); continue }
                    let ext = Str.splitext(name).ext.lowercased()
                    if Constants.videoExtensions.contains(ext) {
                        videos.append(path)
                    } else if Constants.subtitleExtensions.contains(ext) {
                        sidecars.append(path)
                    } else {
                        junk.append(path)
                    }
                }
            }
        }
        walk(folder)
        return (videos.sorted { $0.path < $1.path },
                sidecars.sorted { $0.path < $1.path },
                junk.sorted { $0.path < $1.path })
    }

    /// Whether a name marks an item as junk (case-insensitive substring of the
    /// junk patterns).
    static func isJunk(_ name: String) -> Bool {
        let lower = name.lowercased()
        return Constants.junkNamePatterns.contains { lower.contains($0) }
    }

    /// Whether the URL points at a directory.
    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue
    }
}
