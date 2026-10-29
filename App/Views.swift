import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: Model

    var body: some View {
        TabView {
            EventsView().tabItem { Label("Events", systemImage: "bolt") }
            ProfilesView().tabItem { Label("Profiles", systemImage: "lightbulb") }
        }
        .padding()
        .frame(minWidth: 640, minHeight: 520)
    }
}

struct EventsView: View {
    @EnvironmentObject var model: Model

    var body: some View {
        Form {
            Section("LED helper") {
                HStack {
                    Image(systemName: model.helperInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(model.helperInstalled ? .green : .orange)
                    Text(model.helperInstalled ? "Running. LED control works." : "Not installed. Needed to write the LED (asks for your admin password once).")
                    Spacer()
                    if model.helperInstalled {
                        Button("Remove") { model.removeHelper() }
                    } else {
                        Button("Install") { model.installHelper() }
                    }
                }
                if !model.message.isEmpty { Text(model.message).font(.caption).foregroundStyle(.red) }
            }
            EventSection(title: "When the charger is plugged in", config: $model.settings.onPlug)
            EventSection(title: "When the charger is unplugged", config: $model.settings.onUnplug)
            Section("System") {
                Toggle("Silence the built-in macOS charging chime", isOn: $model.settings.muteSystemChime)
                    .onChange(of: model.settings.muteSystemChime) { _, _ in model.applyChimeMute() }
                Text("Best effort: sets the PowerChime preference. Turn on if you hear two sounds.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Restore system LED now") { model.restoreLED() }
            }
        }
        .formStyle(.grouped)
    }
}

struct EventSection: View {
    @EnvironmentObject var model: Model
    let title: String
    @Binding var config: EventConfig

    var body: some View {
        Section(title) {
            Toggle("Play a sound", isOn: $config.soundOn)
            if config.soundOn {
                HStack {
                    Text(config.soundPath.map { ($0 as NSString).lastPathComponent } ?? "Default (bundled chime)")
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choose…") { choose() }
                    if config.soundPath != nil { Button("Default") { config.soundPath = nil } }
                }
                HStack {
                    Image(systemName: "speaker.fill")
                    Slider(value: $config.volume, in: 0...1)
                    Image(systemName: "speaker.wave.3.fill")
                }
            }
            Picker("LED profile", selection: $config.profileID) {
                Text("None").tag(UUID?.none)
                ForEach(model.settings.profiles) { Text($0.name).tag(UUID?.some($0.id)) }
            }
            Button("Test") { model.fire(config) }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        if panel.runModal() == .OK, let url = panel.url { config.soundPath = url.path }
    }
}

struct ProfilesView: View {
    @EnvironmentObject var model: Model
    // @State is a macro in this SDK and needs Xcode's plugin, which plain swiftc lacks; keep view state on the model.
    private var selection: UUID? {
        get { model.selection }
        nonmutating set { model.selection = newValue }
    }

    var body: some View {
        HSplitView {
            VStack {
                List(selection: $model.selection) {
                    ForEach(model.settings.profiles) { Text($0.name).tag($0.id) }
                }
                HStack {
                    Button { add() } label: { Image(systemName: "plus") }
                    Button { remove() } label: { Image(systemName: "minus") }.disabled(selection == nil)
                }
            }
            .frame(minWidth: 160, maxWidth: 220)
            if let i = model.settings.profiles.firstIndex(where: { $0.id == selection }) {
                ProfileEditor(profile: $model.settings.profiles[i])
            } else {
                Text("Select or add a profile").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func add() {
        let p = Profile(name: "New profile", steps: [Step(value: 3, ms: 400), Step(value: 4, ms: 400)])
        model.settings.profiles.append(p)
        selection = p.id
    }

    private func remove() {
        model.settings.profiles.removeAll { $0.id == selection }
        selection = nil
    }
}

struct ProfileEditor: View {
    @EnvironmentObject var model: Model
    @Binding var profile: Profile

    var body: some View {
        VStack(alignment: .leading) {
            TextField("Name", text: $profile.name)
            Stepper("Repeat \(profile.loops) time\(profile.loops == 1 ? "" : "s")", value: $profile.loops, in: 1...100)
            Text("Steps").font(.headline)
            List {
                ForEach($profile.steps) { $step in
                    HStack {
                        Picker("", selection: $step.value) {
                            ForEach(ledStates, id: \.value) { Text($0.name).tag($0.value) }
                        }
                        .labelsHidden()
                        Stepper("\(step.ms) ms", value: $step.ms, in: 20...5000, step: 50)
                    }
                }
                .onDelete { profile.steps.remove(atOffsets: $0) }
                .onMove { profile.steps.move(fromOffsets: $0, toOffset: $1) }
            }
            HStack {
                Button("Add step") { profile.steps.append(Step()) }
                Spacer()
                Button("Stop") { model.restoreLED() }
                Button("Test") { model.run(profile) }.keyboardShortcut(.defaultAction)
            }
            Text("Each step holds for its time, then the next one runs. Orange and green can't light together: the firmware has one colour state at a time, so mixes come from alternating steps. When the profile ends the LED returns to system control. Experimental values are untested.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.leading)
    }
}
