import SwiftUI

enum RetroPalette {
    static let desktop = Color(red: 0.43, green: 0.45, blue: 0.46)
    static let chrome = Color(red: 0.82, green: 0.82, blue: 0.79)
    static let paper = Color(red: 0.91, green: 0.90, blue: 0.86)
    static let field = Color(red: 0.97, green: 0.96, blue: 0.91)
    static let ink = Color(red: 0.08, green: 0.09, blue: 0.09)
    static let darkEdge = Color(red: 0.18, green: 0.19, blue: 0.19)
    static let midEdge = Color(red: 0.48, green: 0.49, blue: 0.47)
    static let highlight = Color.white.opacity(0.86)
    static let cyan = Color(red: 0.03, green: 0.72, blue: 0.73)
    static let green = Color(red: 0.20, green: 0.66, blue: 0.34)
    static let amber = Color(red: 0.91, green: 0.59, blue: 0.12)
    static let red = Color(red: 0.78, green: 0.20, blue: 0.18)
}

extension Font {
    static func retro(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

struct RaisedBorder: ViewModifier {
    var emphasized = false

    func body(content: Content) -> some View {
        content
            .background(RetroPalette.chrome)
            .overlay(alignment: .top) { Rectangle().fill(RetroPalette.highlight).frame(height: emphasized ? 2 : 1) }
            .overlay(alignment: .leading) { Rectangle().fill(RetroPalette.highlight).frame(width: emphasized ? 2 : 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(RetroPalette.darkEdge).frame(height: emphasized ? 2 : 1) }
            .overlay(alignment: .trailing) { Rectangle().fill(RetroPalette.darkEdge).frame(width: emphasized ? 2 : 1) }
    }
}

struct InsetBorder: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(RetroPalette.field)
            .overlay(alignment: .top) { Rectangle().fill(RetroPalette.darkEdge).frame(height: 1) }
            .overlay(alignment: .leading) { Rectangle().fill(RetroPalette.darkEdge).frame(width: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(RetroPalette.highlight).frame(height: 1) }
            .overlay(alignment: .trailing) { Rectangle().fill(RetroPalette.highlight).frame(width: 1) }
    }
}

extension View {
    func raisedBorder(emphasized: Bool = false) -> some View { modifier(RaisedBorder(emphasized: emphasized)) }
    func insetBorder() -> some View { modifier(InsetBorder()) }
}

struct RetroButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.retro(12, weight: .semibold))
            .foregroundStyle(RetroPalette.ink.opacity(configuration.isPressed ? 0.62 : 1))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(minHeight: 28)
            .background(prominent ? RetroPalette.paper : RetroPalette.chrome)
            .raisedBorder(emphasized: prominent)
            .offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
    }
}

struct RetroPanel<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title.uppercased())
                    .font(.retro(10, weight: .bold))
                    .tracking(0.8)
                Rectangle().fill(RetroPalette.midEdge).frame(height: 1)
            }
            content()
        }
        .foregroundStyle(RetroPalette.ink)
        .padding(12)
        .raisedBorder()
    }
}

struct StatusLight: View {
    let color: Color
    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 9, height: 9)
            .overlay(Rectangle().stroke(RetroPalette.darkEdge, lineWidth: 1))
            .shadow(color: color.opacity(0.45), radius: 2)
    }
}

struct RetroTextField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(RetroPalette.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .insetBorder()
    }
}

struct PropertyRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.retro(12, weight: .semibold))
                .frame(width: 122, alignment: .trailing)
            content()
                .font(.retro(12))
            Spacer(minLength: 0)
        }
    }
}

struct ThinRule: View {
    var body: some View { Rectangle().fill(RetroPalette.midEdge.opacity(0.7)).frame(height: 1) }
}
