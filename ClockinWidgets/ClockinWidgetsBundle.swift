import SwiftUI
import WidgetKit

@main
struct ClockinWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        FocusLiveActivity()
        AlarmLiveActivity()
        FocusControl()
    }
}
