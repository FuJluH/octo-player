import Foundation

// While music plays, the next few server songs of the queue are fetched into the saved songs,
// so they start at once and still play if the connection drops. How many depends on the
// connection: Wi-Fi and mobile data have their own counts. Any change to what comes next starts
// it over. Songs found online are never fetched ahead, only saved as they play.

/// How long a new song plays before the next ones are fetched, so the song itself gets the
/// connection first.
public let prefetchStartAfterMs: Int64 = 5_000

/// How the queue repeats, for fetching ahead.
public enum PrefetchRepeat: Sendable, Equatable {
    case off
    case one
    case all
}

/// How many songs ahead to fetch: none while songs are not saved or with no connection, else the
/// count for Wi-Fi or for mobile data. A connection the phone is asked to use sparingly (Low Data
/// Mode) gets the mobile data count, Wi-Fi or not.
public func prefetchCount(cacheEnabled: Bool, onWifi: Bool, online: Bool, prefs: OfflinePrefs, lowData: Bool = false) -> Int {
    if !cacheEnabled { return 0 }
    if onWifi && !lowData { return prefs.prefetchWifi }
    if online { return prefs.prefetchMobile }
    return 0
}

/// Whether a queue entry can be fetched ahead: a server song, and never one found online.
public func prefetchFetchable(trackId: String, isServerStream: Bool) -> Bool { isServerStream && !isFind(trackId) }

/// The queue places to fetch ahead, in play order: the songs among the next `count` that
/// `fetchable` allows. `playOrder` is every queue place in the order they play (shuffled when
/// shuffle is on). Repeating one song still moves on to the next once it is skipped, so it counts
/// as no repeat; repeating all comes round to the start, and it stops at the song playing now.
/// Nothing is fetched while music is paused (`playing` false).
public func prefetchAhead(playOrder: [Int], current: Int, repeatMode: PrefetchRepeat, playing: Bool = true, count: Int,
                          fetchable: (Int) -> Bool) -> [Int] {
    guard playing, count > 0, !playOrder.isEmpty, var step = playOrder.firstIndex(of: current) else { return [] }
    let wraps = repeatMode == .all
    var places: [Int] = []
    for _ in 0..<count {
        step += 1
        if step == playOrder.count {
            guard wraps else { return places }
            step = 0
        }
        let place = playOrder[step]
        if place == current { return places }
        if fetchable(place) { places.append(place) }
    }
    return places
}
