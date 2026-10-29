import Foundation
import UIKit

/// Единое хранилище выбранного фото.
///
/// Приложение и widget-extension лежат в одном бандле, но на джейлбрейке
/// (Dopamine, rootless) они запускаются без песочницы, поэтому проще всего
/// держать картинку по общему абсолютному пути. Резервно копируем файл внутрь
/// бандла расширения — этот путь читается даже если расширение окажется в песочнице.
enum PhotoStore {

    static let widgetKind = "PhotoWidget"

    static let sharedDirectory = "/var/mobile/Library/PhotoWidget"
    static let sharedPhotoPath = sharedDirectory + "/photo.jpg"

    /// Бандл того таргета, который сейчас исполняется (приложение или расширение).
    private static var ownBundle: Bundle { Bundle(for: BundleToken.self) }

    /// `photo.jpg` внутри бандла расширения — этот путь читается даже из песочницы.
    /// Из приложения путь указывает в PlugIns/PhotoWidgetExt.appex, из расширения — в свой бандл.
    static var appexPhotoPath: String {
        let url = ownBundle.bundleURL
        if url.pathExtension == "appex" {
            return url.appendingPathComponent("photo.jpg").path
        }
        return url.appendingPathComponent("PlugIns/PhotoWidgetExt.appex/photo.jpg").path
    }

    private static var candidates: [String] {
        [sharedPhotoPath, appexPhotoPath]
    }

    // MARK: - Чтение

    static func loadImage() -> UIImage? {
        for path in candidates {
            if let image = UIImage(contentsOfFile: path) {
                return image
            }
        }
        return nil
    }

    static func imageExists() -> Bool {
        candidates.contains { FileManager.default.fileExists(atPath: $0) }
    }

    // MARK: - Запись

    @discardableResult
    static func save(_ image: UIImage) -> Bool {
        let prepared = image.normalized(maxDimension: 2048)
        guard let data = prepared.jpegData(compressionQuality: 0.92) else { return false }

        var saved = false
        let fm = FileManager.default

        // 1) общий путь (основной)
        do {
            try fm.createDirectory(atPath: sharedDirectory,
                                   withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o755])
            try data.write(to: URL(fileURLWithPath: sharedPhotoPath), options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: sharedPhotoPath)
            saved = true
        } catch {
            NSLog("[PhotoWidget] shared save failed: \(error)")
        }

        // 2) копия в бандл расширения (страховка, если он всё-таки в песочнице)
        let appexDir = (appexPhotoPath as NSString).deletingLastPathComponent
        if fm.isWritableFile(atPath: appexDir) {
            try? data.write(to: URL(fileURLWithPath: appexPhotoPath), options: .atomic)
        }

        return saved
    }

    static func clear() {
        let fm = FileManager.default
        for path in candidates {
            try? fm.removeItem(atPath: path)
        }
    }

    // MARK: - Диагностика (показывается в приложении)

    struct PhotoDiagnostic: Identifiable {
        let id = UUID()
        let path: String
        let value: String
    }

    static func diagnostics() -> [PhotoDiagnostic] {
        let fm = FileManager.default
        var rows: [PhotoDiagnostic] = []

        rows.append(PhotoDiagnostic(
            path: "Песочница",
            value: "app: \(ProcessInfo.processInfo.environment["HOME"] ?? "?")"
        ))

        for path in candidates {
            if fm.fileExists(atPath: path) {
                let attrs = try? fm.attributesOfItem(atPath: path)
                let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
                let readable = fm.isReadableFile(atPath: path) ? "читается" : "нет доступа"
                rows.append(PhotoDiagnostic(path: path, value: "есть, \(size / 1024) КБ, \(readable)"))
            } else {
                let writable = fm.isWritableFile(atPath: (path as NSString).deletingLastPathComponent)
                rows.append(PhotoDiagnostic(path: path, value: writable ? "нет файла (папка доступна для записи)" : "нет файла (папка недоступна)"))
            }
        }

        return rows
    }
}

final class BundleToken {}

extension UIImage {

    /// Приводит картинку к разумному размеру и «сжигает» EXIF-ориентацию.
    func normalized(maxDimension: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > 0 else { return self }

        let ratio = maxSide > maxDimension ? maxDimension / maxSide : 1
        let target = CGSize(width: floor(size.width * ratio), height: floor(size.height * ratio))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
