//
//  StreamingStringMatcher.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 6/16/23.
//
//  Helper class to scan a serial string stream for a substring match using a naive algorithm.
//

import Foundation

extension Util {
    class StreamingStringMatcher {
        private var _str = ""
        private let _target: String
        private var _charactersProcessed = 0

        init(lookingFor substring: String) {
            assert(substring.count >= 1)
            _target = substring
        }

        /// Resets the matcher state by purging all accumulated data.
        public func reset() {
            _str = ""
            _charactersProcessed = 0
        }

        /// Number of characters processed so far since initialization or last reset.
        public var charactersProcessed: Int {
            return _charactersProcessed
        }

        /// Ingests and appends string data and checks for a match in the current accumulated buffer.
        /// - Parameter afterAppending: String to accumulate before checking for match within all
        /// existing content.
        /// - Returns: True if an occurrence of the target substring exists. The target substring is
        /// then removed. Note that this means if the target string exists multiple times, subsequent
        /// calls will return true until all of the substrings are accounted for.
        public func matchExists(afterAppending str: String) -> Bool {
            _str += str
            _charactersProcessed += str.count

            // Look for possible substring match by locating the first character of the target string
            // inside the accumulated string
            while let idx = _str.firstIndex(of: _target[str.startIndex]) {
                let idxVal: Int = _str.distance(from: _str.startIndex, to: idx)

                // Have we accumulated enough characters for the target to possibly exist here? If so,
                // check for match.
                let targetEndIdxVal = idxVal + _target.count
                if targetEndIdxVal <= _str.count {
                    let targetEndIdx = _str.index(idx, offsetBy: _target.count)
                    if _str[idx..<targetEndIdx] == _target {
                        // Match found. Remove everything up to end of target substring.
                        _str.removeSubrange(..<targetEndIdx)
                        return true
                    }

                    // No match. Remove only up to and including the first character we started
                    // checking from because target string may partially exist after it.
                    _str.removeSubrange(...idx)

                    // Continue the loop to check again
                } else {
                    // Insufficient characters to check, no match yet
                    return false
                }
            }

            // We can discard everything because the first character hasn't even been found yet
            _str = ""
            return false
        }
    }
}
