//
//  StarkUI
//
#if canImport(SwiftUI)
import SwiftUI
import StarkCore

/// The whole app in one screen: five panes, no chrome, no decoration.
public struct StarkDashboard: View {
  public enum Pane: String, CaseIterable, Identifiable {
    case stats, queue, links, model, log
    public var id: String { rawValue }
  }

  @State private var view: StarkViewModel
  @State private var pane: Pane = .stats

  public init(server: StarkServer) {
    _view = State(initialValue: StarkViewModel(server: server))
  }

  public var body: some View {
    VStack(spacing: 0) {
      header
      Hairline()
      tabs
      Hairline()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          switch pane {
          case .stats: StatsPane(view: view)
          case .queue: QueuePane(view: view)
          case .links: LinksPane(view: view)
          case .model: ModelPane(view: view)
          case .log: LogPane(view: view)
          }
        }
        .padding(14)
      }
    }
    .background(StarkTheme.bg)
    .foregroundStyle(StarkTheme.ink)
    .font(StarkTheme.mono)
    .tint(StarkTheme.ink)
    .task {
      await view.refresh()
      view.startRefreshing()
    }
    .onDisappear { view.stopRefreshing() }
  }

  private var header: some View {
    HStack(spacing: 9) {
      Circle()
        .fill(view.engineRunning ? StarkTheme.ok : StarkTheme.dim)
        .frame(width: 6, height: 6)
      Text("STARK").tracking(4).font(StarkTheme.mono)
      Spacer()
      if let busy = view.busy {
        Text(busy).foregroundStyle(StarkTheme.dim)
      } else {
        Text(view.model.modelID.map { String($0.split(separator: "/").last ?? "") } ?? "no model")
          .foregroundStyle(StarkTheme.dim)
          .lineLimit(1)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
  }

  private var tabs: some View {
    HStack(spacing: 0) {
      ForEach(Pane.allCases) { item in
        Button {
          pane = item
        } label: {
          Text(item.rawValue.uppercased())
            .font(StarkTheme.monoSmall)
            .tracking(1.3)
            .foregroundStyle(pane == item ? StarkTheme.ink : StarkTheme.dim)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .overlay(alignment: .bottom) {
              Rectangle()
                .fill(pane == item ? StarkTheme.ink : .clear)
                .frame(height: 1)
            }
        }
        .buttonStyle(.plain)
      }
    }
  }
}

// MARK: - Stats

struct StatsPane: View {
  let view: StarkViewModel

  var body: some View {
    let metrics = view.metrics
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 1)], spacing: 1) {
      StatTile(label: "queue", value: "\(metrics.queueDepth)")
      StatTile(label: "sent 24h", value: "\(metrics.last24h["sent"] ?? 0)")
      StatTile(label: "drafted 24h", value: "\(metrics.last24h["drafted"] ?? 0)")
      StatTile(label: "blocked 24h", value: "\(metrics.last24h["blocked"] ?? 0)")
      StatTile(label: "sent all", value: "\(metrics.counts["sent"] ?? 0)")
      StatTile(label: "tok/s", value: String(format: "%.1f", metrics.tokensPerSecond))
    }
    .background(StarkTheme.line)
    .overlay(Rectangle().stroke(StarkTheme.line, lineWidth: 1))

    VStack(alignment: .leading, spacing: 6) {
      Sparkline(values: metrics.sentByHour)
      StarkLabel(text: "sends per hour, last 24h")
    }

    HStack(spacing: 8) {
      Button("RUN NOW") { Task { await view.runOnce() } }
      Button(view.engineRunning ? "STOP LOOP" : "START LOOP") { Task { await view.toggleEngine() } }
    }
    .buttonStyle(StarkButton())

    VStack(alignment: .leading, spacing: 6) {
      StarkLabel(text: "publishing")
      ForEach(PublishingPolicy.Mode.allCases, id: \.self) { mode in
        Button {
          Task { await view.setMode(mode) }
        } label: {
          HStack {
            Text(mode == view.config.publishing.mode ? "▪︎" : "▫︎")
            Text(Self.describe(mode))
            Spacer()
          }
          .foregroundStyle(mode == view.config.publishing.mode ? StarkTheme.ink : StarkTheme.dim)
        }
        .buttonStyle(.plain)
      }
    }

    if let url = view.consoleURL {
      VStack(alignment: .leading, spacing: 4) {
        StarkLabel(text: "console")
        Text(url.absoluteString).foregroundStyle(StarkTheme.dim)
        Text("token \(view.config.apiToken)").foregroundStyle(StarkTheme.dim).textSelection(.enabled)
      }
    }

    Text(String(format: "mem budget %.1f GB · disk free %.1f GB", DeviceCapability.memoryBudgetGB, DeviceCapability.freeDiskGB))
      .foregroundStyle(StarkTheme.dim)
  }

  static func describe(_ mode: PublishingPolicy.Mode) -> String {
    switch mode {
    case .review: "review — every draft waits for you"
    case .autoWithinGuardrails: "auto — send what clears the guardrails"
    case .dryRun: "dry run — draft only, never send"
    }
  }
}

// MARK: - Queue

struct QueuePane: View {
  let view: StarkViewModel
  @State private var edits: [String: String] = [:]

  var body: some View {
    if view.drafts.isEmpty {
      Text("queue empty").foregroundStyle(StarkTheme.dim)
    }
    ForEach(view.drafts) { draft in
      VStack(alignment: .leading, spacing: 7) {
        HStack(spacing: 7) {
          Pill(text: draft.status.rawValue, color: draft.status.tint)
          Text("\(draft.item.authorHandle) · \(draft.item.platform.rawValue)")
            .foregroundStyle(StarkTheme.dim)
            .lineLimit(1)
        }
        Text(draft.item.text.prefix(240) + (draft.item.text.count > 240 ? "…" : ""))
          .foregroundStyle(StarkTheme.dim)

        if draft.status == .pending {
          TextEditor(text: Binding(
            get: { edits[draft.id] ?? draft.finalText },
            set: { edits[draft.id] = $0 }
          ))
          .font(StarkTheme.mono)
          .scrollContentBackground(.hidden)
          .frame(minHeight: 92)
          .padding(6)
          .background(Color(white: 0.04))
          .overlay(Rectangle().stroke(StarkTheme.line, lineWidth: 1))
        } else {
          Text(draft.finalText)
        }

        if !draft.verdict.reasons.isEmpty {
          Text("↳ " + draft.verdict.reasons.joined(separator: " · "))
            .foregroundStyle(draft.status == .blocked ? StarkTheme.bad : StarkTheme.warn)
        }

        if draft.status == .pending {
          HStack(spacing: 8) {
            Button("APPROVE & SEND") {
              Task { await view.approve(draft, editedText: edits[draft.id]) }
            }
            Button("REJECT") { Task { await view.reject(draft) } }
          }
          .buttonStyle(StarkButton())
        }
        Hairline()
      }
    }
  }
}

// MARK: - Links

struct LinksPane: View {
  let view: StarkViewModel
  @State private var kind: PlatformKind = .mastodon
  @State private var label = ""
  @State private var endpoint = ""
  @State private var token = ""

  var body: some View {
    StarkLabel(text: "connections")
    if view.connections.isEmpty {
      Text("nothing connected yet").foregroundStyle(StarkTheme.dim)
    }
    ForEach(view.connections) { connection in
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 7) {
          Text(connection.label)
          Text(connection.kind.rawValue).foregroundStyle(StarkTheme.dim)
          if let health = connection.health {
            Pill(text: health.state.rawValue, color: health.state.tint)
          }
          if !connection.enabled { Pill(text: "paused") }
        }
        if let detail = connection.health?.accountHandle ?? connection.health?.detail {
          Text(detail).foregroundStyle(StarkTheme.dim).lineLimit(2)
        }
        HStack(spacing: 8) {
          Button("VERIFY") { Task { await view.verify(connection) } }
          Button(connection.enabled ? "PAUSE" : "RESUME") { Task { await view.toggle(connection) } }
          Button("REMOVE") { Task { await view.remove(connection) } }
        }
        .buttonStyle(StarkButton())
        Hairline()
      }
    }

    StarkLabel(text: "add connection")
    Picker("", selection: $kind) {
      ForEach(PlatformKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
    }
    .pickerStyle(.segmented)

    let hint = ConnectorFactory.setupHint(for: kind)
    Text(hint.help).foregroundStyle(StarkTheme.dim)
    StarkField(label: "label", text: $label)
    StarkField(label: hint.endpointLabel, text: $endpoint)
    StarkField(label: hint.tokenLabel, text: $token, secure: true)
    Button("CONNECT") {
      Task {
        await view.addConnection(kind: kind, label: label.isEmpty ? kind.rawValue : label, endpoint: endpoint, token: token)
        label = ""; endpoint = ""; token = ""
      }
    }
    .buttonStyle(StarkButton())

    Hairline()
    StarkLabel(text: "products")
    ForEach(view.products) { product in
      VStack(alignment: .leading, spacing: 4) {
        Text(product.name)
        Text(product.pitch).foregroundStyle(StarkTheme.dim)
        Button("REMOVE") { Task { await view.removeProduct(product) } }
          .buttonStyle(StarkButton())
      }
    }
  }
}

// MARK: - Model

struct ModelPane: View {
  let view: StarkViewModel

  var body: some View {
    let status = view.model
    VStack(alignment: .leading, spacing: 4) {
      Text(status.state.rawValue.uppercased()).tracking(1.4)
      if let id = status.modelID { Text(id).foregroundStyle(StarkTheme.dim) }
      if status.state == .downloading {
        ProgressView(value: status.progress).tint(StarkTheme.ink)
      }
      if let detail = status.detail { Text(detail).foregroundStyle(StarkTheme.dim) }
    }
    .padding(10)
    .overlay(Rectangle().stroke(StarkTheme.line, lineWidth: 1))

    let fitting = Set(ModelCatalog.fitting().map(\.id))
    ForEach(ModelCatalog.all) { descriptor in
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 7) {
          Text(descriptor.name)
          Text("\(descriptor.parameters) \(descriptor.quantization)").foregroundStyle(StarkTheme.dim)
          Pill(
            text: fitting.contains(descriptor.id) ? "fits" : "too big",
            color: fitting.contains(descriptor.id) ? StarkTheme.ok : StarkTheme.warn
          )
        }
        Text("\(String(format: "%.1f", descriptor.diskGB)) GB on disk · \(descriptor.notes)")
          .foregroundStyle(StarkTheme.dim)
        Button("LOAD") { Task { await view.load(model: descriptor) } }
          .buttonStyle(StarkButton())
        Hairline()
      }
    }
  }
}

// MARK: - Log

struct LogPane: View {
  let view: StarkViewModel

  var body: some View {
    ForEach(view.logs) { entry in
      HStack(alignment: .top, spacing: 7) {
        Text(entry.at.formatted(date: .omitted, time: .standard))
          .foregroundStyle(StarkTheme.dim)
        Text("[\(entry.source)] \(entry.message)")
          .foregroundStyle(tint(entry.level))
      }
      .font(StarkTheme.monoSmall)
    }
  }

  private func tint(_ level: LogLevel) -> Color {
    switch level {
    case .error: StarkTheme.bad
    case .warn: StarkTheme.warn
    case .debug: StarkTheme.dim
    case .info: StarkTheme.ink
    }
  }
}

// MARK: - Controls

struct StarkButton: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(StarkTheme.monoSmall)
      .tracking(1.2)
      .padding(.horizontal, 9)
      .padding(.vertical, 6)
      .foregroundStyle(configuration.isPressed ? StarkTheme.bg : StarkTheme.ink)
      .background(configuration.isPressed ? StarkTheme.ink : Color(white: 0.045))
      .overlay(Rectangle().stroke(StarkTheme.line, lineWidth: 1))
  }
}

struct StarkField: View {
  let label: String
  @Binding var text: String
  var secure = false

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      StarkLabel(text: label)
      Group {
        if secure {
          SecureField("", text: $text)
        } else {
          TextField("", text: $text)
        }
      }
      .textFieldStyle(.plain)
      .font(StarkTheme.mono)
      .padding(7)
      .background(Color(white: 0.045))
      .overlay(Rectangle().stroke(StarkTheme.line, lineWidth: 1))
      #if os(iOS)
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      #endif
    }
  }
}
#endif
