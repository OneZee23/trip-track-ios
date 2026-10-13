import SwiftUI

/// Заголовок вкладки ПЕРВОЙ СТРОКОЙ ШТОРКИ (эррата 1 к спеке «Атласа»).
///
/// До 27 сентября он стоял отдельным слоем у верхнего края экрана и на
/// телефонах с большой безопасной зоной наезжал на часы. Причин переезда две,
/// и обе решения владельца: «Атлас» и «Места» обязаны выглядеть одинаково при
/// переключении вкладок, а заголовок объекта принадлежит той панели, в
/// которой объект открыт.
///
/// Строка ЗАКРЕПЛЕНА: она стоит над скроллом и видна во всех положениях
/// шторки, включая подсказку. Поэтому рампа затухания заголовка (420…280)
/// отменена — гасить больше нечего.
struct AtlasSheetTitleRow<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    /// Высота строки по эррате. Числом, потому что от неё считается высота
    /// каждого содержимого шторки, а та обязана быть известна ДО разметки.
    static var height: CGFloat { 44 }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(AppType.title)
                .tracking(AppType.titleTracking)
                .foregroundStyle(AtlasTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .allowsHitTesting(false)
            trailing()
            Spacer(minLength: 4)
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AtlasTheme.sideInset)
    }
}
