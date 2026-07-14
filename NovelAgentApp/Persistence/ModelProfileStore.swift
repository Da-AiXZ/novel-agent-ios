import Foundation
import GRDB
import NovelAgentCore
import NovelAgentProviders

struct StoredModelProfile: Codable, Hashable, Identifiable, Sendable {
    var configuration: ProviderConfiguration
    var keyReference: String
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    var id: UUID { configuration.id }
}

final class ModelProfileStore: @unchecked Sendable {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func profiles() throws -> [StoredModelProfile] {
        try database.dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM model_profiles ORDER BY isActive DESC, updatedAt DESC"
            )
            return try rows.map { row in
                let raw: String = row["json"]
                guard let data = raw.data(using: .utf8) else {
                    throw CoreError.invalidUTF8
                }
                let configuration = try JSONDecoder.novelAgent.decode(
                    ProviderConfiguration.self,
                    from: data
                )
                return StoredModelProfile(
                    configuration: configuration,
                    keyReference: row["keyReference"],
                    isActive: row["isActive"],
                    createdAt: row["createdAt"],
                    updatedAt: row["updatedAt"]
                )
            }
        }
    }

    func activeProfile() throws -> StoredModelProfile? {
        try profiles().first(where: \.isActive)
    }

    func save(
        configuration: ProviderConfiguration,
        keyReference: String,
        makeActive: Bool
    ) throws {
        try database.dbPool.write { db in
            if makeActive {
                try db.execute(sql: "UPDATE model_profiles SET isActive = 0")
            }
            let data = try JSONEncoder.novelAgent.encode(configuration)
            guard let json = String(data: data, encoding: .utf8) else {
                throw CoreError.invalidUTF8
            }
            let now = Date()
            try db.execute(
                sql: """
                    INSERT INTO model_profiles
                    (id, name, kind, keyReference, isActive, json, createdAt, updatedAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        kind = excluded.kind,
                        keyReference = excluded.keyReference,
                        isActive = excluded.isActive,
                        json = excluded.json,
                        updatedAt = excluded.updatedAt
                    """,
                arguments: [
                    configuration.id.uuidString,
                    configuration.name,
                    configuration.kind.rawValue,
                    keyReference,
                    makeActive,
                    json,
                    now,
                    now
                ]
            )
        }
    }

    func setActive(id: UUID) throws {
        try database.dbPool.write { db in
            try db.execute(sql: "UPDATE model_profiles SET isActive = 0")
            try db.execute(
                sql: "UPDATE model_profiles SET isActive = 1, updatedAt = ? WHERE id = ?",
                arguments: [Date(), id.uuidString]
            )
        }
    }

    func delete(id: UUID) throws {
        try database.dbPool.write { db in
            try db.execute(
                sql: "DELETE FROM model_profiles WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }
}
