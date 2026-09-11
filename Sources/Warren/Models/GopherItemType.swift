import Foundation

/// Gopher item types as defined in RFC 1436, section 3.8, plus the
/// widely deployed de facto extensions (`i`, `h`, `s`, `p`, `d`).
enum GopherItemType: Character, CaseIterable {
    // Canonical RFC 1436 types
    case textFile = "0"        // Item is a file
    case menu = "1"            // Item is a directory
    case csoServer = "2"       // Item is a CSO phone-book server
    case error = "3"           // Error
    case binhex = "4"          // Item is a BinHexed Macintosh file
    case dosBinary = "5"       // Item is DOS binary archive of some sort
    case uuencoded = "6"       // Item is a UNIX uuencoded file
    case search = "7"          // Item is an Index-Search server
    case telnet = "8"          // Item points to a text-based telnet session
    case binary = "9"          // Item is a binary file
    case redundant = "+"       // Item is a redundant server
    case tn3270 = "T"          // Item points to a text-based tn3270 session
    case gif = "g"             // Item is a GIF format graphics file
    case image = "I"           // Item is some kind of image file

    // De facto extensions in wide use on Gopherspace
    case info = "i"            // Informational text line (not selectable)
    case html = "h"            // HTML document / URL: link
    case sound = "s"           // Sound file
    case png = "p"             // PNG image
    case document = "d"        // Document (PDF, DOC, ...)

    var label: String {
        switch self {
        case .textFile: return "Text"
        case .menu: return "Menu"
        case .csoServer: return "CSO"
        case .error: return "Error"
        case .binhex: return "BinHex"
        case .dosBinary: return "DOS Archive"
        case .uuencoded: return "Uuencoded"
        case .search: return "Search"
        case .telnet: return "Telnet"
        case .binary: return "Binary"
        case .redundant: return "Mirror"
        case .tn3270: return "TN3270"
        case .gif: return "GIF"
        case .image: return "Image"
        case .info: return "Info"
        case .html: return "HTML"
        case .sound: return "Sound"
        case .png: return "PNG"
        case .document: return "Document"
        }
    }

    /// SF Symbol used in menu listings.
    var symbolName: String {
        switch self {
        case .textFile: return "doc.plaintext"
        case .menu: return "folder"
        case .csoServer: return "person.crop.rectangle.stack"
        case .error: return "exclamationmark.triangle"
        case .binhex, .dosBinary, .uuencoded, .binary: return "shippingbox"
        case .search: return "magnifyingglass"
        case .telnet, .tn3270: return "terminal"
        case .redundant: return "arrow.triangle.branch"
        case .gif, .image, .png: return "photo"
        case .info: return "info.circle"
        case .html: return "globe"
        case .sound: return "speaker.wave.2"
        case .document: return "doc.richtext"
        }
    }

    /// Types whose payload is opaque binary data (downloaded, not rendered).
    var isBinaryDownload: Bool {
        switch self {
        case .binhex, .dosBinary, .uuencoded, .binary, .sound, .document:
            return true
        default:
            return false
        }
    }

    /// Types rendered inline as an image.
    var isImage: Bool {
        switch self {
        case .gif, .image, .png: return true
        default: return false
        }
    }

    /// Whether a menu line of this type is selectable by the user.
    var isSelectable: Bool {
        switch self {
        case .info, .error: return false
        default: return true
        }
    }
}
