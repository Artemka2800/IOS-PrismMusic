//
//  APIClient.swift
//  PrismMusic
//
//  Networking layer talking to the PrismMusic Next.js backend. One class
//  exposes typed methods for search, recommendations, lyrics, and the
//  stream-proxy URL builder. Always pulls the current backend host and
//  Yandex token from `SettingsStore` so changes propagate immediately.
//

import Foundation
import Observation

@MainActor
final class APIClient {
    let settings: SettingsStore
    private let session: URLSession
    private let decoder: JSONDecoder

    init(settings: SettingsStore) {
        self.settings = settings

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = APIConfig.timeoutSeconds
        config.timeoutIntervalForResource = APIConfig.timeoutSeconds * 2
        // Use the URL cache to dedupe identical recommendation / search requests
        // within a single session — saves a network round-trip on tab switches.
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 32 * 1024 * 1024)

        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    // MARK: - Endpoints

    /// `GET /api/music/search?q=...`
    func search(query: String) async throws -> SearchResponse {
        return try await executeWithFailover(
            path: "/api/music/search",
            queryItems: [URLQueryItem(name: "q", value: query)],
            as: SearchResponse.self
        )
    }

    /// `GET /api/music/recommendations`
    func recommendations() async throws -> RecommendationsResponse {
        return try await executeWithFailover(
            path: "/api/music/recommendations",
            as: RecommendationsResponse.self
        )
    }

    /// `GET /api/music/lyrics?artist=...&title=...&id=...&duration=...`
    func lyrics(artist: String, title: String, id: String? = nil, duration: Double? = nil)
        async throws -> LyricsResponse?
    {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "artist", value: artist),
            URLQueryItem(name: "title", value: title),
        ]
        if let id { items.append(URLQueryItem(name: "id", value: id)) }
        if let duration { items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }

        do {
            return try await executeWithFailover(
                path: "/api/music/lyrics",
                queryItems: items,
                as: LyricsResponse.self
            )
        } catch APIError.httpStatus(let code, _) where code == 404 {
            return nil
        }
    }

    /// Builds the proxied stream URL for a given track. AVPlayer hits this
    /// URL directly; we never download the bytes ourselves.
    func streamURL(for track: Track) -> URL? {
        let trimmed = settings.backendURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = URL(string: trimmed),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        
        if components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        components.path += "/api/music/stream"
        
        var items: [URLQueryItem] = [
            URLQueryItem(name: "id", value: track.id),
            URLQueryItem(name: "source", value: track.source?.rawValue ?? "soundcloud"),
        ]
        if !settings.yandexToken.isEmpty {
            items.append(URLQueryItem(name: "token", value: settings.yandexToken))
        }
        components.queryItems = items
        return components.url
    }

    /// `GET /api/music/playlist?id=...&source=...` — fetches tracks for a playlist/album.
    func playlistTracks(id: String, source: String) async throws -> [Track] {
        if source == "other" || source == "local" || (source == "system" && !id.hasPrefix("daily_mix_") && !id.hasPrefix("radio_")) {
            let details = try await fetchPlaylistDetails(playlistId: id)
            return details.tracks ?? []
        }
        let items = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "source", value: source),
        ]
        let response = try await executeWithFailover(
            path: "/api/music/playlist",
            queryItems: items,
            as: PlaylistDetailResponse.self
        )
        return response.tracks
    }

    /// `POST /api/music/yandex/import` — imports Yandex Liked tracks.
    func importYandexLikes(userId: String? = nil) async throws -> YandexImportResponse {
        var body: [String: Any] = [:]
        if let userId {
            body["userId"] = userId
        }
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        
        var headers: [String: String] = [:]
        if !settings.yandexToken.isEmpty {
            headers["x-yandex-token"] = settings.yandexToken
        }
        
        return try await executeWithFailover(
            path: "/api/music/yandex/import",
            method: "POST",
            bodyData: bodyData,
            headers: headers,
            as: YandexImportResponse.self
        )
    }

    /// `POST /api/auth/login`
    func login(username: String, password: String) async throws -> UserResponse {
        let body = ["username": username, "password": password]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        return try await executeWithFailover(
            path: "/api/auth/login",
            method: "POST",
            bodyData: bodyData,
            as: UserResponse.self
        )
    }

    /// `POST /api/auth/register`
    func register(username: String, password: String) async throws -> UserResponse {
        let body = ["username": username, "password": password]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        return try await executeWithFailover(
            path: "/api/auth/register",
            method: "POST",
            bodyData: bodyData,
            as: UserResponse.self
        )
    }

    /// `POST /api/user/subscribe`
    func subscribe(userId: String, action: String) async throws -> UserResponse {
        let body = ["userId": userId, "action": action]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        return try await executeWithFailover(
            path: "/api/user/subscribe",
            method: "POST",
            bodyData: bodyData,
            as: UserResponse.self
        )
    }

    /// `GET /api/library/likes`
    func fetchLikedTracks(userId: String) async throws -> [Track] {
        return try await executeWithFailover(
            path: "/api/library/likes",
            queryItems: [URLQueryItem(name: "userId", value: userId)],
            as: [Track].self
        )
    }

    /// `POST /api/library/likes`
    func toggleLikeOnServer(userId: String, track: Track) async throws -> Bool {
        let trackDict: [String: Any] = [
            "id": track.id,
            "title": track.title,
            "artist": track.artist,
            "coverUrl": track.cover?.absoluteString ?? "",
            "duration": Int(track.durationSeconds ?? 0),
            "source": track.source?.rawValue ?? "unknown"
        ]
        let body: [String: Any] = [
            "userId": userId,
            "track": trackDict
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        
        struct LikeResponse: Decodable {
            let liked: Bool
        }
        let result = try await executeWithFailover(
            path: "/api/library/likes",
            method: "POST",
            bodyData: bodyData,
            as: LikeResponse.self
        )
        return result.liked
    }

    struct FindResponse: Decodable {
        let results: [Track]
    }

    func findTrack(title: String, artist: String, targetSource: String) async throws -> [Track] {
        let body: [String: Any] = [
            "title": title,
            "artist": artist,
            "targetSource": targetSource
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let response = try await executeWithFailover(
            path: "/api/music/find",
            method: "POST",
            bodyData: bodyData,
            as: FindResponse.self
        )
        return response.results
    }

    func replaceLikedTrack(oldTrackId: String, newTrack: Track) async throws -> Bool {
        guard settings.isLoggedIn else { return false }
        let trackDict: [String: Any] = [
            "id": newTrack.id,
            "title": newTrack.title,
            "artist": newTrack.artist,
            "coverUrl": newTrack.cover?.absoluteString ?? "",
            "duration": Int(newTrack.durationSeconds ?? 0),
            "source": newTrack.source?.rawValue ?? "unknown"
        ]
        let body: [String: Any] = [
            "userId": settings.userId,
            "oldTrackId": oldTrackId,
            "newTrack": trackDict
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        
        struct ReplaceResponse: Decodable {
            let success: Bool
        }
        let result = try await executeWithFailover(
            path: "/api/library/likes",
            method: "PUT",
            bodyData: bodyData,
            as: ReplaceResponse.self
        )
        return result.success
    }

    /// `GET /api/music/mix?userId=...`
    func dailyMixes(userId: String) async throws -> [Album] {
        let response = try await executeWithFailover(
            path: "/api/music/mix",
            queryItems: [URLQueryItem(name: "userId", value: userId)],
            as: DailyMixesResponse.self
        )
        return response.mixes
    }

    /// `GET /api/library/playlists?userId=...`
    func fetchUserPlaylists(userId: String) async throws -> [Album] {
        let response = try await executeWithFailover(
            path: "/api/library/playlists",
            queryItems: [URLQueryItem(name: "userId", value: userId)],
            as: [UserPlaylistDTO].self
        )
        return response.map { $0.toAlbum }
    }

    /// `POST /api/library/playlists`
    func createPlaylist(userId: String, name: String, description: String) async throws -> Album {
        let body: [String: Any] = [
            "userId": userId,
            "name": name,
            "description": description
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let response = try await executeWithFailover(
            path: "/api/library/playlists",
            method: "POST",
            bodyData: bodyData,
            as: UserPlaylistDTO.self
        )
        return response.toAlbum
    }

    /// `DELETE /api/library/playlists?id=...`
    func deletePlaylist(playlistId: String) async throws {
        _ = try await executeWithFailover(
            path: "/api/library/playlists",
            method: "DELETE",
            queryItems: [URLQueryItem(name: "id", value: playlistId)],
            as: PlaylistSuccessResponse.self
        )
    }

    /// `POST /api/library/playlists/tracks`
    func addTrackToPlaylist(playlistId: String, track: Track) async throws {
        let idPart = track.id.components(separatedBy: ":").last ?? track.id
        let sourcePart = track.source?.rawValue ?? "soundcloud"
        let trackDict: [String: Any] = [
            "id": idPart,
            "title": track.title,
            "artist": track.artist,
            "coverUrl": track.cover?.absoluteString ?? "",
            "duration": Int(track.durationSeconds ?? 0),
            "source": sourcePart
        ]
        let body: [String: Any] = [
            "playlistId": playlistId,
            "track": trackDict
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        _ = try await executeWithFailover(
            path: "/api/library/playlists/tracks",
            method: "POST",
            bodyData: bodyData,
            as: PlaylistSuccessResponse.self
        )
    }

    /// `DELETE /api/library/playlists/tracks?playlistId=...&trackId=...`
    func removeTrackFromPlaylist(playlistId: String, trackId: String) async throws {
        let rawTrackId = trackId.components(separatedBy: ":").last ?? trackId
        let queryItems = [
            URLQueryItem(name: "playlistId", value: playlistId),
            URLQueryItem(name: "trackId", value: rawTrackId)
        ]
        _ = try await executeWithFailover(
            path: "/api/library/playlists/tracks",
            method: "DELETE",
            queryItems: queryItems,
            as: PlaylistSuccessResponse.self
        )
    }

    /// `GET /api/library/playlists?id=...`
    func fetchPlaylistDetails(playlistId: String) async throws -> Album {
        let response = try await executeWithFailover(
            path: "/api/library/playlists",
            queryItems: [URLQueryItem(name: "id", value: playlistId)],
            as: UserPlaylistDTO.self
        )
        return response.toAlbum
    }

    /// `PATCH /api/library/playlists`
    func updatePlaylist(playlistId: String, name: String, description: String, coverUrl: String) async throws -> Album {
        let body: [String: Any] = [
            "id": playlistId,
            "name": name,
            "description": description,
            "coverUrl": coverUrl
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let response = try await executeWithFailover(
            path: "/api/library/playlists",
            method: "PATCH",
            bodyData: bodyData,
            as: UserPlaylistDTO.self
        )
        return response.toAlbum
    }

    /// `GET /api/user/state?userId=...`
    func fetchPlayerState(userId: String) async throws -> PlayerSyncPayload? {
        do {
            let response = try await executeWithFailover(
                path: "/api/user/state",
                queryItems: [URLQueryItem(name: "userId", value: userId)],
                as: PlayerSyncPayload.self
            )
            return response
        } catch {
            print("[APIClient] Failed to fetch player state: \(error)")
            return nil
        }
    }

    /// `POST /api/user/sync`
    func syncState(userId: String, clientId: String, type: String, payload: Any) async throws {
        let body: [String: Any] = [
            "userId": userId,
            "clientId": clientId,
            "type": type,
            "payload": payload
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        _ = try await executeWithFailover(
            path: "/api/user/sync",
            method: "POST",
            bodyData: bodyData,
            as: SyncResponse.self
        )
    }

    /// `GET /api/music/artist?id=...&source=...` — artist profile with tracks and albums.
    func artist(id: String, source: String, userId: String? = nil) async throws -> ArtistResponse {
        var queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "source", value: source),
        ]
        if let userId = userId {
            queryItems.append(URLQueryItem(name: "userId", value: userId))
        }
        return try await executeWithFailover(
            path: "/api/music/artist",
            queryItems: queryItems,
            as: ArtistResponse.self
        )
    }

    /// `POST /api/music/artist/follow` — follow / unfollow an artist.
    func toggleFollowArtist(userId: String, artistId: String, source: String, name: String, avatarUrl: String?) async throws -> FollowResponse {
        var body: [String: Any] = [
            "userId": userId,
            "artistId": artistId,
            "source": source,
            "name": name
        ]
        if let avatarUrl = avatarUrl {
            body["avatarUrl"] = avatarUrl
        }
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        return try await executeWithFailover(
            path: "/api/music/artist/follow",
            method: "POST",
            bodyData: bodyData,
            as: FollowResponse.self
        )
    }

    /// `GET /api/user/profile/stats?userId=...` — user profile details and stats.
    func userStats(userId: String) async throws -> ProfileStats {
        return try await executeWithFailover(
            path: "/api/user/profile/stats",
            queryItems: [
                URLQueryItem(name: "userId", value: userId)
            ],
            as: ProfileStats.self
        )
    }

    /// `PATCH /api/user/profile` — updates user bio, avatar, banner, or pinned track.
    func updateProfile(
        userId: String,
        avatarUrl: String? = nil,
        bannerUrl: String? = nil,
        bio: String? = nil,
        pinnedTrack: Track? = nil,
        shouldRemovePinnedTrack: Bool = false
    ) async throws -> UserResponse {
        var body: [String: Any] = ["userId": userId]
        if let avatarUrl { body["avatarUrl"] = avatarUrl }
        if let bannerUrl { body["bannerUrl"] = bannerUrl }
        if let bio { body["bio"] = bio }
        
        if shouldRemovePinnedTrack {
            body["pinnedTrack"] = NSNull()
        } else if let pinnedTrack {
            let data = try JSONEncoder().encode(pinnedTrack)
            if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                body["pinnedTrack"] = dict
            }
        }
        
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        return try await executeWithFailover(
            path: "/api/user/profile",
            method: "PATCH",
            bodyData: bodyData,
            headers: ["Content-Type": "application/json"],
            as: UserResponse.self
        )
    }

    /// `GET /api/user/history?userId=...` — user's listening history.
    func recentTracks(userId: String) async throws -> [Track] {
        return try await executeWithFailover(
            path: "/api/user/history",
            queryItems: [
                URLQueryItem(name: "userId", value: userId)
            ],
            as: [Track].self
        )
    }

    /// `POST /api/user/history` — adds track to user play history on the server.
    func addTrackToHistory(userId: String, track: Track) async throws {
        let idPart = track.id.components(separatedBy: ":").last ?? track.id
        let sourcePart = track.source?.rawValue ?? "soundcloud"
        let trackDict: [String: Any] = [
            "id": idPart,
            "title": track.title,
            "artist": track.artist,
            "coverUrl": track.cover?.absoluteString ?? "",
            "duration": Int(track.durationSeconds ?? 0),
            "source": sourcePart
        ]
        let body: [String: Any] = [
            "userId": userId,
            "track": trackDict
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        _ = try await executeWithFailover(
            path: "/api/user/history",
            method: "POST",
            bodyData: bodyData,
            headers: ["Content-Type": "application/json"],
            as: SyncResponse.self
        )
    }

    /// `GET /api/comments?profileUserId=...` or `?trackId=...` — fetch comments.
    func fetchComments(profileUserId: String? = nil, trackId: String? = nil) async throws -> CommentsResponse {
        var queryItems: [URLQueryItem] = []
        if let profileUserId {
            queryItems.append(URLQueryItem(name: "profileUserId", value: profileUserId))
        }
        if let trackId {
            queryItems.append(URLQueryItem(name: "trackId", value: trackId))
        }
        return try await executeWithFailover(
            path: "/api/comments",
            queryItems: queryItems,
            as: CommentsResponse.self
        )
    }

    /// `POST /api/comments` — posts a comment.
    func postComment(
        authorId: String,
        content: String,
        profileUserId: String? = nil,
        trackId: String? = nil
    ) async throws -> CommentItem {
        var body: [String: Any] = [
            "authorId": authorId,
            "content": content
        ]
        if let profileUserId { body["profileUserId"] = profileUserId }
        if let trackId { body["trackId"] = trackId }
        
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        return try await executeWithFailover(
            path: "/api/comments",
            method: "POST",
            bodyData: bodyData,
            headers: ["Content-Type": "application/json"],
            as: CommentItem.self
        )
    }

    /// `DELETE /api/comments?id=...&userId=...` — deletes a comment.
    func deleteComment(commentId: String, userId: String) async throws {
        _ = try await executeWithFailover(
            path: "/api/comments",
            method: "DELETE",
            queryItems: [
                URLQueryItem(name: "id", value: commentId),
                URLQueryItem(name: "userId", value: userId)
            ],
            as: SyncResponse.self
        )
    }

    // MARK: - Failover & Request plumbing

    func rotateHost() {
        let currentHost = settings.backendURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextHost: String
        if let idx = APIConfig.hosts.firstIndex(of: currentHost) {
            let nextIdx = (idx + 1) % APIConfig.hosts.count
            nextHost = APIConfig.hosts[nextIdx]
        } else {
            nextHost = APIConfig.hosts[0]
        }
        settings.backendURL = nextHost
        DebugLogger.shared.append("[APIClient] Switched active host to: \(nextHost)")
    }

    private func executeWithFailover<T: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        bodyData: Data? = nil,
        headers: [String: String] = [:],
        as type: T.Type
    ) async throws -> T {
        var attempts = 0
        let maxAttempts = APIConfig.hosts.count
        var lastError: Error = APIError.invalidBackendURL
        
        while attempts < maxAttempts {
            let currentHost = settings.backendURL
            do {
                let components = try makeComponents(host: currentHost, path: path, queryItems: queryItems)
                guard let url = components.url else { throw APIError.invalidBackendURL }
                
                var req = URLRequest(url: url)
                req.cachePolicy = .reloadRevalidatingCacheData
                req.httpMethod = method
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                if method == "POST" {
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
                if !settings.yandexToken.isEmpty {
                    req.setValue(settings.yandexToken, forHTTPHeaderField: "x-yandex-token")
                }
                for (key, val) in headers {
                    req.setValue(val, forHTTPHeaderField: key)
                }
                if let bodyData {
                    req.httpBody = bodyData
                }
                
                let (data, response) = try await session.data(for: req)
                guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
                
                if http.statusCode >= 500 {
                    let preview = String(data: data.prefix(200), encoding: .utf8)
                    throw APIError.httpStatus(http.statusCode, preview)
                }
                
                guard (200..<300).contains(http.statusCode) else {
                    let bodyPreview = String(data: data.prefix(APIConfig.errorBodyLogLimit), encoding: .utf8)
                    throw APIError.httpStatus(http.statusCode, bodyPreview)
                }
                
                return try decoder.decode(T.self, from: data)
            } catch let error as APIError {
                if case .httpStatus(let status, _) = error, status < 500 {
                    throw error
                }
                lastError = error
                rotateHost()
                attempts += 1
            } catch {
                lastError = error
                rotateHost()
                attempts += 1
            }
        }
        throw lastError
    }
    /// `GET /api/music/recommend` — fetches recommended/similar tracks for track flow.
    func recommendTracks(id: String, source: String, title: String, artist: String, userId: String?) async throws -> [Track] {
        var queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "source", value: source),
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "artist", value: artist),
        ]
        if let userId, !userId.isEmpty {
            queryItems.append(URLQueryItem(name: "userId", value: userId))
        }
        
        let response = try await executeWithFailover(
            path: "/api/music/recommend",
            queryItems: queryItems,
            as: RecommendTracksResponse.self
        )
        return response.tracks
    }

    /// `GET /api/music/artist/followed?userId=...` — list of followed artists.
    func followedArtists(userId: String) async throws -> [FollowedArtistDTO] {
        return try await executeWithFailover(
            path: "/api/music/artist/followed",
            queryItems: [URLQueryItem(name: "userId", value: userId)],
            as: [FollowedArtistDTO].self
        )
    }

    private func makeComponents(host: String, path: String, queryItems: [URLQueryItem]) throws -> URLComponents {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = URL(string: trimmed),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidBackendURL
        }
        if components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        components.path += path
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components
    }
}

// MARK: - Errors

enum APIError: LocalizedError {
    case invalidBackendURL
    case invalidResponse
    case httpStatus(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidBackendURL:
            return "Некорректный URL бэкенда. Проверь Settings."
        case .invalidResponse:
            return "Сервер вернул неожиданный ответ."
        case .httpStatus(let code, _):
            return "Ошибка сервера (\(code))."
        }
    }
}
