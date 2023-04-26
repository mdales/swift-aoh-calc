

// @pytest.mark.parametrize("input,expected", [
// 	([], []),
// 	(["11"], [1100, 1101, 1102, 1103, 1104, 1105, 1106]),
// 	(["11.1"], [1100, 1101]),
// 	(["11.1.1"], [1100, 1101]),
// 	([  "7", "7.1", "7.2", "9.8.1", "9.8.2", "9.8.3", "9.8.4", "9.8.5", "9.8.6",
// 		"11.1.1", "11.1.2", "13", "13.1", "13.2", "13.3", "13.4", "13.5", "15",
// 		"15.1", "15.2", "15.3", "15.4", "15.5", "15.6", "15.7", "15.8", "15.9",
// 		"15.10", "15.11", "15.12", "15.13", "16", "18"],
// 		[900, 908, 1100, 1101]), # unmappables
// 	])
// def test_jung_translator(input, expected):
// 	result = translator.toJung(input)
// 	result.sort()
// 	assert expected == result


import XCTest
@testable import persistence_calculator

final class jungTests: XCTestCase {

	func testEmptyList() throws {
		let res = try convertIUCNToJung(Set<String>([]))
		XCTAssertEqual(res.count, 0, "Expected no result")
	}

	func testTopLevel() throws {
		let res = try convertIUCNToJung(Set(["11"]))
		XCTAssertEqual(res, Set([1100, 1101, 1102, 1103, 1104, 1105, 1106]), "Expected all sub levels")
	}

	func testSecondLevel() throws {
		let res = try convertIUCNToJung(Set(["11.1"]))
		XCTAssertEqual(res, Set([1100, 1101]), "Expected all sub levels")
	}

	func testThirdLevel() throws {
		let res = try convertIUCNToJung(Set(["11.1.1"]))
		XCTAssertEqual(res, Set([1100, 1101]), "Expected all sub levels")
	}

	func testUnmappable() throws {
		let res = try convertIUCNToJung(Set(["7", "7.1", "7.2", "9.8.1", "9.8.2", "9.8.3", "9.8.4", "9.8.5", "9.8.6", "11.1.1", "11.1.2", "13", "13.1", "13.2", "13.3", "13.4", "13.5", "15", "15.1", "15.2", "15.3", "15.4", "15.5", "15.6", "15.7", "15.8", "15.9", "15.10", "15.11", "15.12", "15.13", "16", "18"]))
		XCTAssertEqual(res, Set([900, 908, 1100, 1101]), "Expected all sub levels")
	}

	func testGarbageIn() throws {
		XCTAssertThrowsError(try convertIUCNToJung(Set(["hello"]))) { error in
			XCTAssertEqual(error as? ConversionError, .CodeContainsNonNumbericParts)
		}
	}

	func testEmptyStringIn() throws {
		XCTAssertThrowsError(try convertIUCNToJung(Set([""]))) { error in
			XCTAssertEqual(error as? ConversionError, .CodeEmpty)
		}
	}
}
