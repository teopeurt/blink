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

import Foundation
import FileProvider
import MobileCoreServices

import BlinkFiles

struct BlinkItemIdentifier {
  let path: String
  let encodedRootPath: String
  
  // <encodedRootPath>/path/to, name = filename. -> <encodedRootPath>/path/to/filename
  init(parentItemIdentifier: NSFileProviderItemIdentifier, filename: String) {
    self.encodedRootPath = (parentItemIdentifier.rawValue as NSString).pathComponents[0]
    var path = (parentItemIdentifier.rawValue)
    path.removeFirst(encodedRootPath.count)
    if path.isEmpty {
      path = "/"
    }
    
    self.path = (path as NSString).appendingPathComponent(filename)
  }
  
  // <encodedRootPath>/path/to/filename
  init(_ identifier: NSFileProviderItemIdentifier) {
    self.encodedRootPath = (identifier.rawValue as NSString).pathComponents[0]
    var path = (identifier.rawValue)
    path.removeFirst(encodedRootPath.count)
    if path.isEmpty {
      path = "/"
    }
    self.path = path
  }
  
  init(url: URL) {
    let manager = NSFileProviderManager.default
    let containerPath = manager.documentStorageURL.absoluteString
    
    // file://<containerPath>/<encodedRootPath>/<encodedPath>/filename
    var path = url.absoluteString
    path.removeFirst(containerPath.count)
    
    // <encodedRootPath>/<encodedPath>/filename
    
    let components = path.split(separator: "/")
    let filename = components[2]
    
    let encodedPath = String(components[1])
    let dataPath = Data(base64Encoded: encodedPath)
    let decodedString = String(data: dataPath!, encoding: .utf8)!
    
    
    self.path = decodedString
    self.encodedRootPath = String(components[0])
    
  }
  
  // <encodedRootPath>/<encodedPath>
  // this gives you the local url with application root container prefix
  // file:///Users/xxxx/Library/Developer/CoreSimulator/Devices/212A70E4-CE48-48C7-8A19-32357CE9B3BD/data/Containers/Shared/AppGroup/658A68A7-43BE-4C48-8586-C7029B0DCD9A/File%20Provider%20Storage/bG9jYWw6L3Vzcg==/L2xvY2Fs/local
  // ??
  var url: URL {
    let data = self.path.data(using: .utf8)
    let encodedPath = data!.base64EncodedString()
    
    // TODO This should probably be relative to the application root container
     return URL(fileURLWithPath:"\(encodedRootPath)/\(encodedPath)/\(filename)")
  }
  
  var alternativeUrl: URL {
    let data = self.path.data(using: .utf8)
    let encodedPath = data!.base64EncodedString()
    
    let manager = NSFileProviderManager.default
    let pathcomponents = "\(encodedRootPath)/\(encodedPath)/\(filename)"
    let itemDirectory = manager.documentStorageURL.appendingPathComponent(pathcomponents)
    return itemDirectory
  }
  
  var filename: String {
    return (path as NSString).lastPathComponent
  }
  
  var itemIdentifier: NSFileProviderItemIdentifier {
      return NSFileProviderItemIdentifier(
        rawValue: "\(encodedRootPath)\(path)"
      )
  }
  
  var parentReference: NSFileProviderItemIdentifier {
    let parentPath = (path as NSString).deletingLastPathComponent
    if parentPath == "/" {
      return .rootContainer
    } else {
      return NSFileProviderItemIdentifier(
        rawValue: "\(encodedRootPath)\(parentPath)"
      )
    }
  }
}

// Goal is to bridge the Identifier to the underlying BlinkFiles system, and to offer
// Representations the item.
struct BlinkItemReference {
  //private let encodedRootPath: String
  // TODO We could also work with a  URL that is not the URL representation,
  // but the URL Identifier. This way we would not have to transform from NSString all the time.
  private let identifier: BlinkItemIdentifier
//  private let path: String
//  private let encodedRootPath: String
  //private let urlRepresentation: URL
  var attributes: BlinkFiles.FileAttributes
  
  // No Blink File?
//  private init(urlRepresentation: URL) {
//    self.urlRepresentation = urlRepresentation
//  }
//
//  private init(urlRepresentation: URL, attributes: BlinkFiles.FileAttributes){
//    self.init(urlRepresentation: urlRepresentation)
//    self.attributes = attributes
//  }
  
  // MARK: - Enumerator Entry Point:
  // Requires attributes. If you only have the Identifier, you need to go to the DB.
  // Identifier format <encodedRootPath>/path/to/more/components/filename
  init(parentItemIdentifier: NSFileProviderItemIdentifier,
       attributes: BlinkFiles.FileAttributes) {
    self.attributes = attributes

    let filename = attributes[.name] as! String

    self.identifier = BlinkItemIdentifier(parentItemIdentifier: parentItemIdentifier, filename: filename)
  }
  
  // MARK: - DB Query Entry Point:
  // TODO The URL needs to be below the container.
  // https://developer.apple.com/documentation/fileprovider/nsfileproviderextension/1623481-urlforitemwithpersistentidentifi?language=objc
  // https://developer.apple.com/documentation/fileprovider/nsfileprovidermanager/2879513-documentstorageurl?language=objc

  var url: URL {
    return identifier.url
  }
  
  var itemIdentifier: NSFileProviderItemIdentifier {
    return identifier.itemIdentifier
  }

  var isDirectory: Bool {
    return (attributes[.type] as? FileAttributeType) == .typeDirectory
  }

  var filename: String {
    return identifier.filename
  }

  var typeIdentifier: String {
    guard let type = attributes[.type] as? FileAttributeType else {
      return ""
    }
    if type == .typeDirectory {
      return kUTTypeFolder as String
    }

    let pathExtension = (filename as NSString).pathExtension
    let unmanaged = UTTypeCreatePreferredIdentifierForTag(
      kUTTagClassFilenameExtension,
      pathExtension as CFString,
      nil
    )
    let retained = unmanaged?.takeRetainedValue()

    return (retained as String?) ?? ""
  }

  var parentReference: NSFileProviderItemIdentifier {
    return identifier.parentReference
  }
}
