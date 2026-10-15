import Foundation

extension CatalogStore {
    /// The library songs a source marks as in the signed-in family member's own library, by
    /// library id: the ones "Remove from my library" can take out.
    public func personalTrackIds(_ sourceId: String) throws -> Set<String> {
        Set(try db.strings("SELECT mergedId FROM source_track WHERE sourceId = ? AND personal = 1 AND mergedId != ''",
                           [sourceId]))
    }
}
