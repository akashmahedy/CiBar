import AppKit

if let i=CommandLine.arguments.firstIndex(of:"--render-previews"),CommandLine.arguments.indices.contains(i+1) {
    do { try renderPreviews(directory:URL(fileURLWithPath:CommandLine.arguments[i+1],isDirectory:true));exit(0) }
    catch { fputs("Preview rendering failed: \(error)\n",stderr);exit(1) }
}

if CommandLine.arguments.contains("--self-test") {
    do { try runTests(); print("CíBar self-tests passed"); exit(0) }
    catch { fputs("CíBar tests failed: \(error)\n",stderr); exit(1) }
}
let app = NSApplication.shared
if let other = NSRunningApplication.runningApplications(withBundleIdentifier:Bundle.main.bundleIdentifier ?? "local.cibar.app").first(where:{$0.processIdentifier != ProcessInfo.processInfo.processIdentifier}) {
    other.activate(options:[.activateIgnoringOtherApps]); exit(0)
}
do {
    let directory: URL?
    if let i=CommandLine.arguments.firstIndex(of:"--data-dir"), CommandLine.arguments.indices.contains(i+1) { directory=URL(fileURLWithPath:CommandLine.arguments[i+1]) }
    else { directory=nil }
    let store=try Store(directory:directory)
    let delegate=AppController(store:store)
    app.delegate=delegate
    withExtendedLifetime(delegate){app.run()}
}catch{
    let alert=NSAlert();alert.messageText="CíBar could not start";alert.informativeText=error.localizedDescription;alert.runModal();exit(1)
}
