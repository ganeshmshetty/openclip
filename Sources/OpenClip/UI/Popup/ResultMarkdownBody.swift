// ResultMarkdownBody.swift
// OpenClip
//
// Markdown-rendered body for AI result cards. Display-only: copy, paste and drag keep using
// payload.text, so the Markdown source is what leaves the card. The theme keeps the card's
// 13.5pt body size and tones the stock heading scale down to popup proportions.
import SwiftUI
import MarkdownUI

struct ResultMarkdownBody: View {
    let text: String

    var body: some View {
        Markdown(text)
            .markdownTheme(Self.cardTheme())
            .markdownTextStyle {
                FontSize(13.5)
            }
            .textSelection(.enabled)
    }

    private static func cardTheme() -> Theme {
        Theme.basic
        .heading1 { configuration in
            configuration.label
                .markdownMargin(top: .em(0.8), bottom: .em(0.5))
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.4))
                }
        }
        .heading2 { configuration in
            configuration.label
                .markdownMargin(top: .em(0.8), bottom: .em(0.5))
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.25))
                }
        }
        .heading3 { configuration in
            configuration.label
                .markdownMargin(top: .em(0.6), bottom: .em(0.4))
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.1))
                }
        }
        .heading4 { configuration in
            configuration.label
                .markdownMargin(top: .em(0.6), bottom: .em(0.4))
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1))
                }
        }
        .heading5 { configuration in
            configuration.label
                .markdownMargin(top: .em(0.5), bottom: .em(0.3))
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(0.95))
                }
        }
        .heading6 { configuration in
            configuration.label
                .markdownMargin(top: .em(0.5), bottom: .em(0.3))
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(0.9))
                }
        }
    }
}