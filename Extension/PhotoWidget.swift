import WidgetKit
import SwiftUI

// MARK: - Timeline

struct PhotoEntry: TimelineEntry {
    let date: Date
    let image: UIImage?
}

struct PhotoProvider: TimelineProvider {

    func placeholder(in context: Context) -> PhotoEntry {
        PhotoEntry(date: Date(), image: PhotoStore.loadImage())
    }

    func getSnapshot(in context: Context, completion: @escaping (PhotoEntry) -> Void) {
        completion(PhotoEntry(date: Date(), image: PhotoStore.loadImage()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PhotoEntry>) -> Void) {
        let entry = PhotoEntry(date: Date(), image: PhotoStore.loadImage())
        // Приложение само дёргает reloadTimelines после выбора фото,
        // это лишь страховка на случай, если система не обновит виджет.
        let refresh = Date().addingTimeInterval(6 * 60 * 60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

// MARK: - View

struct PhotoWidgetView: View {
    var entry: PhotoEntry

    var body: some View {
        GeometryReader { geo in
            content(size: geo.size)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
        // На iOS 16 у виджетов жёсткие внутренние поля, отрицательный padding
        // растягивает фото «от края до края».
        .padding(-16)
        .widgetURL(URL(string: "photowidget://pick"))
    }

    @ViewBuilder
    private func content(size: CGSize) -> some View {
        if let image = entry.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.16, green: 0.20, blue: 0.35),
                        Color(red: 0.05, green: 0.06, blue: 0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.system(size: 28, weight: .light))
                    Text("Выбери фото\nв приложении")
                        .font(.system(size: 11, weight: .medium))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white.opacity(0.8))
            }
            .frame(width: size.width, height: size.height)
        }
    }
}

// MARK: - Widget

struct PhotoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PhotoStore.widgetKind, provider: PhotoProvider()) { entry in
            PhotoWidgetView(entry: entry)
        }
        .configurationDisplayName("Фото")
        .description("Любое фото из галереи на рабочем столе.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
