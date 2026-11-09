import UIKit
import WebKit
import PhotosUI
import UniformTypeIdentifiers

/// Bridges the page's file inputs to the system pickers.
///
/// WKWebView drops `runOpenPanelWith` unless a `WKUIDelegate` implements it, so
/// without this the attachment button does nothing at all. `WKOpenPanelParameters`
/// does not expose the accepted file types, so the user chooses between photos
/// and documents.
final class FilePicker: NSObject, UIDocumentPickerDelegate, PHPickerViewControllerDelegate {
    private let completion: ([URL]?) -> Void
    private let lock = NSLock()
    private var picked: [URL] = []
    private var finished = false

    /// Delegates are not retained by the presented controllers.
    private static var active: [FilePicker] = []

    private init(completion: @escaping ([URL]?) -> Void) {
        self.completion = completion
    }

    static func present(
        from presenter: UIViewController,
        allowsMultiple: Bool,
        completion: @escaping ([URL]?) -> Void
    ) {
        let picker = FilePicker(completion: completion)
        active.append(picker)

        let sheet = UIAlertController(title: "添加附件", message: nil, preferredStyle: .actionSheet)

        sheet.addAction(UIAlertAction(title: "照片", style: .default) { _ in
            var config = PHPickerConfiguration()
            config.filter = .images
            config.selectionLimit = allowsMultiple ? 0 : 1
            let controller = PHPickerViewController(configuration: config)
            controller.delegate = picker
            presenter.present(controller, animated: true)
        })

        sheet.addAction(UIAlertAction(title: "文件", style: .default) { _ in
            let controller = UIDocumentPickerViewController(
                forOpeningContentTypes: [.item],
                asCopy: true
            )
            controller.allowsMultipleSelection = allowsMultiple
            controller.delegate = picker
            presenter.present(controller, animated: true)
        })

        sheet.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
            picker.finish(nil)
        })

        if let popover = sheet.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.maxY - 1,
                width: 1,
                height: 1
            )
        }

        presenter.present(sheet, animated: true)
    }

    // MARK: - Documents

    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        finish(urls.isEmpty ? nil : urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finish(nil)
    }

    // MARK: - Photos

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else {
            finish(nil)
            return
        }

        let group = DispatchGroup()
        for result in results {
            let provider = result.itemProvider
            guard let type = provider.registeredTypeIdentifiers.first else { continue }
            group.enter()
            provider.loadFileRepresentation(forTypeIdentifier: type) { [weak self] url, _ in
                defer { group.leave() }
                guard let self, let url else { return }
                // The provider's file is removed as soon as this returns, so keep a copy.
                let name = UUID().uuidString + "-" + url.lastPathComponent
                let destination = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                do {
                    try FileManager.default.copyItem(at: url, to: destination)
                    self.lock.lock()
                    self.picked.append(destination)
                    self.lock.unlock()
                } catch {}
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let urls = self.picked
            self.lock.unlock()
            self.finish(urls.isEmpty ? nil : urls)
        }
    }

    // MARK: - Completion

    private func finish(_ urls: [URL]?) {
        guard !finished else { return }
        finished = true
        completion(urls)
        FilePicker.active.removeAll { $0 === self }
    }
}
