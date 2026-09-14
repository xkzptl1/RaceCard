// swift-tools-version: 5.9
import PackageDescription
let package = Package(name:"RaceCardDataKit",platforms:[.macOS("15.0")],products:[.library(name:"RaceCardDataKit",targets:["RaceCardDataKit"])],targets:[.target(name:"RaceCardDataKit"),.testTarget(name:"RaceCardDataKitTests",dependencies:["RaceCardDataKit"])])
