import AppKit
import SpectrumCore
import SwiftUI

/// Picks a project and an optional first prompt, then opens Claude Code there in Terminal.
struct NewSessionView: View {
    @Bindable var model: NotchModel

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    model.newSessionOpen = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                Text("New Claude Code session")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(folders, id: \.self) { path in
                    folderButton(path)
                }
                Button(action: model.onChooseFolder) {
                    Label("Other folder…", systemImage: "folder.badge.plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(.white.opacity(0.15), style: StrokeStyle(dash: [3]))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            promptBar
        }
    }

    /// Recent folders, plus one picked by hand that isn't among them.
    private var folders: [String] {
        guard let chosen = model.newSessionDirectory, !model.recentProjects.contains(chosen)
        else { return model.recentProjects }
        return [chosen] + model.recentProjects
    }

    private func folderButton(_ path: String) -> some View {
        let selected = model.newSessionDirectory == path
        return Button {
            model.newSessionDirectory = path
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? .black : .white)
                Text((path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(selected ? .black.opacity(0.6) : .white.opacity(0.4))
                    .truncationMode(.head)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? ClaudeLook.orange : .white.opacity(0.07))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var promptBar: some View {
        let placeholder = "What should Claude do? (optional)"
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if model.renderingStill {
                    Text(placeholder)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField(placeholder, text: $model.newSessionPrompt, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .lineLimit(1...3)
                        .onSubmit(model.startNewSession)
                }
                Button(action: model.startNewSession) {
                    Label("Open in Terminal", systemImage: "terminal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(ClaudeLook.orange))
                }
                .buttonStyle(.plain)
                .disabled(model.newSessionDirectory == nil)
            }
            .padding(.leading, 12)
            .padding(.trailing, 5)
            .padding(.vertical, 5)
            .background(Capsule().fill(.white.opacity(0.09)))
            if let error = model.newSessionError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: 0xF87171))
                    .lineLimit(1)
                    .padding(.leading, 12)
            }
        }
    }
}
