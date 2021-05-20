//
//  Gir2Swift.swift
//  libgir2swift
//
//  Created by Rene Hexel on 20/5/21.
//  Copyright © 2021 Rene Hexel. All rights reserved.
//
import ArgumentParser
import Foundation

/// Structure representing the `gir2swift` executable, including command line arguments
public struct Gir2Swift: ParsableCommand {
    /// Produce verbose output if `true`
    @Flag(name: .short, help: "Produce verbose output.")
    var verbose = false

    /// Generate output for everything, including private C types if `true`
    @Flag(name: .short, help: "Disables all filters. Wrappers for all C types will be generated.")
    var allFilesGenerate = false

    /// Create a single output file per class if `true`
    @Flag(name: .short, help: "Create a single .swift file per class.")
    var singleFilePerClass = false

    /// Array of names of pre-parsed `.gir` files.
    @Option(name: .short, help: "Add pre-requisite .gir files to ensure the types in file.gir are known.")
    var prerequisiteGir: [String] = []

    /// Name of the output directory to write generated files to.
    /// - Note: Writes generated code to `standardOutput` if `nil`
    @Option(name: .short, help: "Specify the output directory to put the generated files into.", transform: String.init(nonEmpty:))
    var outputDirectory: String? = nil

    /// File containing one-off boilerplate code for your module
    @Option(name: .short, help: "Add .swift as the main (hand-crafted) Swift file for your library target.")
    var moduleBoilerPlate: String = ""

    /// The actual, main `.gir` file(s) to process
    @Argument(help: "The .gir metadata files to process.")
    var girFiles: [String]
    
    /// Designated initialiser
    public init() {}
    
    /// Main function to run the `gir2swift command`
    mutating public func run() throws {
        let nTypesPrior = GIR.knownTypes.count

        for girFile in girFiles {
            process_gir(file: girFile, boilerPlate: moduleBoilerPlate, to: outputDirectory, split: singleFilePerClass, generateAll: allFilesGenerate)
        }

        if verbose {
            let nTypesAfter = GIR.knownTypes.count
            let nTypesAdded = nTypesAfter - nTypesPrior
            print("Processed \(nTypesAdded) types (total: \(nTypesAfter)).")
        }
    }
}

