package com.genesis.core.domain.sync

import com.genesis.core.domain.sync.SyncMerge.Decision
import kotlin.test.Test
import kotlin.test.assertEquals

/** The same cases as iOS's SyncMergeTests. */
class SyncMergeTest {
    @Test
    fun newRowsArriveAndDeletedOnesDont() {
        assertEquals(Decision.APPLY_REMOTE, SyncMerge.decide(10, remoteDeleted = false, localUpdatedAt = null))
        assertEquals(Decision.KEEP_LOCAL, SyncMerge.decide(10, remoteDeleted = true, localUpdatedAt = null))
    }

    @Test
    fun theNewestEditWins() {
        assertEquals(Decision.KEEP_LOCAL, SyncMerge.decide(10, remoteDeleted = false, localUpdatedAt = 20))
        assertEquals(Decision.APPLY_REMOTE, SyncMerge.decide(20, remoteDeleted = false, localUpdatedAt = 10))
        assertEquals(Decision.DELETE_LOCAL, SyncMerge.decide(20, remoteDeleted = true, localUpdatedAt = 10))
        assertEquals(Decision.KEEP_LOCAL, SyncMerge.decide(10, remoteDeleted = true, localUpdatedAt = 20))
    }

    @Test
    fun theSameEditIsAppliedAgainHarmlessly() {
        assertEquals(Decision.APPLY_REMOTE, SyncMerge.decide(10, remoteDeleted = false, localUpdatedAt = 10))
    }
}
