import Foundation

import ArgumentParser
import GeoPackage
import LibTIFF
import SQLite
import Yirgacheffe

enum Seasonality: String, EnumerableFlag, ExpressibleByArgument {
    case breeding, nonbreeding, resident
}

struct ExperimentConfig: Codable {
    let translator: String
    let habitat: String
    let elevation: String
    let area: String
    let range: String
    let iucnBatch: String
}

struct Config: Codable {
    let experiments: [String:ExperimentConfig]
}

enum AoHCalcError: Error {
    case ExperimentNotFound(String)
    case TooMuchData
}

@main
struct aohcalc: ParsableCommand {
    @Argument(help: "The IUCN species ID")
    var taxid: UInt

    @Argument(help: "Which season to calculate for (breeding, nonbreeding, or resident)")
    var seasonality: Seasonality

    @Argument(help: "Name of experiment group from configuration json")
    var experiment: String

    @Option(help: "Path of configuration json")
    var configPath = "config.json"

    @Option(help: "Directory where area geotiffs should be stored")
    var resultsPath: String? = nil

    func calculator(
        geometry: GeometryLayer,
        area: UniformAreaLayer<Double>,
        elevation: GeoTIFFReadLayer<Int16>,
        habitat: GeoTIFFReadLayer<UInt8>
    ) throws -> Double {
        let layers: [any Yirgacheffe.Layer] = [geometry, area, elevation, habitat]
        let intersection = try calculateIntersection(layers: layers)
        let targetted_geometry = try geometry.setAreaOfInterest(area: intersection) as! GeometryLayer
        let targetted_area = try area.setAreaOfInterest(area: intersection) as! UniformAreaLayer<Double>
        let targetted_elevation = try elevation.setAreaOfInterest(area: intersection) as! GeoTIFFReadLayer<Int16>
        let targetted_habitat = try habitat.setAreaOfInterest(area: intersection) as! GeoTIFFReadLayer<UInt8>

        let path = "/Users/michael/Desktop/test.tiff"
        let url = URL(fileURLWithPath: path)
        let parentUrl = url.deletingLastPathComponent()

        // Generate image and write PNG to file
        try FileManager.default.createDirectory(at: parentUrl, withIntermediateDirectories: true)

        let geotiff = try GeoTIFFImage<Double>(writingAt: path, size: Size(width: targetted_geometry.window.xsize, height: targetted_geometry.window.ysize), samplesPerPixel: 1, hasAlpha: false)

        try geotiff.setPixelScale([geometry.pixelScale.x, geometry.pixelScale.y * -1, 0.0])
        try geotiff.setTiePoint([0.0, 0.0, 0.0, targetted_geometry.area.left, targetted_geometry.area.top, 0.0])
        try geotiff.setProjection("WGS 84")

        let directoryEntries = [
            GeoTIFFDirectoryEntry(
                keyID: .GTModelTypeGeoKey,
                tiffTag: nil,
                valueCount: 1,
                valueOrIndex: 2
            ),
            GeoTIFFDirectoryEntry(
                keyID: .GTRasterTypeGeoKey,
                tiffTag: nil,
                valueCount: 1,
                valueOrIndex: 1
            ),
            GeoTIFFDirectoryEntry(
                keyID: .GeodeticCitationGeoKey,
                tiffTag: 34737,
                valueCount: 1,
                valueOrIndex: 2 //?
            ),
            GeoTIFFDirectoryEntry(
                keyID: .GeodeticCRSGeoKey,
                tiffTag: nil,
                valueCount: 1,
                valueOrIndex: 4326
            ),
        ]
        let directory = GeoTIFFDirectory(
            majorVersion: 1,
            minorVersion: 1,
            revision: 1,
            entries: directoryEntries
        )
        try geotiff.setDirectory(directory)

        var area = 0.0

        let chunkSize = 512//targetted_geometry.window.ysize/100
        let bufferSize = chunkSize * targetted_geometry.window.xsize
        let resultBuffer = UnsafeMutablePointer<Double>.allocate(capacity: bufferSize)

        let habitat_list: [UInt8] = [130, 100, 40, 200, 201, 202, 140, 110, 152, 220, 150, 120, 153, 122, 60, 61, 62]

        for y in stride(from: 0, to: targetted_geometry.window.ysize, by: chunkSize) {
            let actualSize = y + chunkSize < targetted_geometry.window.ysize ? chunkSize : targetted_geometry.window.ysize - y
            let window = Window(
                xoff: 0,
                yoff: y,
                xsize: targetted_geometry.window.xsize,
                ysize: actualSize
            )
            try targetted_geometry.withDataAt(region: window) { geometry_data in
                guard geometry_data.count <= bufferSize else {
                    throw AoHCalcError.TooMuchData
                }

                try targetted_elevation.withDataAt(region: window) { elevation_data in
                    guard elevation_data.count <= bufferSize else {
                        throw AoHCalcError.TooMuchData
                    }
                    guard elevation_data.count == geometry_data.count else {
                        throw AoHCalcError.TooMuchData
                    }

                    try targetted_habitat.withDataAt(region: window) { habitat_data in
                        guard habitat_data.count <= bufferSize else {
                            throw AoHCalcError.TooMuchData
                        }
                        guard habitat_data.count == geometry_data.count else {
                            throw AoHCalcError.TooMuchData
                        }

                        try targetted_area.withDataAt(region: window) { area_data in
                            guard area_data.count == actualSize else {
                                throw AoHCalcError.TooMuchData
                            }

                            for i in 0..<elevation_data.count {
                                let elevation: Int16 = elevation_data[i]
                                let habitat: UInt8 = habitat_data[i]
                                var val: Double = 0
                                if (elevation >= 0) && (elevation <= 3800) {
                                    if (habitat_list.contains(habitat)) {
                                        if (geometry_data[i] != 0) {
                                            val = area_data[(i / targetted_geometry.window.xsize)]
                                            area += val
                                        }
                                    }
                                }
                                resultBuffer[i] = val
                            }

                            let area = LibTIFF.Area(
                                origin: Point(x: 0, y: y),
                                size: Size(width: targetted_geometry.window.xsize, height: actualSize)
                            )
			                try geotiff.write(area: area, buffer: resultBuffer)
                        }
                    }
                }
            }
        }

        geotiff.close()

        return area
    }

    mutating func run() throws {

        // load config
        let config_url = URL(fileURLWithPath: configPath)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let config_data = try Data(contentsOf: config_url)

        let config: Config
        do {
            config = try decoder.decode(Config.self, from: config_data)
        } catch {
            print("Failed to parse config: \(error)")
            return
        }

        guard let experimentConfig = config.experiments[experiment] else {
            print("Failed to find experiment '\(experiment)' in \(config.experiments.keys)")
            return
        }

        let package = try GeoPackage(experimentConfig.range)
        let layer = try package.getLayers().first!

        let id_column = layer.columns["id_no"] as! Expression<Double>
        let features = try package.getFeaturesForLayer(layer: layer, predicate: id_column == Double(taxid))
        let species = try package.getGeometryForFeature(feature: features.first!)

        let areaLayer = try UniformAreaLayer<Double>(experimentConfig.area)
        let rangeLayer = try GeometryLayer(geometry: species, pixelScale: areaLayer.pixelScale)
        let elevationLayer = try GeoTIFFReadLayer<Int16>(experimentConfig.elevation)
        let habitatLayer = try GeoTIFFReadLayer<UInt8>(experimentConfig.habitat)

        let aoh = try calculator(geometry: rangeLayer, area: areaLayer, elevation: elevationLayer, habitat: habitatLayer)
        print("\(aoh)")
    }
}
