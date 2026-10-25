import Foundation

/// Links such as `tg://msg_url?url=…&text=…`, `tg://msg?to=…&text=…` and `t.me/share/url` open a message that someone else
/// wrote, ready to send. Worms spread through them: the text is the link itself, and the user is asked to send it on. The
/// guard keeps the user from opening such a message without seeing what it says, and who it goes to.
///
/// A confirmed link is remembered for one re-entry: the confirmation re-opens the same link, which must go through once.
enum ForkShareLinkGuard {
    private static var approved: Set<String> = []

    static func key(url: String?, text: String?, to: String?) -> String {
        return "\(url ?? "")\u{1}\(text ?? "")\u{1}\(to ?? "")"
    }

    static func approve(_ key: String) {
        self.approved.insert(key)
    }

    /// True once, after the user confirmed this exact link.
    static func consumeApproval(_ key: String) -> Bool {
        return self.approved.remove(key) != nil
    }

    /// What the alert shows: the text and address, cut so that a very long link cannot push the buttons off screen.
    static func message(url: String?, text: String?, to: String?, russian: Bool) -> String {
        func shortened(_ value: String) -> String {
            let limit = 400
            return value.count > limit ? String(value.prefix(limit)) + "…" : value
        }
        var lines: [String] = []
        if russian {
            lines.append("Эта ссылка открывает готовое сообщение. Если оно просит переслать его контактам или перейти по другой ссылке, это может быть вредоносная рассылка.")
            if let to, !to.isEmpty {
                lines.append("Кому: \(shortened(to))")
            }
            if let url, !url.isEmpty {
                lines.append("Ссылка: \(shortened(url))")
            }
            if let text, !text.isEmpty {
                lines.append("Текст: \(shortened(text))")
            }
        } else {
            lines.append("This link opens a ready-made message. If it asks you to forward it to your contacts or to open another link, it may be a malicious chain message.")
            if let to, !to.isEmpty {
                lines.append("To: \(shortened(to))")
            }
            if let url, !url.isEmpty {
                lines.append("Link: \(shortened(url))")
            }
            if let text, !text.isEmpty {
                lines.append("Text: \(shortened(text))")
            }
        }
        return lines.joined(separator: "\n\n")
    }
}
