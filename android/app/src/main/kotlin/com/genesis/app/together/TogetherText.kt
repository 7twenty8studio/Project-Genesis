package com.genesis.app.together

import android.text.format.DateUtils
import com.genesis.app.R
import com.genesis.core.cloud.Timestamps
import com.genesis.core.cloud.community.CommunityError
import com.genesis.core.cloud.community.GroupStanding
import com.genesis.core.cloud.community.ReportReason

/** The words for an error, as CommunityError's descriptions on iOS. */
internal fun CommunityError.text(): Int = when (this) {
    is CommunityError.SignInRequired -> R.string.error_sign_in
    is CommunityError.Offline -> R.string.error_offline
    is CommunityError.Duplicate -> R.string.error_duplicate
    is CommunityError.NotAllowed -> R.string.error_not_allowed
    is CommunityError.Unknown -> R.string.error_unknown
    is CommunityError.Code -> when (code) {
        "objectionable_content" -> R.string.error_objectionable
        "rate_limited" -> R.string.error_rate_limited
        "name_required" -> R.string.error_name_required
        "invalid_name" -> R.string.error_invalid_name
        "invalid_code" -> R.string.error_invalid_code
        "group_full" -> R.string.error_group_full
        "groups_off" -> R.string.error_groups_off
        "too_many_groups" -> R.string.error_too_many_groups
        "leaders_only" -> R.string.error_leaders_only
        "last_leader" -> R.string.error_last_leader
        "not_allowed" -> R.string.error_cant
        "not_found" -> R.string.error_not_found
        "not_signed_in" -> R.string.error_sign_in
        "banned" -> R.string.error_banned
        "approval_required" -> R.string.error_approval_required
        "too_many_requests" -> R.string.error_too_many_requests
        "owner_only" -> R.string.error_owner_only
        "moderators_only" -> R.string.error_moderators_only
        "owner_role_fixed" -> R.string.error_owner_role_fixed
        "use_leave" -> R.string.error_use_leave
        "not_a_member" -> R.string.error_not_a_member
        "invalid_challenge" -> R.string.error_invalid_challenge
        "too_many_challenges" -> R.string.five_challenges
        "challenge_ended" -> R.string.error_challenge_ended
        "not_started" -> R.string.error_not_started
        "invalid_item" -> R.string.error_invalid_item
        else -> R.string.error_unknown
    }
}

/** Owner, Moderator (Admin in a church), Preacher or Member. */
internal fun GroupStanding.title(inChurch: Boolean): Int = when (this) {
    GroupStanding.OWNER -> R.string.role_owner
    GroupStanding.MODERATOR -> if (inChurch) R.string.role_admin else R.string.role_moderator
    GroupStanding.PREACHER -> R.string.role_preacher
    GroupStanding.MEMBER -> R.string.role_member
}

internal val ReportReason.title: Int
    get() = when (this) {
        ReportReason.ABUSIVE -> R.string.reason_abusive
        ReportReason.SEXUAL -> R.string.reason_sexual
        ReportReason.SPAM -> R.string.reason_spam
        ReportReason.PRIVATE -> R.string.reason_private
        ReportReason.OTHER -> R.string.reason_other
    }

/** "5 minutes ago", "Yesterday", in the phone's language. */
internal fun relativeTime(timestamp: String): String {
    val millis = Timestamps.millis(timestamp) ?: return ""
    return DateUtils.getRelativeTimeSpanString(millis, System.currentTimeMillis(), DateUtils.MINUTE_IN_MILLIS).toString()
}
