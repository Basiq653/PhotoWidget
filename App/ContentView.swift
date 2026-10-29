import SwiftUI
import PhotosUI
import WidgetKit

struct ContentView: View {

    @State private var pickedItem: PhotosPickerItem?
    @State private var preview: UIImage?
    @State private var status: String = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            List {
                previewSection
                actionsSection
                helpSection
                diagnosticsSection
            }
            .navigationTitle("Фото-виджет")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { preview = PhotoStore.loadImage() }
        .onChange(of: pickedItem) { item in
            guard let item else { return }
            load(item)
        }
    }

    // MARK: - Секции

    private var previewSection: some View {
        Section {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))

                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 36, weight: .light))
                        Text("Фото пока не выбрано")
                            .font(.footnote)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(height: 260)
            .listRowInsets(EdgeInsets())
            .padding(.vertical, 6)
        }
    }

    private var actionsSection: some View {
        Section {
            PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                Label("Выбрать фото из галереи", systemImage: "photo.badge.plus")
            }

            if preview != nil {
                Button(role: .destructive) {
                    PhotoStore.clear()
                    preview = nil
                    WidgetCenter.shared.reloadAllTimelines()
                    status = "Фото удалено."
                } label: {
                    Label("Убрать фото", systemImage: "trash")
                }
            }

            if busy {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Сохраняю…").font(.footnote).foregroundStyle(.secondary)
                }
            }

            if !status.isEmpty {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var helpSection: some View {
        Section("Как поставить виджет") {
            Text("1. Выбери фото здесь.")
            Text("2. Зажми пустое место на рабочем столе → «Изменить экран».")
            Text("3. Нажми «+» в левом верхнем углу и найди «Фото-виджет».")
            Text("4. Выбери размер (маленький / средний / большой) → «Добавить виджет».")
            Text("Если виджета нет в списке — сделай respring и открой приложение ещё раз.")
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
    }

    private var diagnosticsSection: some View {
        Section("Диагностика") {
            ForEach(PhotoStore.diagnostics()) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(row.value)
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Логика

    private func load(_ item: PhotosPickerItem) {
        busy = true
        status = ""

        Task {
            let data = try? await item.loadTransferable(type: Data.self)

            await MainActor.run {
                if let data, let image = UIImage(data: data) {
                    let saved = PhotoStore.save(image)
                    preview = PhotoStore.loadImage()
                    WidgetCenter.shared.reloadTimelines(ofKind: PhotoStore.widgetKind)
                    WidgetCenter.shared.reloadAllTimelines()
                    status = saved
                        ? "Сохранено. Виджет обновится в течение нескольких секунд."
                        : "Не удалось записать файл — смотри «Диагностику» ниже."
                } else {
                    status = "Не удалось прочитать выбранное фото."
                }

                busy = false
                pickedItem = nil
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
