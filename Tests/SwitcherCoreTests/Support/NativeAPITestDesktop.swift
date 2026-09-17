import SwitcherCore

actor NativeAPITestDesktop: DesktopControlling {
    private var closeCount = 0
    private var reopenCount = 0

    func closeDesktop() { closeCount += 1 }
    func reopenDesktop() { reopenCount += 1 }
    func counts() -> (Int, Int) { (closeCount, reopenCount) }
}
