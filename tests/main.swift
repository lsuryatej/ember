import Foundation

// Top-level statements are only legal in main.swift, so the runner lives here.

runWireTests()
runEngineTests()
runFeatureTests()

print("\n\(checks - failures)/\(checks) checks passed")
if failures > 0 {
    print("\(failures) FAILED")
    exit(1)
}
print("all green")
