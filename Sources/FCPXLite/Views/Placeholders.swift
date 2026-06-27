import SwiftUI

struct PanelPlaceholder: View {
    let title: String
    var background: Color = Tokens.Palette.chrome
    var body: some View {
        ZStack {
            background
            Text(title).font(Tokens.Typeface.body).foregroundStyle(Tokens.Palette.textMuted)
        }
    }
}
