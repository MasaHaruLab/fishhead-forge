import SwiftUI

/// Excused training pauses — sick days and time off that pause the streak
/// instead of breaking it. List with days lost and strength rebound, plus
/// the add/edit form. An empty end date means "until further notice": the
/// break closes itself when the next workout is finished.
struct BreaksView: View {
    var onChanged: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var summary: BreaksSummary?
    @State private var loading = true
    @State private var editing: BreakSummaryEntry?
    @State private var adding = false
    @State private var errorText: String?

    static let kinds = ["sick", "time_off", "other"]

    static func color(_ kind: String) -> Color {
        switch kind {
        case "sick": return Color(red: 0.831, green: 0.655, blue: 0.173)     // #d4a72c amber
        case "time_off": return Color(red: 0.247, green: 0.655, blue: 0.639) // #3fa7a3 teal
        default: return Color(red: 0.561, green: 0.525, blue: 0.788)         // #8f86c9
        }
    }

    static func label(_ kind: String) -> String {
        switch kind {
        case "sick": return "Sick"
        case "time_off": return "Time off"
        default: return "Other"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FG.background.ignoresSafeArea()
                if loading {
                    ProgressView().tint(FG.ember)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Sick days and time off pause your streak instead of breaking it. A break without an end date closes itself when you next train.")
                                .font(.system(size: 13)).foregroundStyle(FG.muted)
                            if let summary, summary.count_last_year > 0 {
                                chips(summary)
                            }
                            if let summary, !summary.breaks.isEmpty {
                                list(summary.breaks)
                            }
                            Button {
                                adding = true
                            } label: {
                                Text("Add break")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.black)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(FG.ember))
                            }
                            .buttonStyle(Pressable())
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 6)
                    }
                }
            }
            .navigationTitle("Breaks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(FG.ember)
                }
            }
            .sheet(isPresented: $adding) {
                BreakFormView(existing: nil) { await save(nil, $0) }
            }
            .sheet(item: $editing) { entry in
                BreakFormView(existing: entry) { await save(entry, $0) }
            }
            .alert("Couldn't save", isPresented: .init(
                get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    private func chips(_ s: BreaksSummary) -> some View {
        HStack(spacing: 8) {
            ForEach(s.days_last_year.sorted(by: { $0.key < $1.key }), id: \.key) { kind, days in
                Text("\(Self.label(kind)): \(days) day\(days == 1 ? "" : "s") in the past 12 months")
                    .font(.system(size: 12)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().stroke(Self.color(kind), lineWidth: 1))
            }
        }
    }

    private func list(_ breaks: [BreakSummaryEntry]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(breaks.enumerated()), id: \.element.id) { i, b in
                if i > 0 { Divider().overlay(FG.border) }
                HStack(spacing: 12) {
                    Circle()
                        .fill(Self.color(b.kind))
                        .frame(width: 10, height: 10)
                        .shadow(color: Self.color(b.kind).opacity(0.7), radius: 3)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(Self.label(b.kind))
                                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                            if let note = b.note, !note.isEmpty {
                                Text(note).font(.system(size: 13)).foregroundStyle(FG.muted)
                                    .lineLimit(1)
                            }
                        }
                        Text(subtitle(b))
                            .font(.system(size: 12)).foregroundStyle(FG.muted)
                    }
                    Spacer()
                    Button {
                        editing = b
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 13)).foregroundStyle(FG.muted)
                            .frame(width: 32, height: 32)
                    }
                    Button {
                        Task { await remove(b) }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13)).foregroundStyle(FG.muted)
                            .frame(width: 32, height: 32)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
    }

    private func subtitle(_ b: BreakSummaryEntry) -> String {
        var parts = [fmtRange(b.start_date, b.end_date)]
        parts.append("\(b.days) day\(b.days == 1 ? "" : "s")")
        if let r = b.rebound_pct { parts.append("came back at \(Int(r.rounded()))%") }
        if b.auto_closed { parts.append("ended by training") }
        return parts.joined(separator: " · ")
    }

    private func fmtRange(_ start: String, _ end: String?) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let out = DateFormatter()
        out.dateFormat = "d MMM"
        let s = df.date(from: start).map { out.string(from: $0) } ?? start
        guard let end else { return "\(s) — ongoing" }
        let e = df.date(from: end).map { out.string(from: $0) } ?? end
        return "\(s) – \(e)"
    }

    private func load() async {
        do {
            summary = try await ForgeAPI.breaksSummary()
            syncNotification()
        } catch {}
        loading = false
    }

    private func syncNotification() {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let openStart = summary?.breaks.first { $0.end_date == nil }
            .flatMap { df.date(from: $0.start_date) }
        LocalNotifications.syncStillSick(openBreakStart: openStart)
    }

    private func save(_ existing: BreakSummaryEntry?, _ form: BreakFormData) async {
        do {
            if let existing {
                try await ForgeAPI.updateBreak(
                    id: existing.id, kind: form.kind, start: form.start,
                    end: form.end, note: form.note)
            } else {
                try await ForgeAPI.createBreak(
                    kind: form.kind, start: form.start, end: form.end, note: form.note)
            }
            adding = false
            editing = nil
            await load()
            onChanged()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func remove(_ b: BreakSummaryEntry) async {
        do {
            try await ForgeAPI.deleteBreak(id: b.id)
            await load()
            onChanged()
        } catch {}
    }
}

struct BreakFormData {
    var kind: String
    var start: String
    var end: String?
    var note: String?
}

/// The add/edit form, in the app's card idiom: a segmented pill for the
/// reason, label-left rows with date chips that expand an inline calendar,
/// the "until further notice" toggle, and an optional note. Fitted detent —
/// no dead space below the form.
struct BreakFormView: View {
    let existing: BreakSummaryEntry?
    let onSave: (BreakFormData) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kindIndex = 0
    @State private var start = Date()
    @State private var end = Date()
    @State private var ongoing = false
    @State private var note = ""
    @State private var saving = false
    @State private var expanded: Field?
    @State private var detent: PresentationDetent = .medium

    private enum Field { case from, until }

    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                FG.background.ignoresSafeArea()
                ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        PillSegmented(
                            options: BreaksView.kinds.map { BreaksView.label($0) },
                            selection: $kindIndex)

                        VStack(spacing: 0) {
                            dateRow("From", date: start, field: .from)
                            if expanded == .from {
                                calendar($start, in: nil) { d in
                                    if end < d { end = d }
                                }
                                .id("cal-from")
                            }
                            Divider().overlay(FG.border)
                            HStack {
                                Text("Until further notice")
                                    .font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                                Spacer()
                                Toggle("", isOn: $ongoing.animation(.easeOut(duration: 0.18)))
                                    .labelsHidden()
                                    .tint(FG.ember)
                            }
                            .padding(.horizontal, 14).frame(height: 48)
                            if ongoing {
                                Text("Ends when you next train — or set a date later.")
                                    .font(.system(size: 12)).foregroundStyle(FG.muted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14).padding(.bottom, 11)
                            } else {
                                Divider().overlay(FG.border)
                                dateRow("Until", date: end, field: .until)
                                if expanded == .until {
                                    calendar($end, in: start...) { _ in }
                                        .id("cal-until")
                                }
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))

                        TextField("Note — optional", text: $note)
                            .font(.system(size: 15)).foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(height: 48)
                            .background(RoundedRectangle(cornerRadius: 12).fill(FG.card))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(FG.border, lineWidth: 1))

                        Button {
                            saving = true
                            Task {
                                await onSave(BreakFormData(
                                    kind: BreaksView.kinds[kindIndex],
                                    start: Self.df.string(from: start),
                                    end: ongoing ? nil : Self.df.string(from: end),
                                    note: note.trimmingCharacters(in: .whitespaces).isEmpty
                                        ? nil : note.trimmingCharacters(in: .whitespaces)))
                                saving = false
                            }
                        } label: {
                            Group {
                                if saving { ProgressView().tint(.black) }
                                else { Text("Save").font(.system(size: 15, weight: .semibold)) }
                            }
                            .foregroundStyle(.black.opacity(0.8))
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(RoundedRectangle(cornerRadius: 14).fill(FG.ember))
                        }
                        .buttonStyle(Pressable())
                        .disabled(saving)

                        Color.clear.frame(height: 8)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                }
                // An expanded calendar needs the tall sheet and to actually
                // be on screen — grow the detent, then scroll it into view
                .onChange(of: expanded) { _, new in
                    guard let new else { return }
                    detent = .large
                    let target = new == .from ? "cal-from" : "cal-until"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(target, anchor: .bottom)
                        }
                    }
                }
                }
            }
            .navigationTitle(existing == nil ? "Add break" : "Edit break")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(FG.muted)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large], selection: $detent)
        .onAppear {
            guard let existing else { return }
            kindIndex = BreaksView.kinds.firstIndex(of: existing.kind) ?? 0
            start = Self.df.date(from: existing.start_date) ?? Date()
            if let e = existing.end_date, let d = Self.df.date(from: e) {
                end = d
                ongoing = false
            } else {
                ongoing = true
            }
            note = existing.note ?? ""
        }
    }

    /// Label-left row with a pill date chip; tapping expands the calendar
    /// inline underneath (Settings-alarm style, but in the house palette).
    private func dateRow(_ label: String, date: Date, field: Field) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                expanded = expanded == field ? nil : field
            }
        } label: {
            HStack {
                Text(label)
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                Spacer()
                Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(expanded == field ? FG.ember : .white)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9).fill(FG.secondary))
            }
            .padding(.horizontal, 14).frame(height: 48)
        }
        .buttonStyle(.plain)
    }

    private func calendar(
        _ selection: Binding<Date>, in range: PartialRangeFrom<Date>?,
        onPick: @escaping (Date) -> Void
    ) -> some View {
        Group {
            if let range {
                DatePicker("", selection: selection, in: range, displayedComponents: .date)
            } else {
                DatePicker("", selection: selection, displayedComponents: .date)
            }
        }
        .datePickerStyle(.graphical)
        .labelsHidden()
        .tint(FG.ember)
        .padding(.horizontal, 8)
        .onChange(of: selection.wrappedValue) { _, new in
            onPick(new)
            withAnimation(.easeOut(duration: 0.18)) { expanded = nil }
        }
    }
}
