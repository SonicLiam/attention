import SwiftUI

// MARK: - Markdown Renderer

struct MarkdownRendererView: View {
    let text: String

    var body: some View {
        if let attributed = MarkdownRenderer.render(text) {
            Text(attributed)
                .textSelection(.enabled)
        } else {
            Text(text)
                .textSelection(.enabled)
        }
    }
}

enum MarkdownRenderer {
    static func render(_ markdown: String) -> AttributedString? {
        // Use Apple's built-in Markdown parsing for AttributedString
        // then apply custom styling
        var result = AttributedString()
        let lines = markdown.components(separatedBy: "\n")
        var inCodeBlock = false
        var codeBlockContent = ""
        var isFirstLine = true

        for line in lines {
            // Handle code blocks
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCodeBlock {
                    // End code block
                    if !codeBlockContent.isEmpty {
                        var codeAttr = AttributedString(codeBlockContent)
                        codeAttr.font = .system(.body, design: .monospaced)
                        codeAttr.backgroundColor = Color.secondary.opacity(0.1)
                        if !isFirstLine {
                            result.append(AttributedString("\n"))
                        }
                        result.append(codeAttr)
                        isFirstLine = false
                    }
                    codeBlockContent = ""
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                    codeBlockContent = ""
                }
                continue
            }

            if inCodeBlock {
                if !codeBlockContent.isEmpty {
                    codeBlockContent += "\n"
                }
                codeBlockContent += line
                continue
            }

            if !isFirstLine {
                result.append(AttributedString("\n"))
            }
            isFirstLine = false

            let parsedLine = parseLine(line)
            result.append(parsedLine)
        }

        // Close unclosed code block
        if inCodeBlock && !codeBlockContent.isEmpty {
            var codeAttr = AttributedString(codeBlockContent)
            codeAttr.font = .system(.body, design: .monospaced)
            codeAttr.backgroundColor = Color.secondary.opacity(0.1)
            if !isFirstLine {
                result.append(AttributedString("\n"))
            }
            result.append(codeAttr)
        }

        return result
    }

    private static func parseLine(_ line: String) -> AttributedString {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Headings
        if trimmed.hasPrefix("### ") {
            let content = String(trimmed.dropFirst(4))
            var attr = parseInlineFormatting(content)
            attr.font = .system(.title3, weight: .bold)
            return attr
        } else if trimmed.hasPrefix("## ") {
            let content = String(trimmed.dropFirst(3))
            var attr = parseInlineFormatting(content)
            attr.font = .system(.title2, weight: .bold)
            return attr
        } else if trimmed.hasPrefix("# ") {
            let content = String(trimmed.dropFirst(2))
            var attr = parseInlineFormatting(content)
            attr.font = .system(.title, weight: .bold)
            return attr
        }

        // Bullet lists
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            let content = String(trimmed.dropFirst(2))
            var bullet = AttributedString("  \u{2022} ")
            bullet.font = .body
            let rest = parseInlineFormatting(content)
            bullet.append(rest)
            return bullet
        }

        // Numbered lists
        if let match = trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) {
            let prefix = String(trimmed[match])
            let content = String(trimmed[match.upperBound...])
            var numAttr = AttributedString("  \(prefix)")
            numAttr.font = .body
            let rest = parseInlineFormatting(content)
            numAttr.append(rest)
            return numAttr
        }

        return parseInlineFormatting(line)
    }

    private static func parseInlineFormatting(_ text: String) -> AttributedString {
        var result = AttributedString()
        var remaining = text[text.startIndex...]

        while !remaining.isEmpty {
            // Inline code
            if remaining.hasPrefix("`") {
                let afterTick = remaining.index(after: remaining.startIndex)
                if let endTick = remaining[afterTick...].firstIndex(of: "`") {
                    let codeText = String(remaining[afterTick..<endTick])
                    var codeAttr = AttributedString(codeText)
                    codeAttr.font = .system(.body, design: .monospaced)
                    codeAttr.backgroundColor = Color.secondary.opacity(0.1)
                    result.append(codeAttr)
                    remaining = remaining[remaining.index(after: endTick)...]
                    continue
                }
            }

            // Strikethrough ~~text~~
            if remaining.hasPrefix("~~") {
                let afterMarker = remaining.index(remaining.startIndex, offsetBy: 2)
                if let endRange = remaining[afterMarker...].range(of: "~~") {
                    let innerText = String(remaining[afterMarker..<endRange.lowerBound])
                    var attr = AttributedString(innerText)
                    attr.strikethroughStyle = .single
                    result.append(attr)
                    remaining = remaining[endRange.upperBound...]
                    continue
                }
            }

            // Bold **text**
            if remaining.hasPrefix("**") {
                let afterMarker = remaining.index(remaining.startIndex, offsetBy: 2)
                if let endRange = remaining[afterMarker...].range(of: "**") {
                    let innerText = String(remaining[afterMarker..<endRange.lowerBound])
                    var attr = AttributedString(innerText)
                    attr.font = .body.bold()
                    result.append(attr)
                    remaining = remaining[endRange.upperBound...]
                    continue
                }
            }

            // Italic *text*
            if remaining.hasPrefix("*") && !remaining.hasPrefix("**") {
                let afterMarker = remaining.index(after: remaining.startIndex)
                if let endIdx = remaining[afterMarker...].firstIndex(of: "*") {
                    let innerText = String(remaining[afterMarker..<endIdx])
                    var attr = AttributedString(innerText)
                    attr.font = .body.italic()
                    result.append(attr)
                    remaining = remaining[remaining.index(after: endIdx)...]
                    continue
                }
            }

            // Links [text](url)
            if remaining.hasPrefix("[") {
                let afterBracket = remaining.index(after: remaining.startIndex)
                if let closeBracket = remaining[afterBracket...].firstIndex(of: "]") {
                    let linkText = String(remaining[afterBracket..<closeBracket])
                    let afterClose = remaining.index(after: closeBracket)
                    if afterClose < remaining.endIndex && remaining[afterClose] == "(" {
                        let afterParen = remaining.index(after: afterClose)
                        if let closeParen = remaining[afterParen...].firstIndex(of: ")") {
                            let urlString = String(remaining[afterParen..<closeParen])
                            var attr = AttributedString(linkText)
                            if let url = URL(string: urlString) {
                                attr.link = url
                            }
                            attr.foregroundColor = Color.attentionPrimary
                            attr.underlineStyle = .single
                            result.append(attr)
                            remaining = remaining[remaining.index(after: closeParen)...]
                            continue
                        }
                    }
                }
            }

            // Plain character
            let char = remaining[remaining.startIndex]
            var charAttr = AttributedString(String(char))
            charAttr.font = .body
            result.append(charAttr)
            remaining = remaining[remaining.index(after: remaining.startIndex)...]
        }

        return result
    }
}

// MARK: - Markdown Editor View

struct MarkdownEditorView: View {
    @Binding var text: String
    @State private var isPreviewMode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Toggle bar
            HStack {
                Picker("Mode", selection: $isPreviewMode) {
                    Label("Edit", systemImage: "pencil").tag(false)
                    Label("Preview", systemImage: "eye").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)

                Spacer()
            }

            // Content
            if isPreviewMode {
                ScrollView {
                    VStack(alignment: .leading) {
                        if text.isEmpty {
                            Text("No notes")
                                .foregroundStyle(.tertiary)
                                .font(.body)
                        } else {
                            MarkdownRendererView(text: text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(8)
                }
                .frame(minHeight: 120)
                .background(
                    RoundedRectangle(cornerRadius: AttentionLayout.smallCornerRadius)
                        .fill(.quaternary.opacity(0.3))
                )
            } else {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: AttentionLayout.smallCornerRadius)
                            .fill(.quaternary.opacity(0.5))
                    )
            }
        }
    }
}
