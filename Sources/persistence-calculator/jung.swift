
// The IUCN codes can have up to three levels of specificity. E.g.:
// 9     = Marine Neritic
// 9.8   = Marine Neritic - Coral Reef
// 9.8.5 = Marine Neritic - Coral Reef - Inter-reef substrate
//
// The Jung map uses the same scheme, but uses a shifted decimal encoding:
// 9  -> 900
// 9.8 -> 908
// and there is no level three. Each pixel in the jung map will have just one
// code applied to it.
//
// This function coverts then the codes we get from the IUCN range data
// in the former to something we can search for in the jung map in the later.
// Thus, we have the following rules:
//
//  * Level three codes are coverted to the parent level two code:
//    e.g., 9.8.5 becomes 9.8
//  * Level two codes are encoded as both the specific code and the
//    parent:
//    e.g., 9.8 -> [9, 9.8]
//  * Level one codes are encoded as both self and all childern:
//    e.g., 9 -> [9, 9.1, 9.2, ..., 9.10]
//
// Finally, as an optimisation, we know that there is a limited number
// of codes used in the actual Jung map versus the full IUCN set, so to
// remove un-necessary work we remove those before returning.

let validJungCodes: Set<Int16> = [
	100, 101, 102, 103, 104, 105, 106, 107, 108, 109,
	200, 201, 202,
	300, 301, 302, 303, 304, 305, 306, 307, 308,
	400, 401, 402, 403, 404, 405, 406, 407,
	500, 501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 511, 512, 513, 514, 515, 516, 517, 518,
	600,
	800, 801, 802, 803,
	900, 901, 902, 903, 904, 905, 906, 907, 908, 909, 910,
	1000, 1001, 1002, 1003, 1004,
	1100, 1101, 1102, 1103, 1104, 1105, 1106,
	1200, 1201, 1202, 1203, 1204, 1205, 1206, 1207,
	1400, 1401, 1402, 1403, 1404, 1405, 1406,
	1700,
]

enum ConversionError: Error {
	case CodeContainsNonNumbericParts
	case CodeEmpty
}

public func convertIUCNToJung(_ iucnCode: Set<String>) throws -> Set<Int16> {
	return try Set(iucnCode.flatMap { code in
		let parts = try code.split(separator: ".").map {
			if let val = Int16($0) {
				return val
			} else {
				throw ConversionError.CodeContainsNonNumbericParts
			}
		}
		guard parts.count > 0 else {
			throw ConversionError.CodeEmpty
		}
		let majorcode = Int16(parts[0] * 100)
		var codes: Set = [majorcode]
		if parts.count > 1 {
			codes.insert(majorcode + parts[1])
		} else {
			// The highest secondry level code I've seen is 18, so here we just add
			// all codes up to that, and then let the last filter take out the
			// invalid ones
			codes = codes.union(Set((0..<20).map { majorcode + $0 }))
		}
		return codes.intersection(validJungCodes)
	})
}