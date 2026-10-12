import SwiftUI

/// Licenses for third-party material that ships inside the app. The app icon's glyph is a modified
/// Tabler Icons `body-scan`, whose MIT license requires its notice to travel with every copy.
/// Keep this text in sync with THIRD_PARTY_NOTICES.md.
struct AcknowledgementsView: View {
    @Environment(\.dismiss) private var dismiss

    private static let tablerURL = "https://github.com/tabler/tabler-icons"

    private static let tablerLicense = """
        MIT License

        Copyright (c) 2020-2026 Paweł Kuna

        Permission is hereby granted, free of charge, to any person obtaining a copy \
        of this software and associated documentation files (the "Software"), to deal \
        in the Software without restriction, including without limitation the rights \
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
        copies of the Software, and to permit persons to whom the Software is \
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all \
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE \
        SOFTWARE.
        """

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Tabler Icons")
                        .font(.title3.weight(.semibold))
                    Text("The app icon is a modified version of the Tabler Icons \u{201C}body-scan\u{201D} glyph.")
                        .font(.body)
                    // Plain text rather than a link: the app never opens network connections.
                    Text(Self.tablerURL)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(Self.tablerLicense)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)))
                }
                .padding(20)
            }
            .navigationTitle("Acknowledgements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("acknowledgementsDoneButton")
                }
            }
        }
    }
}
