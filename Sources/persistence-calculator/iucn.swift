import Foundation

import SQLite

enum IUCNBatchError: Error {
	case NoMatchFound
	case ElevationRangeError(Int, Int)
}

struct IUCNBatch {

	let db: Connection

	public init(_ path: String) throws {
		self.db = try Connection(path)
	}

	public func getHabitatForSpecies(_ species_id: UInt) throws -> Set<String> {
		let m2m = Table("taxonomy_habitat_m2m")
		let m2m_taxonomy = Expression<Int>("taxonomy")
		let m2m_habitat = Expression<Int>("habitat")

		let habitat = Table("habitat")
		let habitat_id = Expression<Int>("id")
		let habitat_code = Expression<String>("code")

		let query = habitat.join(m2m, on: habitat_id == m2m[m2m_habitat]).filter(m2m_taxonomy == Int(species_id))
		let results = try db.prepare(query)
		let codes: [String] = results.map { res in
			res[habitat_code]
		}
		return Set(codes)
	}

	public func getElevationRangeForSpecies(_ species_id: UInt) throws -> ClosedRange<Int> {
		let taxonomy = Table("taxonomy")
		let idcol = Expression<Int>("id")
		let elevation_lower = Expression<Int>("elevationLower")
		let elevation_upper = Expression<Int>("elevationUpper")

		guard let result = try db.pluck(taxonomy.filter(idcol == Int(species_id))) else {
			throw IUCNBatchError.NoMatchFound
		}
		guard result[elevation_lower] < result[elevation_upper] else {
			throw IUCNBatchError.ElevationRangeError(result[elevation_lower], result[elevation_upper])
		}
		return result[elevation_lower]...result[elevation_upper]
	}
}