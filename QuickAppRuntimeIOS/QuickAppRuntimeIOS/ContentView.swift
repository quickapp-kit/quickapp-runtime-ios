import SwiftUI

@MainActor
private struct RuntimeSurfaceView: UIViewRepresentable {
  let onAttach: (UIView) -> Void

  func makeUIView(context: Context) -> UIView {
    let view = UIView()
    view.backgroundColor = .white
    DispatchQueue.main.async {
      onAttach(view)
    }
    return view
  }

  func updateUIView(_ view: UIView, context: Context) {}
}

private struct RPKApp: Identifiable, Hashable {
  let url: URL

  var id: String { url.path }

  var name: String {
    url.deletingPathExtension().lastPathComponent
  }
}

struct ContentView: View {
  @State private var apps: [RPKApp] = ContentView.loadApps()
  @State private var selectedApp: RPKApp? = ContentView.initialApp()
  @State private var runtime: QuickAppKitRuntime?
  @State private var surface: UIView?
  @State private var status = "请选择应用"

  var body: some View {
    Group {
      if let selectedApp {
        VStack(spacing: 0) {
          HStack {
            Button {
              closeApp()
            } label: {
              Label("退出应用", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(.borderless)
            Spacer()
            Text(selectedApp.name)
              .font(.headline)
            Spacer()
            Text(status)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          .padding(.horizontal)
          .padding(.vertical, 10)

          RuntimeSurfaceView { readySurface in
            surface = readySurface
            load(selectedApp, into: readySurface)
          }
        }
      } else {
        VStack(alignment: .leading, spacing: 12) {
          Text("QuickAppKitHost")
            .font(.title2.bold())
          Text("本地应用")
            .font(.headline)
            .foregroundStyle(.secondary)

          if apps.isEmpty {
            Text("Bundle 中没有 RPK")
              .foregroundStyle(.secondary)
          } else {
            ScrollView {
              LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 84, maximum: 112), spacing: 24)
              ], spacing: 26) {
                ForEach(apps) { app in
                  Button {
                    open(app)
                  } label: {
                    VStack(spacing: 8) {
                      RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.accentColor.gradient)
                        .frame(width: 72, height: 72)
                        .overlay {
                          Image(systemName: "app.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white)
                        }
                      Text(app.name)
                        .font(.caption)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(width: 96, height: 32, alignment: .top)
                    }
                  }
                  .buttonStyle(.plain)
                }
              }
            }
          }
        }
        .padding()
      }
    }
  }

  private static func loadApps() -> [RPKApp] {
    (Bundle.main.urls(forResourcesWithExtension: "rpk", subdirectory: nil) ?? [])
      .map(RPKApp.init)
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  private static func initialApp() -> RPKApp? {
    let requestedName = ProcessInfo.processInfo.environment["QUICKAPP_RPK"]
    guard let requestedName else { return nil }
    return loadApps().first {
      $0.name == requestedName || $0.url.deletingPathExtension().lastPathComponent == requestedName
    }
  }

  private func open(_ app: RPKApp) {
    surface = nil
    selectedApp = app
    status = "正在加载"
  }

  private func closeApp() {
    destroyRuntime()
    surface = nil
    selectedApp = nil
    status = "请选择应用"
  }

  private func load(_ app: RPKApp, into surface: UIView) {
    destroyRuntime()
    do {
      let created = try QuickAppKitRuntime.createRuntime(
        withViewportWidth: surface.bounds.width,
        height: surface.bounds.height)
      try created.attachSurface(surface)
      runtime = created
      status = "正在加载 \(app.name)"
      created.loadRPK(from: app.url) { success, error in
        Task { @MainActor in
          status = success ? "已加载 \(app.name)" : (error?.localizedDescription ?? "RPK 加载失败")
        }
      }
    } catch let error as NSError {
      status = error.localizedDescription
    }
  }

  private func destroyRuntime() {
    runtime?.destroy()
    runtime = nil
  }
}
