import SwiftUI

/// Presents a sheet for a view inside a form from the view that `hostsFormSheets()` is on, outside the
/// form. On iPad, a sheet attached to a form's section can close by itself a moment after it first opens,
/// when the list lays the section's rows out again.
struct FormSheetPresenter {
    fileprivate let present: (AnyView) -> Void

    func callAsFunction(@ViewBuilder _ sheet: () -> some View) {
        present(AnyView(sheet()))
    }
}

extension EnvironmentValues {
    /// Nil outside a view that hosts form sheets.
    @Entry var presentFormSheet: FormSheetPresenter?
}

extension View {
    func hostsFormSheets() -> some View {
        modifier(FormSheetHost())
    }
}

private struct FormSheetHost: ViewModifier {
    private struct Shown: Identifiable {
        let id = UUID()
        let sheet: AnyView
    }

    @State private var shown: Shown?

    func body(content: Content) -> some View {
        content
            .environment(\.presentFormSheet, FormSheetPresenter { shown = Shown(sheet: $0) })
            .sheet(item: $shown) { $0.sheet }
    }
}
