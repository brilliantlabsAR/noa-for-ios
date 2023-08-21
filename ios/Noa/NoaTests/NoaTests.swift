//
//  NoaTests.swift
//  NoaTests
//
//  Created by Bart Trzynadlowski on 5/1/23.
//

import XCTest
@testable import Noa

final class NoaTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testSerialStringMatcher() throws {
        let matcher = Util.StreamingStringMatcher(lookingFor: "foobar")

        XCTAssert(matcher.matchExists(afterAppending: "") == false)
        XCTAssert(matcher.matchExists(afterAppending: "foobar") == true)

        matcher.reset()

        XCTAssert(matcher.matchExists(afterAppending: "fooba") == false)    // fooba
        XCTAssert(matcher.matchExists(afterAppending: "foob") == false)     // foobafoob
        XCTAssert(matcher.matchExists(afterAppending: "artichoke") == true) // foobafoobartichoke

        matcher.reset()

        XCTAssert(matcher.matchExists(afterAppending: "this is a string") == false)
        XCTAssert(matcher.matchExists(afterAppending: "and foobar is embedded within") == true)

        matcher.reset()

        XCTAssert(matcher.matchExists(afterAppending: "this is a string") == false)
        XCTAssert(matcher.matchExists(afterAppending: "foobarfoobar") == true)  // match first foobar
        XCTAssert(matcher.matchExists(afterAppending: "blah") == true)          // match second foobar that we inserted earlier
        XCTAssert(matcher.matchExists(afterAppending: "blah") == false)         // no more foobar left in buffer to match
        XCTAssert(matcher.matchExists(afterAppending: "foobar") == true)

        matcher.reset()

        XCTAssert(matcher.matchExists(afterAppending: "this is a string") == false)
        XCTAssert(matcher.matchExists(afterAppending: "foobar--foobar") == true)    // match first foobar
        XCTAssert(matcher.matchExists(afterAppending: "blah") == true)              // match second foobar that we inserted earlier
        XCTAssert(matcher.matchExists(afterAppending: "blah") == false)             // no more foobar left in buffer to match

        matcher.reset()

        XCTAssert(matcher.matchExists(afterAppending: "fffffffffff") == false)
        XCTAssert(matcher.matchExists(afterAppending: "fffffffffff") == false)
        XCTAssert(matcher.matchExists(afterAppending: "ffffoobarfffffoobarffff") == true)   // first foobar
        XCTAssert(matcher.matchExists(afterAppending: "fffffffff") == true)                 // second foobar from above
        XCTAssert(matcher.matchExists(afterAppending: "fffff") == false)
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
