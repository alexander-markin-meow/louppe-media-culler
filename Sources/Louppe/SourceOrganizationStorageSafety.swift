import Darwin
import Foundation

// Swift imports `struct statfs` under the same name as statfs(2).
@_silgen_name("statfs")
private func louppeOrganizationStatFS(
    _ path: UnsafePointer<CChar>,
    _ information: UnsafeMutablePointer<Darwin.statfs>
) -> Int32

struct SourceOrganizationStorageSafety: Equatable, Sendable {
    let fileSystemName: String?

    var usesReducedDirectoryDurability: Bool {
        fileSystemName?.lowercased() == "exfat"
    }

    var directorySyncPolicy: DurableFileIO.DirectorySyncPolicy {
        usesReducedDirectoryDurability ? .allowUnsupported : .required
    }

    var noOverwriteRenameStrategy: DurableFileIO.NoOverwriteRenameStrategy {
        usesReducedDirectoryDurability ? .foundation : .exclusivePOSIX
    }

    static func detect(at folder: URL) -> Self {
        var information = Darwin.statfs()
        let result = folder.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return louppeOrganizationStatFS(path, &information)
        }
        guard result == 0 else { return Self(fileSystemName: nil) }
        var rawName = information.f_fstypename
        let rawNameSize = MemoryLayout.size(ofValue: rawName)
        let name = withUnsafePointer(to: &rawName) { pointer in
            pointer.withMemoryRebound(
                to: CChar.self,
                capacity: rawNameSize
            ) {
                String(cString: $0)
            }
        }
        return Self(fileSystemName: name)
    }
}
