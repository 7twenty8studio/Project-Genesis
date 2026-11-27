package com.genesis.core.domain.sync

/**
 * How a pulled row meets this device's copy, as SyncMerge on iOS: the newest
 * edit wins (updated_at is the edit time on whichever device made it), and a
 * deletion is an edit like any other.
 */
object SyncMerge {
    enum class Decision {
        /** Create or overwrite the local record from the server. */
        APPLY_REMOTE,

        /** Delete the local record (deleted on another device). */
        DELETE_LOCAL,

        /** Keep the local record; it is newer and will be pushed. */
        KEEP_LOCAL,
    }

    fun decide(remoteUpdatedAt: Long, remoteDeleted: Boolean, localUpdatedAt: Long?): Decision {
        if (localUpdatedAt == null) return if (remoteDeleted) Decision.KEEP_LOCAL else Decision.APPLY_REMOTE
        // Timestamps round-trip through the server at millisecond precision.
        if (localUpdatedAt > remoteUpdatedAt) return Decision.KEEP_LOCAL
        return if (remoteDeleted) Decision.DELETE_LOCAL else Decision.APPLY_REMOTE
    }
}
