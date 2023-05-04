import Foundation

import SQLite

enum IUCNBatchError: Error {
	case NoMatchFound
	case ElevationRangeError(Int, Int)
	case BadSuitability(String)
	case BadSeason(String)
}

enum HabitatSutiability: String {
	case Suitable
	case Marginal
	case Unknown
}

enum HabitatSeason: String {
	case Resident = "Resident"
	case Unknown = "Seasonal Occurrence Unknown"
	case Breeding = "Breeding Season"
	case NonBreeding = "Non-Breeding Season"
	case Passage = "Passage"
}

struct Habitat: Hashable {
	let code: String
	let majorImportance: Bool
	let season: HabitatSeason
	let suitability: HabitatSutiability
}

struct IUCNBatch {

	let db: Connection

	public init(_ path: String) throws {
		self.db = try Connection(path)
	}

	public func getHabitatForSpecies(
		_ species_id: UInt,
		seasonalityFilter: [HabitatSeason] = [],
		suitabilityFilter: [HabitatSutiability] = []
	) throws -> Set<Habitat> {
		let m2m = Table("taxonomy_habitat_m2m")
		let m2m_taxonomy = Expression<Int>("taxonomy")
		let m2m_habitat = Expression<Int>("habitat")
		let m2m_season = Expression<String>("season")
		let m2m_suitability = Expression<String>("suitability")
		let m2m_majorImportance = Expression<Bool>("majorImportance")

		let habitat = Table("habitat")
		let habitat_id = Expression<Int>("id")
		let habitat_code = Expression<String>("code")

		var query = habitat.join(m2m, on: habitat_id == m2m[m2m_habitat]).filter(m2m_taxonomy == Int(species_id))
		if seasonalityFilter.count > 1 {
			var term = m2m_season == seasonalityFilter[0].rawValue
			for season in seasonalityFilter[1...] {
				term = term || (m2m_season == season.rawValue)
			}
			query = query.filter(term)
		}
		if suitabilityFilter.count > 1 {
			var term = m2m_suitability == suitabilityFilter[0].rawValue
			for suitability in suitabilityFilter[1...] {
				term = term || (m2m_suitability == suitability.rawValue)
			}
			query = query.filter(term)
		}

		let results = try db.prepare(query)
		let habitats: [Habitat] = try results.map {
			guard let suitability = HabitatSutiability(rawValue: $0[m2m_suitability]) else {
				throw IUCNBatchError.BadSuitability($0[m2m_suitability])
			}
			guard let season = HabitatSeason(rawValue: $0[m2m_season]) else {
				throw IUCNBatchError.BadSeason($0[m2m_season])
			}
			return Habitat(
				code: $0[habitat_code],
				majorImportance: $0[m2m_majorImportance],
				season: season,
				suitability: suitability
			)
		}
		return Set(habitats)
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