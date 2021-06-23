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
    let remoteProtocol = BlinkFilesProtocol(rawValue: String(components[0]))
    let pathAtFiles: String
    let host: String?
    if components.count == 2 {
      pathAtFiles = String(components[1])
      host = nil
    } else {
      pathAtFiles = String(components[2])
      host = String(components[1])
    }
    
    if let translator = shared.translators[encodedRootPath] {
      return translator
    }
    
    switch remoteProtocol {
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
  var cancellableBag: Set<AnyCancellable> = []

  override init() {
    super.init()
  }

  // MARK: - BlinkItem Entry : DB-GET query (using uniq NSFileProviderItemIdentifier ID)
  override func item(for identifier: NSFileProviderItemIdentifier) throws -> NSFileProviderItem {
    print("ITEM \(identifier.rawValue) REQUESTED")
    
    var queryableIdentifier: NSFileProviderItemIdentifier!
    
    if identifier == .rootContainer {
      queryableIdentifier = NSFileProviderItemIdentifier("bG9jYWw6Lw==/")

    } else {
      queryableIdentifier = identifier
    }
    
    guard let reference = FileTranslatorPool.reference(identifier: queryableIdentifier) else {
      print("ITEM \(queryableIdentifier.rawValue) REQUESTED with ERROR")

      throw NSError.fileProviderErrorForNonExistentItem(withIdentifier: queryableIdentifier)
    }
    
    return FileProviderItem(reference: reference)

  }
  
  override func urlForItem(withPersistentIdentifier identifier: NSFileProviderItemIdentifier) -> URL? {
    let blinkItemFromId = BlinkItemIdentifier(identifier)
    debugPrint("blinkItemFromId.url")
    debugPrint(blinkItemFromId.url)
    return blinkItemFromId.url
  }
  
  // MARK: - Actions
  
  /* TODO: implement the actions for items here
   each of the actions follows the same pattern:
   - make a note of the change in the local model
   - schedule a server request as a background task to inform the server of the change
   - call the completion block with the modified item in its post-modification state
   */
  
  // url => file:///Users/xxxx/Library/Developer/CoreSimulator/Devices/212A70E4-CE48-48C7-8A19-32357CE9B3BD/data/Containers/Shared/AppGroup/658A68A7-43BE-4C48-8586-C7029B0DCD9A/File%20Provider%20Storage/bG9jYWw6L3Vzcg==/L2xvY2Fs/filename
  
  // https://developer.apple.com/documentation/fileprovider/nsfileproviderextension/1623479-persistentidentifierforitematurl?language=objc
  //  define a static mapping between URLs and their persistent identifiers.
  //  A document's identifier should remain constant over time; it should not change when the document is edited, moved, or rename
  //  TODO: Always return nil if the _URL is not inside in the directory referred to by the NSFileProviderManager object's documentStorageURL_ property.
  override func persistentIdentifierForItem(at url: URL) -> NSFileProviderItemIdentifier? {
    let blinkItem = BlinkItemIdentifier(url: url)
    return blinkItem.itemIdentifier
  }
    
  override func providePlaceholder(at url: URL, completionHandler: @escaping (Error?) -> Void) {
    
    print("providePlaceholder at \(url)")

    //A.1. Get the document’s persistent identifier by calling persistentIdentifierForItemAtURL:, and pass in the value of the url parameter.
    makeLocalDirectoryFrom(url: url)

    //A Look Up the Document's File Provider Item
    guard let identifier = persistentIdentifierForItem(at: url) else {
      completionHandler(NSFileProviderError(.noSuchItem))
      return
    }
    print("identifier \(identifier)")

    do {
      
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
    
    print("startProvidingItem  at \(url)")
    
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
    
//    guard let identifier = persistentIdentifierForItem(at: url) else {
//      completionHandler(NSFileProviderError(.noSuchItem))
//      return
//    }
    let blinkIdentifier = BlinkItemIdentifier(url: url)
    //let filename = url.lastPathComponent
    
    // SRC                --> DEST
    // remote             --> local
    // FileTranslatorPool --> Local()
    
    // local
    let destTranslator = Local().cloneWalkTo(url.deletingLastPathComponent().path)
    
    // 2 remote - From the identifier, we get the translator, and we can walk to the remote file
    let srcTranslator = FileTranslatorPool.translator(for: blinkIdentifier.encodedRootPath)
    srcTranslator.flatMap { $0.cloneWalkTo(blinkIdentifier.path) }
      .flatMap { fileTranslator in
        return destTranslator.flatMap { $0.copy(from: [fileTranslator]) }
      }.sink(receiveCompletion: { completion in
        print(completion)
        completionHandler(nil)
      }, receiveValue: { _ in }).store(in: &cancellableBag)
    // 3 - On local, the path is already the URL, so we walk to the local file path to provide there.
    // 4 - Copy from one to the other, and call the completionHandler once done.
    
    // file://
  }
  
  override func itemChanged(at url: URL) {
    print("itemChanged ITEM at \(url)")

    // Called at some point after the file has changed; the provider may then trigger an upload
    
    /* TODO:
     - mark file at <url> as needing an update in the model
     - if there are existing NSURLSessionTasks uploading this file, cancel them
     - create a fresh background NSURLSessionTask and schedule it to upload the current modifications
     - register the NSURLSessionTask with NSFileProviderManager to provide progress updates
     */
  }
  
  override func stopProvidingItem(at url: URL) {
    print("stopProvidingItem ITEM at \(url)")
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
  
//  // https://discussions.apple.com/thread/251188856
//  func importDocument2(at fileURL: URL, toParentItemIdentifier parentItemIdentifier: NSFileProviderItemIdentifier, completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) {
//
//    var error: NSError?
//    print("importDocument ITEM at \(fileURL)")
//
//    print("fileURL")
//    print(fileURL)
//
//    print("parentItemIdentifier")
//    print(parentItemIdentifier)
//
//    let filename = fileURL.lastPathComponent
//    let blinkIdentifier = BlinkItemIdentifier(parentItemIdentifier: parentItemIdentifier, filename: filename)
//
//    let remotepathWithFileName = blinkIdentifier.path
//    let remotePath = (remotepathWithFileName as NSString).deletingLastPathComponent
//
//    _ = fileURL.startAccessingSecurityScopedResource()
//
//    // TODO: Guard against directories being copied?
//
//    NSFileCoordinator()
//      .coordinate(readingItemAt: fileURL, options: .withoutChanges, error: &error) { (url) in
//
//        // OPTION 1.a create local copy of remote src
//        // let manager = NSFileProviderManager.default
//        // let pathcomponents = remotepathWithFileName
//        // let itemUrl = manager.documentStorageURL.appendingPathComponent(pathcomponents)
//
//
//        // OPTION 1.b create local copy of remote src
//        let itemUrl = blinkIdentifier.url
//
//        // Do I need to do this - we actually don't know if the corresponding local file exists, but this implicitly creates the file
//
//        // OPTION 2. Use BlinkItemIdentifier with url..
//        // will error due to url not in Blink URL format
////        let item = BlinkItemIdentifier(url: url)
////        let itemUrl = item.url
//
//        // Option 1.I
////        providePlaceholder(at: itemUrl) { error in
////          // do something
////        }
//
//        // Option 1.II
//        do {
//          try fileManager.createDirectory(
//            at: itemUrl,
//            withIntermediateDirectories: true,
//            attributes: nil
//          )
//
//        } catch let error {
//          debugPrint(error)
////          completionHandler(nil, error)
////          return
//        }
//
//        // move the item from Unknown Remote to Blink_Local()
//        _ = moveFile(url.path, toPath: itemUrl.path)
//
//        // SRC      --> DEST
//        // local    --> remote
//        // Local()  --> FileTranslatorPool()
//
//        // copy item from Blink_Local() to Blink Remote
//        let encodedRootPath = blinkIdentifier.encodedRootPath
//        print("encodedRootPath \(encodedRootPath)")
//        print("remotepathWithFileName \(remotepathWithFileName)")
//        print("remotePath \(remotePath)")
//
//        let srcTranslator = Local().cloneWalkTo(itemUrl.deletingLastPathComponent().path)
//
//        var attributes: FileAttributes!
//
//        do {
//          attributes = try fileManager.attributesOfItem(atPath: itemUrl.path)
//          attributes[.name] = filename
//        } catch let error {
//          completionHandler(nil, error)
//          return
//        }
//
//        let blinkRef = BlinkItemReference(parentItemIdentifier: parentItemIdentifier, attributes: attributes)
//
//
//        let destTranslator = FileTranslatorPool.translator(for: blinkIdentifier.encodedRootPath)
//        destTranslator.flatMap { $0.cloneWalkTo(remotePath) }
//          .flatMap { fileTranslator in
//
//            return srcTranslator.flatMap { $0.copy(from: [fileTranslator]) }
//          }.sink(
//            receiveCompletion: { completionAttribute in
//                print("completionAttribute \(completionAttribute) ")
//
//              if case let .failure(error) = completionAttribute {
//                print("Copyfailed. \(error)")
//
//                completionHandler(nil, error)
//                return
//              }
//
//              // create NSFileProviderItem - translator does not return a BlinkAttribute
//
//             print("DONE: translator does not return a BlinkAttribute ")
//              let item = FileProviderItem(reference: blinkRef)
//              completionHandler(item, nil)
//
//            }, receiveValue: { value in
//                // progress...
//              print("@@@ receiving Value in value \(value)")
//
//            })
//          .store(in: &cancellableBag)
//
//
//
//        // 3 - On local, the path is already the URL, so we walk to the local file path to provide there.
//
//        // 4 - Copy from one to the other, and call the completionHandler once done.
//
//    }
//
//    fileURL.stopAccessingSecurityScopedResource()
//
//    // 1 - From NSFileProviderItemIdentifier we get the parent item and filename ..
//
//  }
//
  
  override func importDocument(at fileURL: URL, toParentItemIdentifier parentItemIdentifier: NSFileProviderItemIdentifier, completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) {
    
    var myerror: NSError?
    var error: NSError?
    
    let localBlinkIdentifier = BlinkItemIdentifier(parentItemIdentifier: parentItemIdentifier, filename: fileURL.lastPathComponent)
    let localParentPath = localBlinkIdentifier.url.deletingLastPathComponent().path
    
    _ = fileURL.startAccessingSecurityScopedResource()
    
    NSFileCoordinator()
      .coordinate(readingItemAt: fileURL, options: .withoutChanges, error: &myerror) { (url) in
        
        do {
          try moveFileWhileCreatingDirectory(url, to: localParentPath)
        } catch let localerror {
          error = localerror as NSError
        }
    
      }
    
    fileURL.stopAccessingSecurityScopedResource()
    
    if let error = error {
      completionHandler(nil, error)
      return
    }
    
    if let myerror = myerror {
      completionHandler(nil, myerror)
      return
    }
    
    // 1. Translator for local target path
    let localFile = (localParentPath as NSString).appendingPathComponent(fileURL.lastPathComponent)
    let srcTranslator = Local().cloneWalkTo(localFile)
    
    
    // 2. translator for remote target path
    let remoteParentIdentifier = BlinkItemIdentifier(parentItemIdentifier)
    let destTranslator = FileTranslatorPool.translator(for: remoteParentIdentifier.encodedRootPath)
    
    var attributes: FileAttributes!
    do {
      attributes = try fileManager.attributesOfItem(atPath: localFile)
      attributes[.name] = localFile
    } catch let error {
      completionHandler(nil, error)
      return
    }
    
    
    destTranslator.flatMap { $0.cloneWalkTo(remoteParentIdentifier.path)}
      .flatMap { remotePathTranslator in
        
        return srcTranslator.flatMap{ localFileTranslator in
          
          remotePathTranslator.copy(from: [localFileTranslator])
        }
      }.sink  { completion in
        
        if case let .failure(error) = completion {
          print("Copyfailed. \(error)")
          completionHandler(nil, error)
          return
        }
        
        
        let blinkItemReference = BlinkItemReference(parentItemIdentifier: remoteParentIdentifier.itemIdentifier, attributes: attributes)
        let parentId = blinkItemReference.parentReference
        let item = FileProviderItem(reference: blinkItemReference)
        
        completionHandler(item, nil)
        
        
      } receiveValue: { _ in
        
        
      }.store(in: &cancellableBag)
    
  }
  
  override func createDirectory(withName directoryName: String,
  inParentItemIdentifier parentItemIdentifier: NSFileProviderItemIdentifier,
  completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) {
    
    // TODO:
    
    // 1. Check for collisions
    
    // 2. Create a directory (locally?)
  }
  
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
  
  // MARK: - Private
  
  private func makeLocalDirectoryFrom(url: URL) {
    let localDirectory = url.deletingLastPathComponent()
    print("directory \(localDirectory)")

    do {

      try fileManager.createDirectory(
        at: localDirectory,
        withIntermediateDirectories: true,
        attributes: nil
      )

    } catch let error {
      debugPrint(error)
    }
  }

  func copyFile(_ atPath: String, toPath: String) -> Error? {
      
      var errorResult: Error?
      
      if !fileManager.fileExists(atPath: atPath) { return NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo:[:]) }
      
      do {
          try fileManager.removeItem(atPath: toPath)
      } catch let error {
          print("error: \(error)")
      }
      do {
          try fileManager.copyItem(atPath: atPath, toPath: toPath)
      } catch let error {
          errorResult = error
      }
      
      return errorResult
  }
  
  func moveFileWhileCreatingDirectory(_ fileURL: URL, to targetPath: String) throws {
    
    var isDirectory: ObjCBool = false
    
     if !fileManager.fileExists(atPath: targetPath, isDirectory:&isDirectory) {
         
      try fileManager.createDirectory(atPath: targetPath, withIntermediateDirectories: true, attributes: nil)
         // Check to see if file exists, move file, error handling
     }
    
    let filename = fileURL.lastPathComponent
    let newFilePath  = (targetPath as NSString).appendingPathComponent(filename)
    if fileManager.fileExists(atPath: newFilePath) {
      try fileManager.removeItem(atPath: newFilePath)
    }
    
    try fileManager.moveItem(atPath: fileURL.path, toPath: newFilePath)

    
    
  }
  
  func moveFile(_ atPath: String, toPath: String) -> Error? {
      
      var errorResult: Error?
      
      if atPath == toPath { return nil }
    
      if fileManager.fileExists(atPath: atPath) {
        //return NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo:[:])
        
        do {
            try fileManager.removeItem(atPath: toPath)
        } catch let error {
            print("error: \(error)")
          return error
        }

      }
      
//      do {
//          try fileManager.removeItem(atPath: toPath)
//      } catch let error {
//          print("error: \(error)")
//        return error
//      }
    
      do {
          try fileManager.moveItem(atPath: atPath, toPath: toPath)
      } catch let error {
          errorResult = error
        return error
      }
      
      return errorResult
  }
  
  
  func deleteFile(_ atPath: String) -> Error? {
      
      var errorResult: Error?
      
      do {
          try fileManager.removeItem(atPath: atPath)
      } catch let error {
          errorResult = error
      }
      
      return errorResult
  }
  
  func fileExists(atPath: String) -> Bool {
      return fileManager.fileExists(atPath: atPath)
  }
  
}
