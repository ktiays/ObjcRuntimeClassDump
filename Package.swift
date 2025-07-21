// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "ObjcRuntimeClassDump",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "ObjcRuntimeClassDump",
            targets: ["ObjcRuntimeClassDump"]
        )
    ],
    targets: [
        .target(
            name: "ObjcRuntimeClassDump",
            exclude: [
                "objc-encodingparser/run-test.c"
            ]
        )
    ],
    cxxLanguageStandard: .cxx20,
)
