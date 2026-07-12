import Foundation

struct GraphGenerator {
    let entries: [ProxyGenerator.GraphEntry]
    let outputPath: URL

    init(entries: [ProxyGenerator.GraphEntry], outputPath: URL) {
        self.entries = entries
        self.outputPath = outputPath
    }

    func generate() throws {
        var graph: [[String: Any]] = []
        for entry in entries {
            graph.append([
                "data": [
                    "id": entry.module,
                    "module": entry.module,
                    "status": entry.status.rawValue,
                    "hasMacro": entry.hasMacro,
                ]
            ])

            for dep in entry.dependencies {
                graph.append([
                    "data": [
                        "source": entry.module,
                        "target": dep,
                    ]
                ])
            }
        }

        let data = try JSONSerialization.data(withJSONObject: graph, options: .prettyPrinted)
        try data.write(to: outputPath)
        Logger.info("Generated graph at \(outputPath.path)")
    }
}
