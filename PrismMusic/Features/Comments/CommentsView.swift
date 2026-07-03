//
//  CommentsView.swift
//  PrismMusic
//
//  Reusable comments view that matches the Next.js `comments-section.tsx` functionality.
//  Supports:
//   - Steam-style profile wall comments and Player track comments.
//   - Composing comments (maximum 500 characters).
//   - Deleting comments (allowed for author, wall owner, or admin).
//   - Gradients for premium badges, nice avatars, and relative time calculation.
//   - Two styling modes: `.card` (for profile pages) and `.overlay` (for now playing panel).
//

import SwiftUI

struct CommentsView: View {
    @Environment(AppState.self) private var app

    enum Kind {
        case profile, track
    }

    enum Variant {
        case card, overlay
    }

    let kind: Kind
    let targetId: String
    let profileOwnerId: String?
    let variant: Variant

    @State private var comments: [CommentItem] = []
    @State private var total = 0
    @State private var isLoading = false
    @State private var draft = ""
    @State private var isSending = false
    @State private var deletingCommentId: String?

    private let maxContentLength = 500

    init(kind: Kind, targetId: String, profileOwnerId: String? = nil, variant: Variant = .card) {
        self.kind = kind
        self.targetId = targetId
        self.profileOwnerId = profileOwnerId
        self.variant = variant
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Comment Composer
            if app.settings.isLoggedIn {
                composerSection
            } else {
                HStack {
                    Spacer()
                    Text("Войдите в аккаунт, чтобы оставлять комментарии")
                        .font(Theme.Typography.secondary)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding(.vertical, 12)
            }

            // Comments List
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(.white)
                    Spacer()
                }
                .padding(.vertical, 24)
            } else if comments.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.Palette.textTertiary)
                    
                    Text(kind == .profile ? "Здесь пока тихо. Оставьте первый комментарий!" : "Комментариев ещё нет — будьте первым!")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                VStack(spacing: 12) {
                    ForEach(comments) { comment in
                        commentRow(comment)
                    }
                    
                    if total > comments.count {
                        Text("Показаны последние \(comments.count) из \(total)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.Palette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .task(id: targetId) {
            await loadComments()
        }
    }

    // MARK: - Composer

    private var composerSection: some View {
        HStack(alignment: .top, spacing: 10) {
            // User Avatar
            userAvatar(urlStr: app.profile.stats?.avatarUrl)
            
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    TextField(kind == .profile ? "Оставить комментарий в профиле..." : "Что думаете об этом треке?", text: $draft, axis: .vertical)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .padding(.bottom, 22) // Space for count
                        .background(variant == .overlay ? Color.white.opacity(0.06) : Color.white.opacity(0.03))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                        .onChange(of: draft) { _, newValue in
                            if newValue.count > maxContentLength {
                                draft = String(newValue.prefix(maxContentLength))
                            }
                        }
                    
                    // Character count
                    Text("\(draft.count)/\(maxContentLength)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .padding(.trailing, 10)
                        .padding(.bottom, 6)
                }
                
                // Submit Button
                HStack {
                    Spacer()
                    
                    Button {
                        submitComment()
                    } label: {
                        HStack(spacing: 6) {
                            if isSending {
                                ProgressView()
                                    .tint(variant == .overlay ? .black : .white)
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 11))
                            }
                            Text("Отправить")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(variant == .overlay ? .black : .white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(variant == .overlay ? Color.white : Color.white.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
            }
        }
    }

    // MARK: - Comment Row

    private func commentRow(_ comment: CommentItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Author Avatar
            userAvatar(urlStr: comment.author.avatarUrl)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 6) {
                    Text(comment.author.username)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    
                    if let role = comment.author.role, role != "user" {
                        Text(role == "premium" ? "PLUS" : role.uppercased())
                            .font(.system(size: 7, weight: .black))
                            .foregroundStyle(role == "premium" ? .yellow : .black)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                role == "premium" ? Color.yellow.opacity(0.15) : (role == "admin" ? Color.red : Color.emerald),
                                in: RoundedRectangle(cornerRadius: 3)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(role == "premium" ? Color.yellow.opacity(0.3) : Color.clear, lineWidth: 0.5)
                            )
                    }

                    Text(formatRelativeTime(comment.createdAt))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }

                Text(comment.content)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            // Trash moderator delete button
            if canDelete(comment) {
                Button {
                    deleteComment(comment)
                } label: {
                    ZStack {
                        if deletingCommentId == comment.id {
                            ProgressView()
                                .tint(.red)
                        } else {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                        }
                    }
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                }
                .foregroundStyle(Theme.Palette.textTertiary)
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(Color.white.opacity(0.01))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func userAvatar(urlStr: String?) -> some View {
        ZStack {
            if let urlStr, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Color.white.opacity(0.05)
                    }
                }
            } else {
                Color.white.opacity(0.08)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    )
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
    }

    // MARK: - Logic Helpers

    private func canDelete(_ comment: CommentItem) -> Bool {
        guard app.settings.isLoggedIn else { return false }
        let currentUserId = app.settings.userId
        
        // 1. Author of the comment
        if comment.author.id == currentUserId { return true }
        // 2. Owner of the profile wall (Steam-style moderation)
        if kind == .profile && profileOwnerId == currentUserId { return true }
        // 3. Admin user role
        if app.settings.role == "admin" { return true }
        
        return false
    }

    private func loadComments() async {
        isLoading = true
        do {
            let res = try await app.api.fetchComments(
                profileUserId: kind == .profile ? targetId : nil,
                trackId: kind == .track ? targetId : nil
            )
            self.comments = res.comments
            self.total = res.total
        } catch {
            print("[CommentsView] Failed to load comments: \(error)")
        }
        isLoading = false
    }

    private func submitComment() {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, isSending == false else { return }
        isSending = true
        
        Task {
            do {
                let comment = try await app.api.postComment(
                    authorId: app.settings.userId,
                    content: content,
                    profileUserId: kind == .profile ? targetId : nil,
                    trackId: kind == .track ? targetId : nil
                )
                withAnimation {
                    self.comments.insert(comment, at: 0)
                    self.total += 1
                    self.draft = ""
                }
            } catch {
                app.audio.errorMessage = error.localizedDescription
                app.audio.showError = true
            }
            isSending = false
        }
    }

    private func deleteComment(_ comment: CommentItem) {
        guard deletingCommentId == nil else { return }
        deletingCommentId = comment.id
        
        Task {
            do {
                try await app.api.deleteComment(commentId: comment.id, userId: app.settings.userId)
                withAnimation {
                    self.comments.removeAll { $0.id == comment.id }
                    self.total = max(0, self.total - 1)
                }
            } catch {
                app.audio.errorMessage = error.localizedDescription
                app.audio.showError = true
            }
            deletingCommentId = nil
        }
    }

    private func formatRelativeTime(_ dateStr: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: dateStr) else { return "недавно" }
        
        let diff = Date().timeIntervalSince(date)
        let minutes = Int(diff / 60)
        if minutes < 1 { return "только что" }
        if minutes < 60 { return "\(minutes) мин назад" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) ч назад" }
        let days = hours / 24
        if days < 7 { return "\(days) дн назад" }
        
        let outFormatter = DateFormatter()
        outFormatter.locale = Locale(identifier: "ru_RU")
        outFormatter.dateFormat = "d MMM yyyy"
        return outFormatter.string(from: date)
    }
}
