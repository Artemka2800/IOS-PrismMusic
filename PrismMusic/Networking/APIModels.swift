//
//  APIModels.swift
//  PrismMusic
//
//  Response DTOs for the PrismMusic backend. Shapes mirror what the
//  Next.js routes return in `app/api/music/*`.
//

import Foundation

/// `GET /api/music/search` — returns tracks + playlists + artists.
/// Backend sends `playlists` key, not `albums`.
struct SearchResponse: Decodable, Sendable {
    let tracks: [Track]
    let albums: [Album]?

    /// The backend sometimes omits optional sections; default them to empty.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.tracks = (try? container.decode([Track].self, forKey: .tracks)) ?? []

        // Backend sends playlists, not albums. Map playlists → albums.
        if let playlists = try? container.decode([SearchPlaylistDTO].self, forKey: .playlists) {
            self.albums = playlists.compactMap { p in
                Album(
                    id: p.id,
                    title: p.name ?? "Плейлист",
                    artist: p.description ?? "SoundCloud",
                    year: nil,
                    cover: p.coverUrl.flatMap { URL(string: $0) },
                    source: TrackSource(rawValue: p.source?.lowercased() ?? "soundcloud") ?? .soundcloud,
                    tracks: nil
                )
            }
        } else {
            self.albums = try? container.decode([Album].self, forKey: .albums)
        }
    }

    enum CodingKeys: String, CodingKey {
        case tracks, albums, playlists
    }
}

/// DTO for playlists in search results.
private struct SearchPlaylistDTO: Decodable, Sendable {
    let id: String
    let name: String?
    let coverUrl: String?
    let description: String?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case id, name, coverUrl, description, source
    }
}

/// `GET /api/music/recommendations` — returns playlists from SoundCloud.
///
/// Backend shape:
/// ```json
/// {
///   "title": "Подборки для вас",
///   "playlists": [
///     { "id": "...", "name": "...", "coverUrl": "...", "description": "...", "source": "soundcloud", "tracks": [] }
///   ]
/// }
/// ```
///
/// We map `playlists` → `[Album]` for display in the home grid.
struct RecommendationsResponse: Decodable, Sendable {
    let title: String?
    let albums: [Album]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try? container.decode(String.self, forKey: .title)

        // The backend returns `playlists`, each with { id, name, coverUrl, description, source, tracks }
        if let playlists = try? container.decode([PlaylistDTO].self, forKey: .playlists) {
            self.albums = playlists.map { playlist in
                Album(
                    id: playlist.id,
                    title: playlist.name,
                    artist: playlist.description ?? playlist.source ?? "SoundCloud",
                    year: nil,
                    cover: playlist.coverUrl.flatMap { URL(string: $0) },
                    source: TrackSource(rawValue: playlist.source ?? "soundcloud") ?? .soundcloud,
                    tracks: nil
                )
            }
        } else {
            // Fallback: try parsing as { tracks, albums } for forward-compat
            self.albums = (try? container.decode([Album].self, forKey: .albums)) ?? []
        }
    }

    enum CodingKeys: String, CodingKey {
        case title, playlists, albums
    }
}

/// Internal DTO matching the backend's playlist shape.
/// All fields are optional/flexible to prevent decode failures.
private struct PlaylistDTO: Decodable, Sendable {
    let id: String
    let name: String
    let coverUrl: String?
    let description: String?
    let source: String?
    let isSystem: Bool?
    // `tracks` is intentionally omitted — we don't need playlist tracks
    // from the recommendations endpoint, and including it risks decode
    // failures if the track format differs from our Track model.

    enum CodingKeys: String, CodingKey {
        case id, name, coverUrl, description, source, isSystem
    }
}

/// `GET /api/music/lyrics` — raw LRC blob.
struct LyricsResponse: Decodable, Sendable {
    let lyrics: String?
    let source: String?
}

/// `GET /api/music/playlist?id=...&source=...` — playlist detail with tracks.
struct PlaylistDetailResponse: Decodable, Sendable {
    let id: String?
    let name: String?
    let coverUrl: String?
    let description: String?
    let tracks: [Track]
    let source: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try? container.decode(String.self, forKey: .id)
        self.name = try? container.decode(String.self, forKey: .name)
        self.coverUrl = try? container.decode(String.self, forKey: .coverUrl)
        self.description = try? container.decode(String.self, forKey: .description)
        self.tracks = (try? container.decode([Track].self, forKey: .tracks)) ?? []
        self.source = try? container.decode(String.self, forKey: .source)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, coverUrl, description, tracks, source
    }
}

/// `POST /api/music/yandex/import` — returns imported likes and playlists.
struct YandexImportResponse: Decodable, Sendable {
    let importedLikes: [Track]
}

/// `POST /api/auth/login` and `POST /api/auth/register` response.
struct UserResponse: Codable, Sendable {
    let id: String
    let username: String
    let token: String? // Yandex OAuth token
    let avatarUrl: String?
    let role: String?
    let createdAt: String?
}

/// `GET /api/music/mix` — daily mixes response
struct DailyMixesResponse: Decodable, Sendable {
    let mixes: [Album]
}

struct UserPlaylistDTO: Decodable, Sendable {
    let id: String
    let name: String
    let description: String?
    let coverUrl: String?
    let isSystem: Bool?
    let tracks: [Track]?

    var toAlbum: Album {
        Album(
            id: id,
            title: name,
            artist: description ?? "Мой плейлист",
            year: nil,
            cover: coverUrl.flatMap { URL(string: $0) },
            source: .other,
            tracks: tracks
        )
    }
}

struct PlaylistSuccessResponse: Decodable, Sendable {
    let success: Bool
}

/// Dynamic payload structures for Cross-Device Sync
struct SyncResponse: Decodable, Sendable {
    let success: Bool?
    let error: String?
}

struct SyncMessage: Decodable, Sendable {
    let clientId: String
    let type: String // "player", "settings", "token"
}

struct PlayerSyncPayload: Codable, Sendable {
    let track: Track?
    let isPlaying: Bool?
    let volume: Float?
    let currentTime: Double?
    let timestamp: Double?
}

struct SettingsSyncPayload: Codable, Sendable {
    let theme: String?
    let immersive: Bool?
    let yandexToken: String?
}

// MARK: - Artist

/// `GET /api/music/artist?id=...&source=...` — artist page data.
struct ArtistResponse: Decodable, Sendable {
    let id: String
    let name: String
    let avatarUrl: String?
    let followers: Int?
    let city: String?
    let tracks: [Track]
    let albums: [ArtistAlbumDTO]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.avatarUrl = try? container.decode(String.self, forKey: .avatarUrl)
        self.followers = try? container.decode(Int.self, forKey: .followers)
        self.city = try? container.decode(String.self, forKey: .city)
        self.tracks = (try? container.decode([Track].self, forKey: .tracks)) ?? []
        self.albums = (try? container.decode([ArtistAlbumDTO].self, forKey: .albums)) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case id, name, avatarUrl, followers, city, tracks, albums
    }
}

/// Backend album/playlist shape inside artist responses.
struct ArtistAlbumDTO: Decodable, Sendable {
    let id: String
    let name: String?
    let coverUrl: String?
    let description: String?
    let source: String?

    var toAlbum: Album {
        Album(
            id: id,
            title: name ?? "Альбом",
            artist: description ?? source ?? "Неизвестный",
            year: nil,
            cover: coverUrl.flatMap { URL(string: $0) },
            source: TrackSource(rawValue: source ?? "soundcloud") ?? .soundcloud,
            tracks: nil
        )
    }
}

// MARK: - Profile

struct BadgeProgressItem: Codable, Sendable {
    let current: Int
    let target: Int
}

struct TopArtistItem: Codable, Sendable {
    let name: String
    let count: Int
    let coverUrl: String?
}

struct RecentHistoryItem: Codable, Sendable {
    let track: Track
    let playedAt: String
}

struct ProfileStats: Codable, Sendable {
    let id: String
    let username: String
    let avatarUrl: String?
    let bio: String?
    let bannerUrl: String?
    let pinnedTrack: Track?
    let unlockedBadges: [String]
    let badgeProgress: [String: BadgeProgressItem]?
    let tracksListened: Int
    let likedTracks: Int
    let playlistCount: Int
    let memberSince: String
    let role: String?
    let topArtists: [TopArtistItem]?
    let recentHistory: [RecentHistoryItem]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.username = try container.decode(String.self, forKey: .username)
        self.avatarUrl = try? container.decode(String.self, forKey: .avatarUrl)
        self.bio = try? container.decode(String.self, forKey: .bio)
        self.bannerUrl = try? container.decode(String.self, forKey: .bannerUrl)
        self.pinnedTrack = try? container.decode(Track.self, forKey: .pinnedTrack)
        self.unlockedBadges = (try? container.decode([String].self, forKey: .unlockedBadges)) ?? []
        self.badgeProgress = try? container.decode([String: BadgeProgressItem].self, forKey: .badgeProgress)
        self.tracksListened = (try? container.decode(Int.self, forKey: .tracksListened)) ?? 0
        self.likedTracks = (try? container.decode(Int.self, forKey: .likedTracks)) ?? 0
        self.playlistCount = (try? container.decode(Int.self, forKey: .playlistCount)) ?? 0
        self.memberSince = (try? container.decode(String.self, forKey: .memberSince)) ?? ""
        self.role = try? container.decode(String.self, forKey: .role)
        self.topArtists = try? container.decode([TopArtistItem].self, forKey: .topArtists)
        self.recentHistory = try? container.decode([RecentHistoryItem].self, forKey: .recentHistory)
    }

    enum CodingKeys: String, CodingKey {
        case id, username, avatarUrl, bio, bannerUrl, pinnedTrack, unlockedBadges, badgeProgress, tracksListened, likedTracks, playlistCount, memberSince, role, topArtists, recentHistory
    }
}

// MARK: - Comments

struct CommentAuthor: Codable, Sendable {
    let id: String
    let username: String
    let avatarUrl: String?
    let role: String?
}

struct CommentItem: Codable, Identifiable, Sendable {
    let id: String
    let content: String
    let createdAt: String
    let author: CommentAuthor
}

struct CommentsResponse: Codable, Sendable {
    let comments: [CommentItem]
    let total: Int
}
