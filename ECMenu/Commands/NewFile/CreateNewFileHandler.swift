/**
 通过注入的模板读取入口取得内容，再调用新文件写入边界完成创建。
 定义写入能力并连接命令执行与结果反馈，模板库状态由模板能力持有。
 */

import Foundation

nonisolated struct NewFileWriter: Sendable {
    let create: @Sendable (Data, URL) throws -> URL
}

/// 读取一次当前模板快照，然后完成排他创建；反馈不参与文件写入。
@MainActor
struct CreateNewFileHandler: ContextCommandHandling {
    private let readTemplate: @Sendable (FileTemplateID) async throws -> FileTemplateContent
    private let writer: NewFileWriter
    private let feedback: @MainActor @Sendable (CreateNewFileOutcome, UUID) -> Void

    nonisolated init(
        readTemplate: @escaping @Sendable (FileTemplateID) async throws -> FileTemplateContent,
        writer: NewFileWriter,
        present: @escaping @MainActor @Sendable (CreateNewFileOutcome, UUID) -> Void
    ) {
        self.readTemplate = readTemplate
        self.writer = writer
        feedback = present
    }

    @concurrent nonisolated func execute(
        _ command: CreateNewFileCommand
    ) async -> CreateNewFileOutcome {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let content: FileTemplateContent
        do {
            content = try await readTemplate(command.templateID)
        } catch {
            return .failure(.template(
                command.templateID,
                SystemErrorSnapshot(capturing: error)
            ))
        }

        do {
            let preferredURL = command.directoryPath.url
                .appendingPathComponent(content.template.defaultFileName)
            let fileURL = try writer.create(content.data, preferredURL)
            return .success(CreateNewFileSuccess(
                fileURL: fileURL,
                elapsedMilliseconds: (DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
            ))
        } catch {
            return .failure(.destination(
                directoryURL: command.directoryPath.url,
                systemError: SystemErrorSnapshot(capturing: error)
            ))
        }
    }

    func present(_ outcome: CreateNewFileOutcome, requestID: UUID) {
        feedback(outcome, requestID)
    }
}
