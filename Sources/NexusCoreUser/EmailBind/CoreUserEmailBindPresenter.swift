#if canImport(UIKit)
import UIKit

enum CoreUserEmailBindPresenter {
    static func show(
        presenting viewController: UIViewController,
        initialEmail: String?,
        onCancel: @escaping () -> Void,
        onSubmit: @escaping (String) -> Void
    ) {
        let alert = UIAlertController(
            title: "Bind Email",
            message: "Enter your email to keep your account and benefits available across products.",
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
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            onCancel()
        })
        alert.addAction(UIAlertAction(title: "Bind", style: .default) { _ in
            let email = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            onSubmit(email)
        })
        viewController.present(alert, animated: true)
    }
}
#endif
