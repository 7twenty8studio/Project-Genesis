package com.genesis.core.cloud.community

import com.genesis.core.cloud.Timestamps
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// Group owners, moderators and moderation tools, as GroupModerationModels.swift.
// Rows mirror supabase/migrations/20261011000000_group_moderation_challenges.sql.
// The owner's role is 'leader' too, so "leader" means moderator or owner. In
// a church (sermons on) moderators are called Admins and a member can be a
// Preacher (20261126000000_church_preachers.sql).

/** A role in a church that set_church_role sets. */
enum class ChurchMemberRole(val rawValue: String) { ADMIN("admin"), PREACHER("preacher"), MEMBER("member") }

/** How long a member is muted for (mute_member takes 1 to 720 hours). */
enum class MuteDuration(val hours: Int) { HOUR(1), DAY(24), WEEK(168) }

/** What a moderator decides about reported content. */
enum class ReportAction(val rawValue: String) { REMOVE("remove"), KEEP("keep") }

/** Someone waiting to be let into a group. */
@Serializable
data class GroupJoinRequest(
    @SerialName("group_id") val groupId: String,
    @SerialName("user_id") val userId: String,
    @SerialName("display_name") val displayName: String,
    @SerialName("created_at") val createdAt: String,
    @SerialName("group_name") val groupName: String = "",
)

/** Someone kept out of a group, whatever invite code they have. */
@Serializable
data class GroupBan(
    @SerialName("group_id") val groupId: String,
    @SerialName("user_id") val userId: String,
    @SerialName("display_name") val displayName: String,
    val reason: String = "",
    @SerialName("created_at") val createdAt: String,
)

/** One reported post, prayer request or announcement, with its open reports (never who made them). */
@Serializable
data class GroupReport(
    @SerialName("content_type") val contentType: String,
    @SerialName("content_id") val contentId: String,
    @SerialName("author_id") val authorId: String? = null,
    @SerialName("author_name") val authorName: String = "",
    val body: String = "",
    @SerialName("report_count") val reportCount: Int = 0,
    val reasons: List<String> = emptyList(),
    @SerialName("last_reported_at") val lastReportedAt: String? = null,
    val hidden: Boolean = false,
) {
    val kind: ContentKind? get() = ContentKind.entries.firstOrNull { it.rawValue == contentType }
}

fun GroupMember.isMuted(nowMillis: Long = System.currentTimeMillis()): Boolean {
    val until = mutedUntil?.let(Timestamps::millis) ?: return false
    return until > nowMillis
}

/**
 * What the signed-in person may do to others in a group. Mirrors the
 * server's genesis_can_moderate: moderators act on members, only the owner
 * acts on moderators, nobody acts on the owner or themselves.
 */
data class GroupPermissions(val me: String?, val ownerId: String?, val myRole: String?, val isChurch: Boolean = false) {
    constructor(group: GroupSummary, me: String?) : this(me?.lowercase(), group.ownerId, group.role, group.isChurch)

    private fun same(a: String?, b: String?) = a != null && b != null && a.equals(b, ignoreCase = true)

    val isOwner: Boolean get() = same(me, ownerId)
    /** A moderator or the owner. */
    val isModerator: Boolean get() = myRole == "leader"

    fun standing(member: GroupMember): GroupStanding = when {
        same(member.userId, ownerId) -> GroupStanding.OWNER
        member.isLeader -> GroupStanding.MODERATOR
        isChurch && member.preacher == true -> GroupStanding.PREACHER
        else -> GroupStanding.MEMBER
    }

    fun isMe(member: GroupMember) = same(member.userId, me)

    /** Make or remove a preacher (a church's owner and admins, for members; never themselves or the owner). */
    fun canChoosePreacher(member: GroupMember): Boolean =
        isChurch && me != null && !isMe(member) && isModerator && member.role == "member" && !same(member.userId, ownerId)

    /** A preacher stepping down to member. */
    fun canStepDown(member: GroupMember): Boolean = isChurch && isMe(member) && member.role == "member" && member.preacher == true

    /** Mute, remove and ban. */
    fun canModerate(member: GroupMember): Boolean {
        if (me == null || isMe(member) || !isModerator) return false
        if (same(member.userId, ownerId)) return false
        return isOwner || !member.isLeader
    }

    /** Make or unmake a moderator, or hand the group over (owner only, never themselves). */
    fun canChooseRole(member: GroupMember): Boolean = isOwner && !isMe(member)
}
