package com.genesis.core.cloud

import com.genesis.core.cloud.community.GroupMember
import com.genesis.core.cloud.community.GroupPermissions
import com.genesis.core.cloud.community.GroupReport
import com.genesis.core.cloud.community.GroupStanding
import com.genesis.core.cloud.community.ContentKind
import com.genesis.core.cloud.community.isMuted
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ModerationTest {
    private val owner = "o"
    private fun member(id: String, role: String = "member", preacher: Boolean = false, muted: String? = null) =
        GroupMember("g", id, role, id, "2026-11-01T00:00:00Z", muted, preacher)

    @Test fun ownerActsOnModeratorsButNotThemselves() {
        val perms = GroupPermissions(me = owner, ownerId = owner, myRole = "leader")
        assertTrue(perms.canModerate(member("m", "leader")))
        assertTrue(perms.canChooseRole(member("m", "leader")))
        assertFalse(perms.canModerate(member(owner, "leader")))
        assertFalse(perms.canChooseRole(member(owner, "leader")))
    }

    @Test fun moderatorsActOnMembersOnly() {
        val perms = GroupPermissions(me = "m", ownerId = owner, myRole = "leader")
        assertTrue(perms.canModerate(member("x")))
        assertFalse(perms.canModerate(member("m2", "leader")))
        assertFalse(perms.canModerate(member(owner, "leader")))
        assertFalse(perms.canChooseRole(member("x")))
    }

    @Test fun membersActOnNobody() {
        val perms = GroupPermissions(me = "x", ownerId = owner, myRole = "member")
        assertFalse(perms.canModerate(member("y")))
        assertFalse(perms.canChoosePreacher(member("y")))
    }

    @Test fun preachersOnlyInChurches() {
        val church = GroupPermissions(me = "m", ownerId = owner, myRole = "leader", isChurch = true)
        assertTrue(church.canChoosePreacher(member("x")))
        assertFalse(church.canChoosePreacher(member("m2", "leader")))
        assertEquals(GroupStanding.PREACHER, church.standing(member("x", preacher = true)))
        val group = church.copy(isChurch = false)
        assertFalse(group.canChoosePreacher(member("x")))
        assertEquals(GroupStanding.MEMBER, group.standing(member("x", preacher = true)))
        val preacher = GroupPermissions(me = "p", ownerId = owner, myRole = "member", isChurch = true)
        assertTrue(preacher.canStepDown(member("p", preacher = true)))
        assertFalse(preacher.canStepDown(member("q", preacher = true)))
    }

    @Test fun idsCompareWithoutCase() {
        val perms = GroupPermissions(me = "abc", ownerId = "ABC", myRole = "leader")
        assertTrue(perms.isOwner)
    }

    @Test fun mutedUntilAFutureTime() {
        assertTrue(member("x", muted = "2100-01-01T00:00:00Z").isMuted())
        assertFalse(member("x", muted = "2000-01-01T00:00:00Z").isMuted())
        assertFalse(member("x").isMuted())
    }

    @Test fun readsReports() {
        val json = """[{"content_type":"group_post","content_id":"a","author_name":"Ann","body":"hi","report_count":3,"reasons":["Spam"],"hidden":true}]"""
        val report = Json { ignoreUnknownKeys = true }.decodeFromString<List<GroupReport>>(json).single()
        assertEquals(ContentKind.GROUP_POST, report.kind)
        assertTrue(report.hidden)
    }
}
