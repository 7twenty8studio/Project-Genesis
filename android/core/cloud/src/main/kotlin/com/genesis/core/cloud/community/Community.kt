package com.genesis.core.cloud.community

import com.genesis.core.cloud.SupabaseClient
import com.genesis.core.cloud.SupabaseError
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

// Church groups, as CommunityModels.swift: rows of the tables in
// supabase/migrations/20261003000000_groups_community.sql and later.

/** Your name as others see it, and whether you've agreed to the community guidelines. */
@Serializable
data class CommunityProfile(
    @SerialName("user_id") val userId: String,
    @SerialName("display_name") val displayName: String,
    @SerialName("community_terms_accepted_at") val termsAcceptedAt: String? = null,
) {
    val hasAcceptedTerms: Boolean get() = termsAcceptedAt != null
}

/** How the signed-in person stands in a group (GroupStanding on iOS). */
enum class GroupStanding { OWNER, MODERATOR, PREACHER, MEMBER }

/** A group you belong to, with your role in it. */
data class GroupSummary(
    val id: String,
    val name: String,
    val description: String,
    val inviteCode: String,
    /** "leader" (a moderator; the owner is one too) or "member". */
    val role: String,
    val notifications: Boolean,
    val isOwner: Boolean,
    val requiresApproval: Boolean,
    val isChurch: Boolean,
    val isPreacher: Boolean,
    val planTitle: String? = null,
    val ownerId: String? = null,
) {
    val isLeader: Boolean get() = role == "leader"

    val standing: GroupStanding
        get() = when {
            isOwner -> GroupStanding.OWNER
            isLeader -> GroupStanding.MODERATOR
            isChurch && isPreacher -> GroupStanding.PREACHER
            else -> GroupStanding.MEMBER
        }

    /** The invite code as people type it: ABCDE-12345. */
    val formattedInviteCode: String get() = InviteCode.format(inviteCode)
}

@Serializable
data class GroupMember(
    @SerialName("group_id") val groupId: String,
    @SerialName("user_id") val userId: String,
    val role: String,
    @SerialName("display_name") val displayName: String,
    @SerialName("joined_at") val joinedAt: String,
    @SerialName("muted_until") val mutedUntil: String? = null,
    val preacher: Boolean? = null,
) {
    val isLeader: Boolean get() = role == "leader"
}

@Serializable
data class GroupPrayer(
    val id: String,
    @SerialName("group_id") val groupId: String,
    @SerialName("user_id") val userId: String,
    @SerialName("display_name") val displayName: String,
    val body: String,
    @SerialName("prayed_count") val prayedCount: Int = 0,
    @SerialName("created_at") val createdAt: String,
    @SerialName("answered_at") val answeredAt: String? = null,
    @SerialName("hidden_at") val hiddenAt: String? = null,
)

/** A message in a group's discussion; `day` ties it to a plan day. */
@Serializable
data class GroupPost(
    val id: String,
    @SerialName("group_id") val groupId: String,
    @SerialName("user_id") val userId: String,
    @SerialName("display_name") val displayName: String,
    val day: Int? = null,
    val body: String,
    @SerialName("created_at") val createdAt: String,
    @SerialName("hidden_at") val hiddenAt: String? = null,
)

@Serializable
data class GroupAnnouncement(
    val id: String,
    @SerialName("group_id") val groupId: String,
    @SerialName("user_id") val userId: String,
    @SerialName("display_name") val displayName: String,
    val title: String,
    val body: String,
    @SerialName("created_at") val createdAt: String,
)

/** What joining with a code did: joined, or asked a group that approves its members. */
@Serializable
data class GroupJoinOutcome(
    @SerialName("group_id") val groupId: String,
    val name: String,
    val status: String,
) {
    val joined: Boolean get() = status == "joined"
}

/** Anything people post, for reporting and removing (ContentKind on iOS). */
enum class ContentKind(val rawValue: String) {
    GROUP_PRAYER("group_prayer"),
    GROUP_POST("group_post"),
    GROUP_ANNOUNCEMENT("group_announcement"),
}

/** Report reasons: the value sent is English, as iOS sends it. */
enum class ReportReason(val value: String) {
    ABUSIVE("Abusive or hateful"),
    SEXUAL("Sexual or inappropriate"),
    SPAM("Spam or advertising"),
    PRIVATE("Shares private information"),
    OTHER("Something else"),
}

object InviteCode {
    /** Letters and digits only, upper case: "abcde-12345 " → "ABCDE12345". */
    fun clean(typed: String): String = typed.filter { it.isLetterOrDigit() }.uppercase()

    fun format(code: String): String = if (code.length == 10) "${code.take(5)}-${code.takeLast(5)}" else code

    /** Join is offered from six characters, as on iOS. */
    fun isPlausible(typed: String): Boolean = clean(typed).length >= 6
}

/**
 * Why something failed, as a short code the app turns into words
 * (CommunityError.from on iOS reads the database's codes the same way).
 */
sealed class CommunityError : Exception() {
    class SignInRequired : CommunityError()
    class Offline : CommunityError()
    /** It was already there (a second report, "I prayed" twice). */
    class Duplicate : CommunityError()
    /** One of the database's own codes ("invalid_code", "rate_limited"…). */
    data class Code(val code: String) : CommunityError()
    class NotAllowed : CommunityError()
    class Unknown : CommunityError()

    companion object {
        val knownCodes = setOf(
            "objectionable_content", "rate_limited", "name_required", "invalid_name", "invalid_code", "group_full",
            "groups_off", "too_many_groups", "leaders_only", "last_leader", "not_allowed", "not_found", "not_signed_in",
            "banned", "approval_required", "too_many_requests", "owner_only", "moderators_only", "owner_role_fixed",
            "use_leave", "not_a_member", "invalid_duration", "invalid_reason", "already_nudged", "nudge_limit", "nudges_off",
        )

        fun from(error: Throwable): CommunityError = when (error) {
            is CommunityError -> error
            is SupabaseError.Network -> Offline()
            is SupabaseError.Http -> when {
                error.message in knownCodes -> Code(error.message.orEmpty())
                error.status == 409 || error.message.orEmpty().contains("duplicate key") -> Duplicate()
                error.status == 401 -> SignInRequired()
                error.status == 403 || error.message.orEmpty().contains("row-level security") -> NotAllowed()
                else -> Unknown()
            }
            else -> Unknown()
        }
    }
}

/**
 * Groups on the server, as SupabaseCommunityBackend on iOS: the same
 * tables, functions and columns. Blocking: call off the main thread.
 * `token` gives a fresh access token (or throws SignInRequired).
 */
class CommunityApi(private val client: SupabaseClient, private val token: () -> String, private val userId: () -> String?) {
    private val json = Json { ignoreUnknownKeys = true }

    private fun me(): String = userId()?.lowercase() ?: throw CommunityError.SignInRequired()

    private fun <T> wrap(block: () -> T): T = try {
        block()
    } catch (error: Throwable) {
        throw CommunityError.from(error)
    }

    private inline fun <reified T> get(table: String, vararg query: Pair<String, String>): List<T> = wrap {
        json.decodeFromString<List<T>>(client.select(table, query.toList(), token()).ifEmpty { "[]" })
    }

    private fun rpc(name: String, vararg params: Pair<String, JsonElement>): String = wrap {
        client.rpc(name, buildJsonObject { params.forEach { (key, value) -> put(key, value) } }.toString(), token())
    }

    private fun insert(table: String, vararg values: Pair<String, JsonElement>) = wrap {
        client.insert(table, buildJsonObject { values.forEach { (key, value) -> put(key, value) } }.toString(), token())
    }

    private fun insertIgnoringDuplicate(table: String, vararg values: Pair<String, JsonElement>) {
        try {
            insert(table, *values)
        } catch (_: CommunityError.Duplicate) {
            // Already there.
        }
    }

    private fun delete(table: String, vararg query: Pair<String, String>) = wrap { client.delete(table, query.toList(), token()) }


    // Profile and safety

    fun profile(): CommunityProfile? =
        get<CommunityProfile>("profiles", "select" to "user_id,display_name,community_terms_accepted_at", "user_id" to "eq.${me()}").firstOrNull()

    fun setDisplayName(name: String) {
        rpc("set_display_name", "p_name" to JsonPrimitive(name.trim()))
    }

    fun acceptCommunityTerms() {
        rpc("accept_community_terms")
    }

    @Serializable
    private data class BlockRow(val blocked: String)

    fun blockedUsers(): Set<String> = get<BlockRow>("user_blocks", "select" to "blocked").mapTo(mutableSetOf()) { it.blocked.lowercase() }

    fun block(user: String) = insertIgnoringDuplicate("user_blocks", "blocked" to JsonPrimitive(user.lowercase()))

    fun report(kind: ContentKind, id: String, reason: ReportReason) = insertIgnoringDuplicate(
        "content_reports",
        "content_type" to JsonPrimitive(kind.rawValue),
        "content_id" to JsonPrimitive(id.lowercase()),
        "reason" to JsonPrimitive(reason.value),
    )

    fun remove(kind: ContentKind, id: String) {
        rpc("remove_content", "p_type" to JsonPrimitive(kind.rawValue), "p_id" to JsonPrimitive(id.lowercase()))
    }

    // Groups

    @Serializable
    private data class MembershipRow(
        val role: String,
        val notifications: Boolean = true,
        val preacher: Boolean? = null,
        val group: GroupRow? = null,
    )

    @Serializable
    private data class GroupRow(
        val id: String,
        val name: String,
        val description: String = "",
        @SerialName("invite_code") val inviteCode: String = "",
        @SerialName("plan_title") val planTitle: String? = null,
        @SerialName("deleted_at") val deletedAt: String? = null,
        @SerialName("owner_id") val ownerId: String? = null,
        @SerialName("requires_approval") val requiresApproval: Boolean? = null,
        @SerialName("sermons_enabled") val sermonsEnabled: Boolean? = null,
    )

    fun myGroups(): List<GroupSummary> {
        val me = me()
        val rows = get<MembershipRow>(
            "group_members",
            "select" to "role,notifications,preacher,group:groups(id,name,description,invite_code,plan_title,deleted_at,owner_id,requires_approval,sermons_enabled)",
            "user_id" to "eq.$me",
        )
        return rows.mapNotNull { row ->
            val group = row.group?.takeIf { it.deletedAt == null } ?: return@mapNotNull null
            GroupSummary(
                id = group.id.lowercase(),
                name = group.name,
                description = group.description,
                inviteCode = group.inviteCode,
                role = row.role,
                notifications = row.notifications,
                isOwner = group.ownerId?.lowercase() == me,
                requiresApproval = group.requiresApproval ?: false,
                isChurch = group.sermonsEnabled ?: false,
                isPreacher = row.preacher ?: false,
                planTitle = group.planTitle,
                ownerId = group.ownerId?.lowercase(),
            )
        }.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })
    }

    /** Starts a group (no reading plan yet); its id. */
    fun createGroup(name: String, description: String): String {
        val reply = rpc(
            "create_group",
            "p_name" to JsonPrimitive(name.trim()),
            "p_description" to JsonPrimitive(description.trim()),
            "p_plan_id" to JsonNull,
            "p_plan_title" to JsonNull,
            "p_plan_books" to JsonNull,
            "p_plan_days" to JsonNull,
            "p_plan_start" to JsonNull,
        )
        return reply.trim().trim('"').lowercase().takeIf { it.length >= 32 } ?: throw CommunityError.Unknown()
    }

    /** Joins with an invite code, or asks to join a group that approves its members. */
    fun requestToJoin(code: String): GroupJoinOutcome {
        val reply = rpc("request_to_join_group", "p_code" to JsonPrimitive(code))
        return runCatching { json.decodeFromString<GroupJoinOutcome>(reply) }.getOrElse { throw CommunityError.Unknown() }
            .let { it.copy(groupId = it.groupId.lowercase()) }
    }

    fun leaveGroup(group: String) {
        rpc("leave_group", "p_group" to JsonPrimitive(group))
    }

    fun members(group: String): List<GroupMember> = get(
        "group_members",
        "select" to "group_id,user_id,role,display_name,joined_at,muted_until,preacher",
        "group_id" to "eq.$group",
        "order" to "joined_at.asc",
    )

    fun prayers(group: String): List<GroupPrayer> = get(
        "group_prayers",
        "select" to "id,group_id,user_id,display_name,body,prayed_count,created_at,answered_at,hidden_at",
        "group_id" to "eq.$group",
        "order" to "created_at.desc",
        "limit" to "200",
    )

    @Serializable
    private data class MarkRow(@SerialName("prayer_id") val prayerId: String)

    fun myPrayerMarks(prayers: Collection<String>): Set<String> {
        if (prayers.isEmpty()) return emptySet()
        return get<MarkRow>("group_prayer_marks", "select" to "prayer_id", "prayer_id" to "in.(${prayers.joinToString(",")})")
            .mapTo(mutableSetOf()) { it.prayerId.lowercase() }
    }

    fun addPrayer(body: String, group: String) =
        insert("group_prayers", "group_id" to JsonPrimitive(group), "body" to JsonPrimitive(body.trim()))

    fun setPrayed(prayed: Boolean, prayer: String) {
        if (prayed) {
            insertIgnoringDuplicate("group_prayer_marks", "prayer_id" to JsonPrimitive(prayer))
        } else {
            delete("group_prayer_marks", "prayer_id" to "eq.$prayer", "user_id" to "eq.${me()}")
        }
    }

    fun setAnswered(answered: Boolean, prayer: String) {
        rpc("set_prayer_answered", "p_prayer" to JsonPrimitive(prayer), "p_answered" to JsonPrimitive(answered))
    }

    /** The newest 500, oldest first. */
    fun posts(group: String): List<GroupPost> = get<GroupPost>(
        "group_posts",
        "select" to "id,group_id,user_id,display_name,day,body,created_at,hidden_at",
        "group_id" to "eq.$group",
        "order" to "created_at.desc",
        "limit" to "500",
    ).reversed()

    fun addPost(body: String, day: Int?, group: String) = insert(
        "group_posts",
        "group_id" to JsonPrimitive(group),
        "body" to JsonPrimitive(body.trim()),
        "day" to (day?.let(::JsonPrimitive) ?: JsonNull),
    )

    fun announcements(group: String): List<GroupAnnouncement> = get(
        "group_announcements",
        "select" to "id,group_id,user_id,display_name,title,body,created_at",
        "group_id" to "eq.$group",
        "order" to "created_at.desc",
        "limit" to "100",
    )

    /** Posts an announcement and asks the server to notify members (best effort). */
    fun addAnnouncement(title: String, body: String, group: String) {
        val id = java.util.UUID.randomUUID().toString()
        insert(
            "group_announcements",
            "id" to JsonPrimitive(id),
            "group_id" to JsonPrimitive(group),
            "title" to JsonPrimitive(title.trim()),
            "body" to JsonPrimitive(body.trim()),
        )
        runCatching { client.callFunction("group-notify", buildJsonObject { put("announcementID", id) }.toString(), token()) }
    }


    // Group settings and moderation (GroupMembersView and GroupModerationView on iOS)

    private fun groupAndUser(group: String, user: String) =
        arrayOf("p_group" to JsonPrimitive(group.lowercase()), "p_user" to JsonPrimitive(user.lowercase()))

    /** A fresh invite code; the old one stops working. */
    fun newInviteCode(group: String): String =
        rpc("new_invite_code", "p_group" to JsonPrimitive(group)).trim().trim('"')

    fun deleteGroup(group: String) {
        rpc("delete_group", "p_group" to JsonPrimitive(group))
    }

    /** "leader" (moderator) or "member"; owner only. */
    fun setRole(role: String, user: String, group: String) {
        rpc("set_member_role", *groupAndUser(group, user), "p_role" to JsonPrimitive(role))
    }

    fun setChurchRole(role: ChurchMemberRole, user: String, group: String) {
        rpc("set_church_role", *groupAndUser(group, user), "p_role" to JsonPrimitive(role.rawValue))
    }

    fun removeMember(user: String, group: String) {
        rpc("remove_member", *groupAndUser(group, user))
    }

    fun transferOwnership(group: String, user: String) {
        rpc("transfer_group_ownership", *groupAndUser(group, user))
    }

    fun banMember(user: String, group: String, reason: String) {
        rpc("ban_member", *groupAndUser(group, user), "p_reason" to JsonPrimitive(reason.trim().take(300)))
    }

    fun unbanMember(user: String, group: String) {
        rpc("unban_member", *groupAndUser(group, user))
    }

    /** Mutes for `hours` (0 unmutes). */
    fun muteMember(user: String, group: String, hours: Int) {
        rpc("mute_member", *groupAndUser(group, user), "p_hours" to JsonPrimitive(hours.coerceIn(0, 720)))
    }

    fun bans(group: String): List<GroupBan> = get(
        "group_bans",
        "select" to "group_id,user_id,display_name,reason,created_at",
        "group_id" to "eq.$group",
        "order" to "created_at.desc",
    )

    fun joinRequests(group: String): List<GroupJoinRequest> = get(
        "group_join_requests",
        "select" to "group_id,user_id,display_name,created_at,group_name",
        "group_id" to "eq.$group",
        "order" to "created_at.asc",
    )

    fun answerJoinRequest(user: String, group: String, accept: Boolean) {
        rpc("answer_join_request", *groupAndUser(group, user), "p_accept" to JsonPrimitive(accept))
    }

    fun setRequiresApproval(required: Boolean, group: String) {
        rpc("set_group_approval", "p_group" to JsonPrimitive(group), "p_required" to JsonPrimitive(required))
    }

    fun reports(group: String): List<GroupReport> = wrap {
        json.decodeFromString<List<GroupReport>>(rpc("group_reports", "p_group" to JsonPrimitive(group)).ifBlank { "[]" }.let { if (it == "null") "[]" else it })
    }

    fun reviewReport(kind: ContentKind, id: String, action: ReportAction) {
        rpc("review_group_report", "p_type" to JsonPrimitive(kind.rawValue), "p_id" to JsonPrimitive(id.lowercase()), "p_action" to JsonPrimitive(action.rawValue))
    }

    fun unblock(user: String) = delete("user_blocks", "blocker" to "eq.${me()}", "blocked" to "eq.${user.lowercase()}")
}
