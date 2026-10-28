import Foundation
import Testing

@testable import SpectrumCore

@Test func terminalCommandQuotesFolderAndPrompt() {
    let command = NewSession.shellCommand(
        directory: "/code/it's here", prompt: #"fix "auth" & $HOME"#)

    #expect(command == #"cd '/code/it'\''s here' && claude 'fix "auth" & $HOME'"#)
    #expect(
        NewSession.shellCommand(directory: "/code/app", prompt: nil) == "cd '/code/app' && claude")
}

@Test func appleScriptEscapesTheCommand() {
    let script = NewSession.appleScript(command: #"cd '/a' && claude 'say "hi" \ bye'"#)

    #expect(script.contains(#"do script "cd '/a' && claude 'say \"hi\" \\ bye'""#))
    #expect(script.contains("activate"))
}

@Test func recentProjectsComeFromTheNewestTranscripts() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let existing = root.appending(path: "real-project")
    try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)

    func transcript(_ folder: String, cwd: String, age: TimeInterval) throws {
        let directory = root.appending(path: folder)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "session.jsonl")
        try Data(
            """
            {"type":"summary","summary":"x"}
            {"type":"user","cwd":"\(cwd)","sessionId":"s"}

            """.utf8
        ).write(to: file)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: file.path)
    }
    try transcript("-old", cwd: existing.path, age: 3600)
    try transcript("-gone", cwd: "/nowhere/deleted", age: 10)
    try transcript("-new", cwd: root.path, age: 60)

    #expect(NewSession.recentProjects(in: root) == [root.path, existing.path])
}
