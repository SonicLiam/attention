import SwiftUI

struct iOSAuthView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var isLoginMode = true
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Logo & Title
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(Color.attentionPrimary)

                        Text("Attention")
                            .font(.largeTitle.weight(.bold))

                        Text(isLoginMode ? "Welcome back" : "Create your account")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)

                    // Form Fields
                    VStack(spacing: 16) {
                        if !isLoginMode {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Display Name")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                                TextField("Your name", text: $displayName)
                                    .textFieldStyle(.roundedBorder)
                                    .textContentType(.name)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Email")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            TextField("email@example.com", text: $email)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            SecureField("At least 8 characters", text: $password)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(isLoginMode ? .password : .newPassword)
                                .onSubmit {
                                    performAction()
                                }
                        }
                    }
                    .padding(.horizontal, 24)

                    // Error
                    if let error = authViewModel.errorMessage {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(Color.attentionDanger)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    // Action Button
                    VStack(spacing: 16) {
                        Button {
                            performAction()
                        } label: {
                            if authViewModel.isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                            } else {
                                Text(isLoginMode ? "Sign In" : "Create Account")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.attentionPrimary)
                        .disabled(authViewModel.isLoading)
                        .controlSize(.large)

                        Button {
                            withAnimation {
                                isLoginMode.toggle()
                                authViewModel.errorMessage = nil
                            }
                        } label: {
                            Text(isLoginMode ? "Don't have an account? Sign up" : "Already have an account? Sign in")
                                .font(.subheadline)
                                .foregroundStyle(Color.attentionPrimary)
                        }
                    }
                    .padding(.horizontal, 24)

                    Spacer()
                }
            }
        }
    }

    private func performAction() {
        Task {
            if isLoginMode {
                await authViewModel.login(email: email, password: password)
            } else {
                await authViewModel.register(email: email, password: password, displayName: displayName)
            }
        }
    }
}
