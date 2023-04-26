import Foundation

import SQLite

struct IUCNBatch {

	let db: Connection

	public init(_ path: String) throws {
		self.db = try Connection(path)
	}

	public func getHabitatForSpecies(_ species_id: UInt) throws -> Set<String> {
		let m2m = Table("taxonomy_to_habitat_m2m")
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
}