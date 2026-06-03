import Foundation

struct StatusFileReader {
    private let statusURL = URL(fileURLWithPath: "/var/tmp/thermalbar/status.json")

    func readStatus() -> Result<ThermalStatus, Error> {
        do {
            let data = try Data(contentsOf: statusURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return .success(try decoder.decode(ThermalStatus.self, from: data))
        } catch {
            return .failure(error)
        }
    }
}
