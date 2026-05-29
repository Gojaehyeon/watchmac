import SwiftUI
import Network

struct ContentView: View {
    @StateObject private var stream = WatchStream()
    @AppStorage("watchmac_host") private var host: String = ""
    @State private var showSettings = false
    @State private var showControls = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let img = stream.image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 8) {
                    if host.trimmingCharacters(in: .whitespaces).isEmpty {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("탭해서 맥 주소 입력")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                        Text(stream.status).font(.footnote).foregroundStyle(.secondary)
                        Text(host).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .onTapGesture { showSettings = true }
            }

            if showControls {
                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(stream.status == "연결됨" ? .green : .orange)
                            .frame(width: 6, height: 6)
                        Text(stream.status == "연결됨" ? "\(stream.fps) fps" : stream.status)
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gear").font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.55))
                }
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { showControls = true }
            hideTask?.cancel()
            hideTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if !Task.isCancelled {
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.4)) { showControls = false }
                    }
                }
            }
        }
        .onAppear {
            if !host.trimmingCharacters(in: .whitespaces).isEmpty {
                stream.connect(to: host)
            }
        }
        .sheet(isPresented: $showSettings) {
            HostEditor(host: $host) {
                showSettings = false
                stream.connect(to: host)
            }
        }
    }
}

struct HostEditor: View {
    @Binding var host: String
    var onConnect: () -> Void
    @State private var probeResult: String = ""
    @State private var probing: Bool = false

    // LAN IP + the public Cloudflare URL change per session, so users enter
    // whichever address watchmac shows in its menu bar.
    private let presets: [(label: String, url: String)] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("빠른 연결").font(.headline)
                ForEach(presets, id: \.url) { p in
                    Button {
                        host = p.url
                        onConnect()
                    } label: {
                        Text(p.label).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }

                Divider().padding(.vertical, 4)

                Text("직접 입력").font(.headline)
                TextField("IP:포트 또는 URL", text: $host)
                    .textContentType(.URL)
                Button(action: onConnect) {
                    Label("연결", systemImage: "wifi").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)

                Text("현재: \(host)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                Divider().padding(.vertical, 4)

                Text("네트워크 진단").font(.headline)
                Text("경로: \(pathSummary)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button(action: probeNetwork) {
                    Label(probing ? "확인 중…" : "HTTPS 도달 확인",
                          systemImage: "network").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(probing)
                if !probeResult.isEmpty {
                    Text(probeResult).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
        .onAppear { startPathMonitor() }
    }

    @State private var pathSummary: String = "—"
    @State private var monitor: NWPathMonitor?

    private func startPathMonitor() {
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                var parts: [String] = []
                switch path.status {
                case .satisfied:   parts.append("satisfied")
                case .unsatisfied: parts.append("unsatisfied")
                case .requiresConnection: parts.append("needsConn")
                @unknown default: parts.append("?")
                }
                if path.usesInterfaceType(.wifi)     { parts.append("wifi") }
                if path.usesInterfaceType(.cellular) { parts.append("cell") }
                if path.usesInterfaceType(.wiredEthernet) { parts.append("eth") }
                if path.isExpensive   { parts.append("expensive") }
                if path.isConstrained { parts.append("constrained") }
                pathSummary = parts.joined(separator: " ")
            }
        }
        m.start(queue: DispatchQueue.global(qos: .background))
        monitor = m
    }

    private func probeNetwork() {
        probing = true
        probeResult = ""
        // Probe the actual host the user is connecting to, not apple.com.
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        let httpURLString: String
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            httpURLString = trimmed
        } else if trimmed.hasPrefix("ws://") {
            httpURLString = "http://" + trimmed.dropFirst("ws://".count)
        } else if trimmed.hasPrefix("wss://") {
            httpURLString = "https://" + trimmed.dropFirst("wss://".count)
        } else {
            httpURLString = "http://\(trimmed)"
        }
        guard let testURL = URL(string: httpURLString) else {
            probing = false; probeResult = "URL 오류"; return
        }
        let config = URLSessionConfiguration.default
        config.allowsCellularAccess = true
        config.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: config)
        var req = URLRequest(url: testURL)
        req.httpMethod = "HEAD"
        session.dataTask(with: req) { _, response, error in
            DispatchQueue.main.async {
                probing = false
                if let err = error as NSError? {
                    probeResult = "실패: [\(err.code)] \(err.localizedDescription.prefix(80))"
                } else if let http = response as? HTTPURLResponse {
                    probeResult = "OK · HTTP \(http.statusCode)"
                } else {
                    probeResult = "응답 없음"
                }
            }
        }.resume()
    }
}
