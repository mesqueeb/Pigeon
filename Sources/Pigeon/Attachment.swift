import Foundation
import UniformTypeIdentifiers

struct Attachment {
  let filename: String
  let mediaType: String
  let data: Data

  init(path: String) throws {
    let url = URL(fileURLWithPath: path)
    filename = url.lastPathComponent
    guard !filename.isEmpty,
      !filename.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else {
      throw PigeonError("Attachment filenames must be nonempty and contain no control characters.")
    }

    mediaType =
      UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    do {
      let target = url.resolvingSymlinksInPath()
      guard try target.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
        throw PigeonError("Expected a regular file.")
      }
      data = try Data(contentsOf: target)
    } catch {
      throw PigeonError("Cannot read attachment \(filename): \(error.localizedDescription)")
    }
  }

  var disposition: String {
    let field = "Content-Disposition: attachment;"
    let quoted = filename.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    if filename.utf8.allSatisfy({ $0 < 128 }), quoted.utf8.count <= 64 {
      return field + "\r\n filename=\"\(quoted)\""
    }

    let attrCharacters = Set(
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-".utf8
    )
    var segments = ["UTF-8''"]
    for byte in filename.utf8 {
      let token =
        attrCharacters.contains(byte) ? String(UnicodeScalar(byte)) : String(format: "%%%02X", byte)
      if segments[segments.count - 1].utf8.count + token.utf8.count > 60 { segments.append("") }
      segments[segments.count - 1] += token
    }
    if segments.count == 1 { return field + "\r\n filename*=\(segments[0])" }
    let parameters = segments.enumerated().map { index, segment in "filename*\(index)*=\(segment)" }
    return field + "\r\n " + parameters.joined(separator: ";\r\n ")
  }
}
