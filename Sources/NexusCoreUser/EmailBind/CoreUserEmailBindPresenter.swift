#if canImport(UIKit)
import UIKit

enum CoreUserEmailBindPresenter {
    static func show(
        presenting viewController: UIViewController,
        initialEmail: String?,
        onCancel: @escaping () -> Void,
        onSubmit: @escaping (String, String) -> Void
    ) {
        let alert = UIAlertController(
            title: "Bind Email",
            message: "Enter your email and set a password for future sign-in.",
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = "Email"
            textField.text = initialEmail
            textField.keyboardType = .emailAddress
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
            textField.clearButtonMode = .whileEditing
        }
        alert.addTextField { textField in
            textField.placeholder = "Password"
            textField.isSecureTextEntry = true
            textField.textContentType = .newPassword
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            onCancel()
        })
        alert.addAction(UIAlertAction(title: "Bind", style: .default) { _ in
            let email = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let password = alert.textFields?.dropFirst().first?.text ?? ""
            onSubmit(email, password)
        })
        viewController.present(alert, animated: true)
    }
}
#endif
