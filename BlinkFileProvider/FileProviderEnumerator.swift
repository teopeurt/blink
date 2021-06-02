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

import BlinkFiles
import FileProvider
import Combine


class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {
  let identifier: NSFileProviderItemIdentifier
  let translator: AnyPublisher<Translator, Error>
  var cancellableBag: Set<AnyCancellable> = []
  //var translatorPub: AnyPublisher<Translator, Error>

  init(enumeratedItemIdentifier: NSFileProviderItemIdentifier,
       domain: NSFileProviderDomain) {
    
    // domainIdentifier <encodedRootIdentifier>
    // TODO It would be nice if the Reference could take care of the details about
    // what the structure is, and here we could just specify what we need.
    // TODO Or maybe wrap that into a BlinkItemIdentifier
    // Two cases, with or without a path below <encodedRootIdentifier>
    // enumeratedItemIdentifier <encodedRootIdentifier>/path/to/wherever
    if enumeratedItemIdentifier == .rootContainer {
      self.identifier = NSFileProviderItemIdentifier(rawValue: domain.identifier.rawValue)
    } else {
      self.identifier = enumeratedItemIdentifier
    }
    var path = self.identifier.rawValue
    path.removeFirst(domain.identifier.rawValue.count)
    // The path is always relative to the encoded root. If we start with a slash, we remove it
    // as otherwise the cloneWalk will go to the root of the filesystem.
    if path.starts(with: "/") {
      path.removeFirst()
    }
    self.translator = FileTranslatorPool.translator(for: domain.identifier.rawValue)
      .flatMap { t -> AnyPublisher<Translator, Error> in
        if !path.isEmpty {
          return t.cloneWalkTo(path)
        } else {
          return Just(t.clone()).mapError {$0 as Error}.eraseToAnyPublisher()
        }
      }.eraseToAnyPublisher()

    super.init()
  }
  
  func invalidate() {
    // TODO: perform invalidation of server connection if necessary
  }
  
  func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
    /* TODO:
     - inspect the page to determine whether this is an initial or a follow-up request
     
     If this is an enumerator for a directory, the root container or all directories:
     - perform a server request to fetch directory contents
     If this is an enumerator for the active set:
     - perform a server request to update your local database
     - fetch the active set from your local database
     
     - inform the observer about the items returned by the server (possibly multiple times)
     - inform the observer that you are finished with this page
     */
    
    translator.print("Translator").flatMap { $0.directoryFilesAndAttributes()
    }.sink(receiveCompletion: { completion in
      switch completion {
      case .failure(let error):
        print("ERROR \(error.localizedDescription)")
      default:
        break
      }
    }, receiveValue: { attrs in
      let items = attrs.map { blinkAttr -> FileProviderItem in
        let ref = BlinkItemReference(parentItemIdentifier: self.identifier,
                                     attributes: blinkAttr)
        // Store the reference in the internal DB for later usage.
        FileTranslatorPool.store(reference: ref)
        return FileProviderItem(reference: ref)
      }
      observer.didEnumerate(items)
      observer.finishEnumerating(upTo: nil)
    }).store(in: &cancellableBag)
  }

  func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
    /* TODO:
     - query the server for updates since the passed-in sync anchor
     
     If this is an enumerator for the active set:
     - note the changes in your local database
     
     - inform the observer about item deletions and updates (modifications + insertions)
     - inform the observer when you have finished enumerating up to a subsequent sync anchor
     */
  }
  
}
