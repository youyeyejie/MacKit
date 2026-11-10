/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See THIRD_PARTY_NOTICES.md for the original NOTICE and attribution.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import EventKit
import Foundation

protocol CalendarServiceProviding {
    func requestAccess() async -> Bool
    func requestAccess(to type: EKEntityType) async -> Bool
    func calendars() async -> [CalendarModel]
    func events(from start: Date, to end: Date, calendars: [String]) async -> [EventModel]
}

class CalendarService: CalendarServiceProviding {
    private let store = EKEventStore()

    @MainActor
    func requestAccess() async -> Bool {
        await requestAccess(to: .event)
    }

    @MainActor
    func requestAccess(to type: EKEntityType) async -> Bool {
        do {
            return try await performAccessRequest(for: type)
        } catch {
            print("Calendar access error: \(error)")
            return false
        }
    }

    private func performAccessRequest(for type: EKEntityType) async throws -> Bool {
        switch type {
        case .event:
            return try await store.requestFullAccessToEvents()
        case .reminder:
            return false
        @unknown default:
            return false
        }
    }

    private func hasAccess(to entityType: EKEntityType) -> Bool {
        let status = EKEventStore.authorizationStatus(for: entityType)
        return status == .fullAccess
    }

    func calendars() async -> [CalendarModel] {
        var calendars: [EKCalendar] = []

        for type in [EKEntityType.event] where hasAccess(to: type) {
            calendars.append(contentsOf: store.calendars(for: type))
        }

        return calendars.map { CalendarModel(from: $0) }
    }

    func events(from start: Date, to end: Date, calendars ids: [String]) async -> [EventModel] {
        let allCalendars = await self.calendars()
        let filteredCalendars = allCalendars.filter { ids.isEmpty || ids.contains($0.id) }
        let ekCalendars = filteredCalendars.compactMap { calendarModel in
            store.calendars(for: .event).first { $0.calendarIdentifier == calendarModel.id }
        }

        var events: [EventModel] = []

        // Fetch regular events
        if hasAccess(to: .event) {
            let eventCalendars = ekCalendars.filter { store.calendars(for: .event).contains($0) }
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: eventCalendars)
            let ekEvents = store.events(matching: predicate)
            events.append(contentsOf: ekEvents.compactMap { EventModel(from: $0) })
        }

        // Fetch reminders

        return events.sorted { $0.start < $1.start }
    }

}

// MARK: - Model Extensions

extension CalendarModel {
    init(from calendar: EKCalendar) {
        self.init(
            accountName: calendar.accountTitle,
            id: calendar.calendarIdentifier,
            title: calendar.title,
            color: calendar.color,
            isSubscribed: calendar.isSubscribed || calendar.isDelegate,
            sourceName: calendar.source.sourceType == .subscribed
                ? "Subscribe" : calendar.source.title + (calendar.isSubscribed ? " · Subscribe" : "")
        )
    }
}

extension EventModel {
    init?(from event: EKEvent) {
        guard let calendar = event.calendar else { return nil }

        self.init(
            id: event.calendarItemIdentifier,
            start: event.startDate,
            end: event.endDate,
            title: event.title ?? "",
            location: event.location,
            notes: event.notes,
            url: event.url,
            isAllDay: event.shouldBeAllDay,
            type: .init(from: event),
            calendar: .init(from: calendar),
            participants: .init(from: event),
            timeZone: calendar.isSubscribed || calendar.isDelegate ? nil : event.timeZone,
            hasRecurrenceRules: event.hasRecurrenceRules || event.isDetached,
            conferenceURL: event.extractConferenceURL()
        )
    }

}

extension EventType {
    init(from event: EKEvent) {
        self =
            event.birthdayContactIdentifier != nil
            ? .birthday : .event(.init(from: event.currentUser?.participantStatus))
    }
}

extension AttendanceStatus {
    init(from status: EKParticipantStatus?) {
        switch status {
        case .accepted:
            self = .accepted
        case .tentative:
            self = .maybe
        case .declined:
            self = .declined
        case .pending:
            self = .pending
        default:
            self = .unknown
        }
    }
}

extension Array where Element == Participant {
    init(from event: EKEvent) {
        var participants = event.attendees ?? []
        if let organizer = event.organizer, !participants.contains(where: { $0.url == organizer.url }) {
            participants.append(organizer)
        }
        self.init(
            participants.map { .init(from: $0, isOrganizer: $0.url == event.organizer?.url) }
        )
    }
}

extension Participant {
    init(from participant: EKParticipant, isOrganizer: Bool) {
        self.init(
            name: participant.name ?? participant.url.absoluteString.replacingOccurrences(of: "mailto:", with: ""),
            status: .init(from: participant.participantStatus),
            isOrganizer: isOrganizer,
            isCurrentUser: participant.isCurrentUser
        )
    }
}

// MARK: - Helper Extensions

extension EKCalendar {
    var accountTitle: String {
        switch source.sourceType {
        case .local, .subscribed, .birthdays:
            return String(localized: "Other")
        default:
            return source.title
        }
    }

    var isDelegate: Bool {
        return source.isDelegate
    }
}

extension EKEvent {
    fileprivate var currentUser: EKParticipant? {
        attendees?.first(where: \.isCurrentUser)
    }

    fileprivate var shouldBeAllDay: Bool {
        guard !isAllDay else { return true }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: startDate)
        let endOfDay = calendar.dateInterval(of: .day, for: endDate)?.end
        return startDate == startOfDay && endDate == endOfDay
    }

    /// Extract conference call URL from various sources
    fileprivate func extractConferenceURL() -> URL? {
        // First try the URL field if it's a conference URL
        if let eventURL = url, isConferenceURL(eventURL) {
            return eventURL
        }

        // Then try to extract from location field
        if let location = location, let conferenceURL = extractURLFromText(location) {
            return conferenceURL
        }

        // Finally try to extract from notes
        if let notes = notes, let conferenceURL = extractURLFromText(notes) {
            return conferenceURL
        }

        return nil
    }

    /// Check if a URL is likely a conference URL
    private func isConferenceURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        let conferenceHosts = [
            "zoom.us",
            "teams.microsoft.com",
            "meet.google.com",
            "webex.com",
            "gotomeeting.com",
            "bluejeans.com",
            "whereby.com",
            "meet.jit.si",
            "discord.gg",
            "discord.com",
            "facetime.apple.com",
        ]

        return conferenceHosts.contains { host.contains($0) }
    }

    /// Extract first valid conference URL from text
    private func extractURLFromText(_ text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))

        for match in matches ?? [] {
            if let url = match.url, isConferenceURL(url) {
                return url
            }
        }

        return nil
    }
}

extension Calendar {
    fileprivate func endOfDay(for date: Date) -> Date {
        dateInterval(of: .day, for: date)?.end ?? date
    }
}
