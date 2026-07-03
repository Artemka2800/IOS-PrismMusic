import SwiftUI

struct AccountView: View {
    @Environment(AppState.self) private var app
    
    enum AuthMode {
        case login, register
    }
    @State private var authMode: AuthMode = .login
    @State private var usernameDraft: String = ""
    @State private var passwordDraft: String = ""
    @State private var isAuthenticating = false
    @State private var authError: String = ""
    @State private var syncFlash = false
    @State private var showCheckoutSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                ImmersiveBackground()
                    .ignoresSafeArea()

                if app.settings.isLoggedIn {
                    ProfileView(userId: app.settings.userId)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            header
                            authCard
                        }
                        .padding(.horizontal, Theme.Layout.screenInset)
                        .padding(.top, 20)
                        .padding(.bottom, 140)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationBarHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showCheckoutSheet) {
                PlategaCheckoutView()
            }
            .navigationDestination(for: Album.self) { album in
                PlaylistDetailView(album: album)
            }
            .navigationDestination(for: ArtistDestination.self) { dest in
                ArtistView(destination: dest)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Аккаунт")
                .font(Theme.Typography.largeTitle)
                .foregroundStyle(.white)
            Text(app.settings.isLoggedIn ? "Управление профилем PrismMusic" : "Войдите или зарегистрируйтесь")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(.top, 12)
    }



    private var authCard: some View {
        VStack(spacing: 16) {
            Picker("Режим", selection: $authMode) {
                Text("Вход").tag(AuthMode.login)
                Text("Регистрация").tag(AuthMode.register)
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 4)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Имя пользователя")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                TextField("username", text: $usernameDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
                    .foregroundStyle(.white)
                    .tint(.white)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Пароль")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                SecureField("••••••••", text: $passwordDraft)
                    .padding(12)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
                    .foregroundStyle(.white)
                    .tint(.white)
            }
            
            if !authError.isEmpty {
                Text(authError)
                    .font(Theme.Typography.secondary)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                performAuth()
            } label: {
                HStack {
                    Spacer()
                    if isAuthenticating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(authMode == .login ? "Войти" : "Зарегистрироваться")
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
                .padding()
                .background(usernameDraft.isEmpty || passwordDraft.isEmpty ? Color.white.opacity(0.06) : Color.white.opacity(0.12))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .disabled(usernameDraft.isEmpty || passwordDraft.isEmpty || isAuthenticating)
        }
        .padding()
        .prismGlass(cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func performAuth() {
        isAuthenticating = true
        authError = ""
        
        Task {
            do {
                let response: UserResponse
                if authMode == .login {
                    response = try await app.api.login(
                        username: usernameDraft.trimmingCharacters(in: .whitespacesAndNewlines),
                        password: passwordDraft
                    )
                } else {
                    response = try await app.api.register(
                        username: usernameDraft.trimmingCharacters(in: .whitespacesAndNewlines),
                        password: passwordDraft
                    )
                }
                
                // Success! Save details
                app.settings.userId = response.id
                app.settings.username = response.username
                if let role = response.role {
                    app.settings.role = role
                } else {
                    app.settings.role = "free"
                }
                if let serverYandexToken = response.token, !serverYandexToken.isEmpty {
                    app.settings.yandexToken = serverYandexToken
                }
                
                // Clear draft inputs
                usernameDraft = ""
                passwordDraft = ""
                authError = ""
                
                // Sync library likes
                await app.library.syncWithServer()
                
            } catch {
                if case APIError.httpStatus(let code, let preview) = error {
                    if let preview = preview,
                       let previewData = preview.data(using: .utf8),
                       let errObj = try? JSONSerialization.jsonObject(with: previewData) as? [String: Any],
                       let errMsg = errObj["error"] as? String {
                        authError = errMsg
                    } else {
                        authError = "Неверный логин или пароль (код \(code))"
                    }
                } else {
                    authError = error.localizedDescription
                }
            }
            isAuthenticating = false
        }
    }
}
