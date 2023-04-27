import Foundation

import ArgumentParser
import GeoPackage
import LibTIFF
import SQLite
import Yirgacheffe

#if true //experiment == "jung"
typealias AreaType = Float
typealias ElevationType = UInt16
typealias HabitatType = Int16
#else // esacii
typealias AreaType = Double
typealias ElevationType = Int16
typealias HabitatType = UInt8
#endif

typealias AreaLayer = UniformAreaLayer<AreaType>
typealias ElevationLayer = GeoTIFFReadLayer<ElevationType>
typealias HabitatLayer = GeoTIFFReadLayer<HabitatType>

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

// from https://github.com/kodecocodes/swift-algorithm-club/blob/master/Binary%20Search/BinarySearch.swift
public func binarySearch<T: Comparable>(_ a: [T], key: T) -> Int? {
    var lowerBound = 0
    var upperBound = a.count
    while lowerBound < upperBound {
        let midIndex = lowerBound + (upperBound - lowerBound) / 2
        let val = a[midIndex]
        if val == key {
            return midIndex
        } else if val < key {
            lowerBound = midIndex + 1
        } else {
            upperBound = midIndex
        }
    }
    return nil
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
        area: AreaLayer,
        elevation: ElevationLayer,
        habitat: HabitatLayer,
        habitat_types: Set<HabitatType>,
        elevation_range: ClosedRange<Int>
    ) throws -> Double {
        let layers: [any Yirgacheffe.Layer] = [geometry, area, elevation, habitat]
        let intersection: Yirgacheffe.Area
        do {
            intersection = try calculateIntersection(layers: layers)
        } catch {
            for layer in layers {
                print("\(layer.pixelScale)")
            }
            throw error
        }
        let targetted_geometry = try geometry.setAreaOfInterest(area: intersection) as! GeometryLayer
        let targetted_area = try area.setAreaOfInterest(area: intersection) as! AreaLayer
        let targetted_elevation = try elevation.setAreaOfInterest(area: intersection) as! ElevationLayer
        let targetted_habitat = try habitat.setAreaOfInterest(area: intersection) as! HabitatLayer

        let path = "/scratch/4C/test.tiff"
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

        // On Linux rendering is backed by Cairo for the vector layers,
        // and the maximum size of an image there is 32K by 32K
        // let chunkSize = Size(width: 512, height: 512)
        let chunkSize = Size(width: targetted_geometry.window.xsize, height: 512)

        let habitat_list = Array(habitat_types).sorted()

        let target_window = targetted_geometry.window

        for y in stride(from: 0, to: targetted_geometry.window.ysize, by: chunkSize.height) {
            let actualHeight = y + chunkSize.height < target_window.ysize ? chunkSize.height : target_window.ysize - y

            // hack to work around TIFF file format - we should use tiles eventually
            let buffer = UnsafeMutableBufferPointer<Double>.allocate(capacity: actualHeight * target_window.xsize)
            defer { buffer.deallocate() }

            for x in stride(from: 0, to: targetted_geometry.window.xsize, by: chunkSize.width) {

                let actualWidth = x + chunkSize.width < target_window.xsize ? chunkSize.width : target_window.xsize - x

                let window = Window(
                    xoff: x,
                    yoff: y,
                    xsize: actualWidth,
                    ysize: actualHeight
                )
                try targetted_geometry.withDataAt(region: window) { geometry_data, geometry_stride in
                    guard geometry_data.count >= (actualWidth * actualHeight) else {
                        throw AoHCalcError.TooMuchData
                    }
                    guard geometry_stride >= actualWidth else {
                        throw AoHCalcError.TooMuchData
                    }

                    try targetted_elevation.withDataAt(region: window) { elevation_data, elevation_stride in
                        guard elevation_data.count == (actualWidth * actualHeight) else {
                            throw AoHCalcError.TooMuchData
                        }
                        guard elevation_stride == actualWidth else {
                            throw AoHCalcError.TooMuchData
                        }

                        try targetted_habitat.withDataAt(region: window) { habitat_data, habitat_stride in
                            guard habitat_data.count == (actualWidth * actualHeight) else {
                                throw AoHCalcError.TooMuchData
                            }
                            guard habitat_stride == actualWidth else {
                                throw AoHCalcError.TooMuchData
                            }

                            try targetted_area.withDataAt(region: window) { area_data, area_stride in
                                guard area_data.count == actualHeight else {
                                    throw AoHCalcError.TooMuchData
                                }
                                guard area_stride == 1 else {
                                    throw AoHCalcError.TooMuchData
                                }

                                let resultBuffer: [Double] = geometry_data.enumerated().map { index, geometry in
                                    let indexWithoutStride = ((index / geometry_stride) * actualWidth) + (index % geometry_stride)

                                    var val: Double = 0.0
                                    if geometry != 0 {
                                        let elevation = Int(elevation_data[indexWithoutStride])
                                        if elevation_range.contains(elevation) {
                                            let habitat: HabitatType = habitat_data[indexWithoutStride]
                                            if binarySearch(habitat_list, key: habitat) != nil {
                                                val = Double(area_data[(index / geometry_stride)])
                                                area += val
                                            }
                                        }
                                    }
                                    return val
                                }

                                resultBuffer.withUnsafeBufferPointer { result in
                                    for row in 0..<actualHeight {
                                        let src = result.baseAddress!.advanced(by: row * geometry_stride)
                                        let target = buffer.baseAddress!.advanced(by: (row * target_window.xsize) + x)
                                        target.update(from: src, count: actualWidth)
                                    }
                                }
//
//                                 let area = LibTIFF.Area(
//                                     origin: Point(x: x, y: y),
//                                     size: Size(width: actualWidth, height: actualHeight)
//                                 )
//                                 try resultBuffer.withUnsafeBufferPointer {
//     			                    try geotiff.write(area: area, buffer: $0)
//                                 }
                            }
                        }
                    }
                }
            }

            let area = LibTIFF.Area(
                origin: Point(x: 0, y: y),
                size: Size(width: target_window.xsize, height: actualHeight)
            )
            let immute = UnsafeBufferPointer<Double>(buffer)
            try geotiff.write(area: area, buffer: immute)


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

        let iucnBatch = try IUCNBatch(experimentConfig.iucnBatch)
        let iucnHabitats = try iucnBatch.getHabitatForSpecies(taxid)
        let jungHabitats = try Set(convertIUCNToJung(iucnHabitats).map { HabitatType($0 & 0xFF) })
        let jungElevation = try iucnBatch.getElevationRangeForSpecies(taxid)
        print("Habitats: \(Array(jungHabitats).sorted())")
        print("Elevation: \(jungElevation)")

        let package = try GeoPackage(experimentConfig.range)
        let layer = try package.getLayers().first!

        let id_column = layer.columns["id_no"] as! Expression<Double>
        let features = try package.getFeaturesForLayer(layer: layer, predicate: id_column == Double(taxid))
        let species = try package.getGeometryForFeature(feature: features.first!)

        let areaLayer: AreaLayer
        do {
            areaLayer = try AreaLayer(experimentConfig.area)
        } catch {
            print("Failed to open area \(experimentConfig.area): \(error)")
            return
        }

        let rangeLayer: GeometryLayer
        do {
            rangeLayer = try GeometryLayer(geometry: species, pixelScale: areaLayer.pixelScale)
        } catch {
            print("Failed to open geometry for species \(taxid): \(error)")
            return
        }

        let elevationLayer: ElevationLayer
        do {
            elevationLayer = try ElevationLayer(experimentConfig.elevation)
        } catch {
            print("Failed to open elevation \(experimentConfig.elevation): \(error)")
            return
        }

        let habitatLayer: HabitatLayer
        do {
            habitatLayer = try HabitatLayer(experimentConfig.habitat)
        } catch {
            print("Failed to open habitat \(experimentConfig.habitat): \(error)")
            return
        }

        let aoh = try calculator(
            geometry: rangeLayer,
            area: areaLayer,
            elevation: elevationLayer,
            habitat: habitatLayer,
            habitat_types: jungHabitats,
            elevation_range: jungElevation
        )
        print("\(aoh)")
    }
}
