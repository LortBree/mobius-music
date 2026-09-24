import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  private let minimumWindowSize = NSSize(
    width: 960,
    height: 640
  )

  private let securityScopedBookmarkPrefix =
    "Mobius.SecurityScopedBookmark."

  private var activeSecurityScopedURLs: [String: URL] = [:]

  override func awakeFromNib() {
    super.awakeFromNib()

    self.delegate = self

    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Native macOS minimum size. This prevents the user from
    // shrinking Mobius below the layout's usable dimensions.
    self.minSize = minimumWindowSize
    self.contentMinSize = NSSize(
      width: minimumWindowSize.width,
      height: minimumWindowSize.height - titlebarHeight
    )

    var frame = self.frame
    frame.size.width = max(
      frame.size.width,
      minimumWindowSize.width
    )
    frame.size.height = max(
      frame.size.height,
      minimumWindowSize.height
    )

    self.setFrame(
      frame,
      display: true
    )

    registerSecurityScopedBookmarkChannel(
      with: flutterViewController
    )

    RegisterGeneratedPlugins(
      registry: flutterViewController
    )
  }

  deinit {
    for url in activeSecurityScopedURLs.values {
      url.stopAccessingSecurityScopedResource()
    }
  }

  private func registerSecurityScopedBookmarkChannel(
    with flutterViewController: FlutterViewController
  ) {
    let channel = FlutterMethodChannel(
      name: "mobius/security_scoped_folder",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(
            code: "WINDOW_UNAVAILABLE",
            message: "Mobius window is unavailable.",
            details: nil
          )
        )
        return
      }

      switch call.method {
      case "saveBookmark":
        guard
          let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String,
          !path.isEmpty
        else {
          result(
            FlutterError(
              code: "INVALID_ARGUMENT",
              message: "A non-empty folder path is required.",
              details: nil
            )
          )
          return
        }

        do {
          try self.saveSecurityScopedBookmark(for: path)
          result(true)
        } catch {
          result(
            FlutterError(
              code: "BOOKMARK_SAVE_FAILED",
              message: error.localizedDescription,
              details: nil
            )
          )
        }

      case "restoreBookmark":
        guard
          let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String,
          !path.isEmpty
        else {
          result(
            FlutterError(
              code: "INVALID_ARGUMENT",
              message: "A non-empty folder path is required.",
              details: nil
            )
          )
          return
        }

        do {
          let restoredPath =
            try self.restoreSecurityScopedBookmark(for: path)

          result(restoredPath)
        } catch {
          result(nil)
        }

      case "removeBookmark":
        guard
          let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String,
          !path.isEmpty
        else {
          result(
            FlutterError(
              code: "INVALID_ARGUMENT",
              message: "A non-empty folder path is required.",
              details: nil
            )
          )
          return
        }

        self.removeSecurityScopedBookmark(for: path)
        result(true)

      case "restoreAllBookmarks":
        let restoredPaths =
          self.restoreAllSecurityScopedBookmarks()

        result(restoredPaths)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func bookmarkKey(for path: String) -> String {
    return securityScopedBookmarkPrefix + path
  }

  private func saveSecurityScopedBookmark(
    for path: String
  ) throws {
    let url = URL(fileURLWithPath: path)

    guard url.isFileURL else {
      throw NSError(
        domain: "MobiusSecurityScopedBookmark",
        code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "The selected folder is not a file URL."
        ]
      )
    }

    let bookmarkData = try url.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )

    UserDefaults.standard.set(
      bookmarkData,
      forKey: bookmarkKey(for: path)
    )

    startAccessing(url: url, for: path)
  }

  private func restoreSecurityScopedBookmark(
    for path: String
  ) throws -> String {
    guard
      let bookmarkData =
        UserDefaults.standard.data(
          forKey: bookmarkKey(for: path)
        )
    else {
      throw NSError(
        domain: "MobiusSecurityScopedBookmark",
        code: 2,
        userInfo: [
          NSLocalizedDescriptionKey:
            "No security-scoped bookmark exists for this folder."
        ]
      )
    }

    var isStale = false

    let url = try URL(
      resolvingBookmarkData: bookmarkData,
      options: [.withSecurityScope],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    )

    guard url.isFileURL else {
      throw NSError(
        domain: "MobiusSecurityScopedBookmark",
        code: 3,
        userInfo: [
          NSLocalizedDescriptionKey:
            "The stored bookmark does not resolve to a file URL."
        ]
      )
    }

    if isStale {
      let refreshedBookmark = try url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )

      UserDefaults.standard.set(
        refreshedBookmark,
        forKey: bookmarkKey(for: path)
      )
    }

    startAccessing(url: url, for: path)

    return url.path
  }

  private func restoreAllSecurityScopedBookmarks() -> [String] {
    let defaults = UserDefaults.standard.dictionaryRepresentation()

    let keys = defaults.keys
      .filter {
        $0.hasPrefix(securityScopedBookmarkPrefix)
      }
      .sorted()

    var restoredPaths: [String] = []

    for key in keys {
      let path = String(
        key.dropFirst(securityScopedBookmarkPrefix.count)
      )

      do {
        let restoredPath =
          try restoreSecurityScopedBookmark(for: path)

        restoredPaths.append(restoredPath)
      } catch {
        // Keep the saved bookmark. The user can re-select the
        // folder if the bookmark can no longer be resolved.
      }
    }

    return restoredPaths
  }

  private func startAccessing(
    url: URL,
    for path: String
  ) {
    if activeSecurityScopedURLs[path] != nil {
      return
    }

    if url.startAccessingSecurityScopedResource() {
      activeSecurityScopedURLs[path] = url
    }
  }

  private func removeSecurityScopedBookmark(
    for path: String
  ) {
    if let url = activeSecurityScopedURLs.removeValue(forKey: path) {
      url.stopAccessingSecurityScopedResource()
    }

    UserDefaults.standard.removeObject(
      forKey: bookmarkKey(for: path)
    )
  }

  func windowWillResize(
    _ sender: NSWindow,
    to frameSize: NSSize
  ) -> NSSize {
    return NSSize(
      width: max(
        frameSize.width,
        minimumWindowSize.width
      ),
      height: max(
        frameSize.height,
        minimumWindowSize.height
      )
    )
  }

  private var titlebarHeight: CGFloat {
    let contentRect = NSWindow.contentRect(
      forFrameRect: NSRect(
        x: 0,
        y: 0,
        width: minimumWindowSize.width,
        height: minimumWindowSize.height
      ),
      styleMask: self.styleMask
    )

    return minimumWindowSize.height -
        contentRect.height
  }
}
