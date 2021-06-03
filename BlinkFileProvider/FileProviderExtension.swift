//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K
//
// Copyright (C) 2016-2019 Blink Mobile Shell Project
//
// This file is part of Blink.
//
// Blink is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Blink is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Blink. If not, see <http://www.gnu.org/licenses/>.
//
// In addition, Blink is also subject to certain additional terms under
// GNU GPL version 3 section 7.
//
// You should have received a copy of these additional terms immediately
// following the terms and conditions of the GNU General Public License
// which accompanied the Blink Source Code. If not, see
// <http://www.github.com/blinksh/blink>.
//
////////////////////////////////////////////////////////////////////////////////


import FileProvider
import BlinkFiles
import Combine

// TODO Provide proper error subclassing. BlinkFilesProviderError
extension String: Error {}

enum BlinkFilesProtocol: String {
  case ssh = "ssh"
  case local = "local"
  case sftp = "sftp"
}

class FileTranslatorPool {
  static let shared = FileTranslatorPool()
  private var translators: [String: AnyPublisher<Translator, Error>] = [:]
  private var references: [String: BlinkItemReference] = [:]
  
  private init() {}
  
  static func translator(for encodedRootPath: String) -> AnyPublisher<Translator, Error> {
    guard let rootData = Data(base64Encoded: encodedRootPath),
          let rootPath = String(data: rootData, encoding: .utf8) else {
      return Fail(error: "Wrong encoded identifier for Translator").eraseToAnyPublisher()
    }
    
    // rootPath: ssh:host:root_folder
    let components = rootPath.split(separator: ":")
    
    // TODO At least two components. Tweak for sftp
    let p = BlinkFilesProtocol(rawValue: String(components[0]))
    let pathAtFiles: String
    if components.count == 2 {
      pathAtFiles = String(components[1])
    } else {
      pathAtFiles = String(components[2])
    }
    
    if let translator = shared.translators[encodedRootPath] {
      return translator
    }
    
    switch p {
    case .local:
      let translatorPub = Local().walkTo(pathAtFiles)
      shared.translators[encodedRootPath] = translatorPub
      return translatorPub
    default:
      return Fail(error: "Not implemented").eraseToAnyPublisher()
    }
  }
  
  static func store(reference: BlinkItemReference) {
    print("storing File BlinkItemReference : \(reference.itemIdentifier.rawValue)")
    shared.references[reference.itemIdentifier.rawValue] = reference
  }
  
  static func reference(identifier: NSFileProviderItemIdentifier) -> BlinkItemReference? {
    shared.references[identifier.rawValue]
  }
}

class FileProviderExtension: NSFileProviderExtension {
  
  var fileManager = FileManager()
  
  override init() {
    super.init()
  }

  // MARK: - BlinkItem Entry : DB-GET query (using uniq NSFileProviderItemIdentifier ID)
  override func item(for identifier: NSFileProviderItemIdentifier) throws -> NSFileProviderItem {
    print("ITEM \(identifier.rawValue) REQUESTED")
    
    //  TODO At least two components
//    let p = BlinkFilesProtocol(rawValue: String(components[0]))
//    let pathAtFiles: String
//    if components.count == 2 {
//      pathAtFiles = String(components[1])
//    } else {
//      pathAtFiles = String(components[2])
//    }
    
    // TODO We have no attributes here, but they are necessary. Metadata will have to be
    // stored somewhere else too.
    guard let reference = FileTranslatorPool.reference(identifier: identifier) else {
      throw NSError.fileProviderErrorForNonExistentItem(withIdentifier: identifier)
    }
    
    return FileProviderItem(reference: reference)
//    guard let reference = BlinkItemReference(itemIdentifier: identifier, rootPath: pathAtFiles) else {      throw NSError.fileProviderErrorForNonExistentItem(withIdentifier: identifier)
//    }
//
//    return FileProviderItem(reference: reference)
  }
  
  override func urlForItem(withPersistentIdentifier identifier: NSFileProviderItemIdentifier) -> URL? {
    // TODO: option B: init using translator cache pool
    // resolve the given identifier to a file (from translator)
//    guard let item = try? item(for: identifier) else {
//      return nil
//    }
        
    // TODO: option B option A: init BlinkItemIdentifier
    let blinkItemFromId = BlinkItemIdentifier(identifier)
    
    return  blinkItemFromId.alternativeUrl
  }
  
  // url => file:///Users/xxxx/Library/Developer/CoreSimulator/Devices/212A70E4-CE48-48C7-8A19-32357CE9B3BD/data/Containers/Shared/AppGroup/658A68A7-43BE-4C48-8586-C7029B0DCD9A/File%20Provider%20Storage/bG9jYWw6L3Vzcg==/L2xvY2Fs/filename
  
  // https://developer.apple.com/documentation/fileprovider/nsfileproviderextension/1623479-persistentidentifierforitematurl?language=objc
  //  define a static mapping between URLs and their persistent identifiers.
  //  A document's identifier should remain constant over time; it should not change when the document is edited, moved, or rename
  //  TODO: Always return nil if the _URL is not inside in the directory referred to by the NSFileProviderManager object's documentStorageURL_ property.
  override func persistentIdentifierForItem(at url: URL) -> NSFileProviderItemIdentifier? {
    
    let blinkItem = BlinkItemIdentifier(url: url)
    
    
    // resolve the given URL to a persistent identifier using a database
//    let pathComponents = url.pathComponents
    
    // exploit the fact that the path structure has been defined as
    // <base storage directory>/<item identifier>/<item file name> above
//    assert(pathComponents.count > 2)
//    let identifier = pathComponents[pathComponents.count - 2]
    
//    let identifier = url.deletingLastPathComponent().lastPathComponent
    
//    return NSFileProviderItemIdentifier(identifier)
    
    return blinkItem.itemIdentifier
  }
  

  override func providePlaceholder(at url: URL, completionHandler: @escaping (Error?) -> Void) {
    //A Look Up the Document's File Provider Item
    
    //A.1. Get the document’s persistent identifier by calling persistentIdentifierForItemAtURL:, and pass in the value of the url parameter.
    guard let identifier = persistentIdentifierForItem(at: url) else {
      completionHandler(NSFileProviderError(.noSuchItem))
      return
    }
    
    let localDirectory = url.deletingLastPathComponent()
    print("identifier \(identifier)")
    print("directory \(localDirectory)")
    
    do {
      
//      try fileManager.createDirectory(
//        at: localDirectory,
//        withIntermediateDirectories: true,
//        attributes: nil
//      )
    
      //A.2. Call itemForIdentifier:error:, and pass in the persistent identifier. This method returns the file provider item for the document.
      let fileProviderItem = try item(for: identifier)
      
      // B. Write the Placeholder
      
      // B.1 Get the placeholder URL by calling placeholderURLForURL:, and pass in the value of the url parameter.
      let placeholderURL = NSFileProviderManager.placeholderURL(for: url)
      
      // B.2 Call writePlaceholderAtURL:withMetadata:error:, and pass in the placeholder URL and the file provider item.
      try NSFileProviderManager.writePlaceholder(at: placeholderURL,withMetadata: fileProviderItem)
      
      
      completionHandler(nil)
      
      
    } catch let error {
      debugPrint(error)
      completionHandler(error)
    }
  }
  
  override func startProvidingItem(at url: URL, completionHandler: @escaping ((_ error: Error?) -> Void)) {
    
    // Should ensure that the actual file is in the position returned by URLForItemWithIdentifier:, then call the completion handler
    
    /* TODO:
     This is one of the main entry points of the file provider. We need to check whether the file already exists on disk,
     whether we know of a more recent version of the file, and implement a policy for these cases. Pseudocode:
   */
//    if !fileOnDisk {
//      downloadRemoteFile()
//      callCompletion(downloadErrorOrNil)
//    } else if fileIsCurrent {
//      callCompletion(nil)
//    } else {
//      if localFileHasChanges {
//        // in this case, a version of the file is on disk, but we know of a more recent version
//        // we need to implement a strategy to resolve this conflict
//        moveLocalFileAside()
//        scheduleUploadOfLocalFile()
//        downloadRemoteFile()
//        callCompletion(downloadErrorOrNil)
//      } else {
//        downloadRemoteFile()
//        callCompletion(downloadErrorOrNil)
//      }
//    }
//
    
    // 1 - From URL we get the identifier.
    
    guard let identifier = persistentIdentifierForItem(at: url) else {
      completionHandler(NSFileProviderError(.noSuchItem))
      return
    }
    
    // 2 - From the identifier, we get the translator, and we can walk to the remote file.
    
    let translator = FileTranslatorPool.translator(for: identifier.rawValue)
    
    // 3 - On local, the path is already the URL, so we walk to the local file path to provide there.
    // 4 - Copy from one to the other, and call the completionHandler once done.
    
    // file://
    completionHandler(NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError, userInfo:[:]))
  }
  
  override func itemChanged(at url: URL) {
    // Called at some point after the file has changed; the provider may then trigger an upload
    
    /* TODO:
     - mark file at <url> as needing an update in the model
     - if there are existing NSURLSessionTasks uploading this file, cancel them
     - create a fresh background NSURLSessionTask and schedule it to upload the current modifications
     - register the NSURLSessionTask with NSFileProviderManager to provide progress updates
     */
  }
  
  override func stopProvidingItem(at url: URL) {
    // Called after the last claim to the file has been released. At this point, it is safe for the file provider to remove the content file.
    // Care should be taken that the corresponding placeholder file stays behind after the content file has been deleted.
    
    // Called after the last claim to the file has been released. At this point, it is safe for the file provider to remove the content file.
    
    // TODO: look up whether the file has local changes
    let fileHasLocalChanges = false
    
    if !fileHasLocalChanges {
      // remove the existing file to free up space
      do {
        _ = try FileManager.default.removeItem(at: url)
      } catch {
        // Handle error
      }
      
      // write out a placeholder to facilitate future property lookups
      self.providePlaceholder(at: url, completionHandler: { error in
        // TODO: handle any error, do any necessary cleanup
      })
    }
  }
  
  // MARK: - Actions
  
  /* TODO: implement the actions for items here
   each of the actions follows the same pattern:
   - make a note of the change in the local model
   - schedule a server request as a background task to inform the server of the change
   - call the completion block with the modified item in its post-modification state
   */
  
  // MARK: - Enumeration
  
  override func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier) throws -> NSFileProviderEnumerator {

    let maybeEnumerator: NSFileProviderEnumerator? = nil
    print("Called enumerator for \(containerItemIdentifier.rawValue)")
    
    guard let domain = self.domain else {
      throw "No domain received."
    }

    if (containerItemIdentifier != NSFileProviderItemIdentifier.workingSet) {
      return FileProviderEnumerator(enumeratedItemIdentifier: containerItemIdentifier, domain: domain)
    } else {
      // We may want to do an empty FileProviderEnumerator, because otherwise it will try to request it again and again.
      throw NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError, userInfo:[:])
    }
  }
  
}
