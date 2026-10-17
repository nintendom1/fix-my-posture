import UIKit

protocol ImageStoring {
    func saveImage(_ image: UIImage, filename: String) throws -> String
    func loadImage(relativePath: String) -> UIImage?
    func deleteImage(relativePath: String)
}

extension ImageStoring {
    func saveImage(_ image: UIImage) throws -> String {
        try saveImage(image, filename: "\(UUID().uuidString).jpeg")
    }
}

struct ImageStoreAdapter: ImageStoring {
    private let store: ImageStore

    init(store: ImageStore = .shared) {
        self.store = store
    }

    func saveImage(_ image: UIImage, filename: String = "\(UUID().uuidString).jpeg") throws -> String {
        try store.saveImage(image, filename: filename)
    }

    func loadImage(relativePath: String) -> UIImage? {
        store.loadImage(relativePath: relativePath)
    }

    func deleteImage(relativePath: String) {
        store.deleteImage(relativePath: relativePath)
    }
}
