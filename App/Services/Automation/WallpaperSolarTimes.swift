import Foundation

/// Local, approximate sunrise/sunset using NOAA's published fractional-year equations.
/// https://gml.noaa.gov/grad/solcalc/solareqns.PDF
enum WallpaperSolarTimes {
    static func event(_ event: WallpaperAutomationRule.Event, on day: Date,
                      location: WallpaperSolarLocation, calendar: Calendar) -> Date? {
        guard event != .time, location.isValid else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var local = Calendar(identifier: .gregorian)
        local.timeZone = calendar.timeZone
        let components = local.dateComponents([.year, .month, .day], from: day)
        guard let base = utc.date(from: components) else { return nil }
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        // Longitude and the Mac's time zone need not agree; choose the event actually
        // occurring on this local day, rather than assuming its UTC date matches.
        for shift in -1...1 {
            guard let midnight = utc.date(byAdding: .day, value: shift, to: base),
                  let ordinal = utc.ordinality(of: .day, in: .year, for: midnight),
                  let days = utc.range(of: .day, in: .year, for: midnight)?.count else { continue }
            let gamma = 2 * Double.pi / Double(days) * Double(ordinal - 1)
            let equation = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
                - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))
            let declination = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma)
                - 0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma)
                - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)
            let latitude = location.latitude * .pi / 180
            let denominator = cos(latitude) * cos(declination)
            guard abs(denominator) > 1e-12 else { continue }
            let cosine = (cos(90.833 * .pi / 180) - sin(latitude) * sin(declination)) / denominator
            guard (-1...1).contains(cosine) else { continue } // Polar day/night has no event.
            let angle = acos(cosine) * 180 / .pi
            let minutes = 720 - 4 * location.longitude - equation + (event == .sunrise ? -4 : 4) * angle
            let timestamp = midnight.timeIntervalSince1970 + minutes * 60
            let result = Date(timeIntervalSince1970: (timestamp / 60).rounded() * 60)
            if result >= start && result < end { return result }
        }
        return nil
    }
}
