import Foundation

struct SchoolClosing: Codable, Hashable {
    let name: String
    let status: String
    let updateTime: String
    let source: String

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case status = "Status"
        case updateTime = "UpdateTime"
        case source = "Source"
    }
}

struct ClosingsResponse: Codable {
    let lastUpdated: String
    let entries: [SchoolClosing]

    enum CodingKeys: String, CodingKey {
        case lastUpdated = "lastUpdated"
        case entries = "entries"
    }
}

class SchoolClosingsViewModel: ObservableObject {
    @Published var entries: [SchoolClosing] = []
    @Published var lastUpdated: String = "Never"
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let apiURL = "https://yr4zm4dy27.execute-api.us-east-1.amazonaws.com/Prod/"

    func fetchClosings(completion: @escaping () -> Void = {}) {
        isLoading = true
        errorMessage = nil

        guard let url = URL(string: apiURL) else {
            DispatchQueue.main.async {
                self.errorMessage = "Invalid URL"
                self.isLoading = false
                completion()
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                defer {
                    self?.isLoading = false
                    completion()
                }

                // Check for network errors
                if let error = error {
                    self?.errorMessage = "Network error: \(error.localizedDescription)"
                    return
                }

                // Check HTTP response
                guard let httpResponse = response as? HTTPURLResponse else {
                    self?.errorMessage = "Invalid response"
                    return
                }

                guard httpResponse.statusCode == 200 else {
                    self?.errorMessage = "HTTP Error: \(httpResponse.statusCode)"
                    return
                }

                // Parse JSON
                guard let data = data else {
                    self?.errorMessage = "No data received"
                    return
                }

                do {
                    let decoder = JSONDecoder()
                    let response = try decoder.decode(ClosingsResponse.self, from: data)
                    self?.entries = response.entries.sorted { $0.name < $1.name }
                    self?.lastUpdated = response.lastUpdated
                } catch {
                    self?.errorMessage = "Failed to parse data: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
}
