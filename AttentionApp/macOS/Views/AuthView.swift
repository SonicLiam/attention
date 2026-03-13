import SwiftUI

struct AuthView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var isLoginMode = true
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // Logo & Title
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.attentionPrimary)

                    Text("Attention")
                        .font(.largeTitle.weight(.bold))

                    Text(isLoginMode ? "Welcome back" : "Create your account")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Form
                VStack(spacing: 12) {
                    if !isLoginMode {
                        TextField("Display Name", text: $displayName)
                            .textFieldStyle(.roundedBorder)
                    }

                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)

                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(isLoginMode ? .password : .newPassword)
                        .onSubmit {
                            performAction()
                        }
                }
                .frame(maxWidth: 300)

                // Error
                if let error = authViewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.attentionDanger)
                        .multilineTextAlignment(.center)
                }

                // Action Button
                Button {
                    performAction()
                } label: {
                    if authViewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(isLoginMode ? "Sign In" : "Create Account")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.attentionPrimary)
                .frame(maxWidth: 300)
                .disabled(authViewModel.isLoading)
                .controlSize(.large)

                // Toggle mode
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
                .buttonStyle(.plain)
            }
            .padding(40)

            Spacer()
        }
        .frame(minWidth: 400, minHeight: 500)
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
