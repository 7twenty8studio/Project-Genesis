package com.genesis.app.together

import com.genesis.app.account.AccountService
import com.genesis.core.cloud.community.CommunityApi
import com.genesis.core.cloud.community.CommunityError
import com.genesis.core.cloud.community.CommunityProfile
import com.genesis.core.cloud.community.ContentKind
import com.genesis.core.cloud.community.GroupJoinOutcome
import com.genesis.core.cloud.community.GroupSummary
import com.genesis.core.cloud.community.ReportReason
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext

data class TogetherState(
    val hasLoaded: Boolean = false,
    val userId: String? = null,
    val profile: CommunityProfile? = null,
    val profileLoaded: Boolean = false,
    val groups: List<GroupSummary> = emptyList(),
    /** People the signed-in person has blocked: their posts and prayers aren't shown. */
    val blocked: Set<String> = emptySet(),
    val error: CommunityError? = null,
    val isWorking: Boolean = false,
) {
    val isSignedIn: Boolean get() = userId != null
    val needsDisplayName: Boolean get() = isSignedIn && profileLoaded && profile == null
}

/**
 * The signed-in person's groups, profile and blocks, as CommunityStore on
 * iOS. Every rule (membership, leaders, names, the word filter, rate limits)
 * is the database's; this only asks and shows.
 */
class CommunityStore(private val account: AccountService, private val scope: CoroutineScope) {
    private val _state = MutableStateFlow(TogetherState())
    val state: StateFlow<TogetherState> = _state.asStateFlow()

    val api: CommunityApi? = account.client?.let { client ->
        CommunityApi(
            client,
            token = { runCatching { runBlocking { account.accessToken() } }.getOrElse { throw CommunityError.SignInRequired() } },
            userId = { account.state.value.user?.id },
        )
    }

    fun isMine(user: String): Boolean = user.equals(state.value.userId, ignoreCase = true)

    suspend fun refresh() {
        val api = api
        val user = account.state.value.user?.id?.lowercase()
        if (api == null || user == null) {
            _state.value = TogetherState(hasLoaded = true)
            return
        }
        if (_state.value.userId != user) _state.value = TogetherState(userId = user)
        try {
            val (profile, groups, blocked) = withContext(Dispatchers.IO) { Triple(api.profile(), api.myGroups(), api.blockedUsers()) }
            _state.update { it.copy(hasLoaded = true, userId = user, profile = profile, profileLoaded = true, groups = groups, blocked = blocked, error = null) }
        } catch (error: CommunityError) {
            _state.update { it.copy(hasLoaded = true, userId = user, error = error) }
        }
    }

    suspend fun refreshGroups() {
        val api = api ?: return
        runCatching { withContext(Dispatchers.IO) { api.myGroups() } }.onSuccess { groups -> _state.update { it.copy(groups = groups) } }
    }

    fun group(id: String): GroupSummary? = state.value.groups.firstOrNull { it.id == id }

    /** Runs an action, showing its error; true when it worked. */
    suspend fun perform(action: (CommunityApi) -> Unit): Boolean {
        val api = api ?: return false
        _state.update { it.copy(isWorking = true, error = null) }
        return try {
            withContext(Dispatchers.IO) { action(api) }
            _state.update { it.copy(isWorking = false) }
            true
        } catch (error: CommunityError) {
            _state.update { it.copy(isWorking = false, error = error) }
            false
        }
    }

    fun clearError() = _state.update { it.copy(error = null) }

    suspend fun setDisplayName(name: String): Boolean {
        if (!perform { it.setDisplayName(name) }) return false
        refresh()
        return true
    }

    suspend fun acceptCommunityTerms(): Boolean {
        if (!perform { it.acceptCommunityTerms() }) return false
        refresh()
        return true
    }

    suspend fun createGroup(name: String, description: String): String? {
        var id: String? = null
        if (!perform { id = it.createGroup(name, description) }) return null
        refreshGroups()
        return id
    }

    suspend fun requestToJoin(code: String): GroupJoinOutcome? {
        var outcome: GroupJoinOutcome? = null
        if (!perform { outcome = it.requestToJoin(code) }) return null
        refreshGroups()
        return outcome
    }

    suspend fun leaveGroup(id: String): Boolean {
        if (!perform { it.leaveGroup(id) }) return false
        _state.update { state -> state.copy(groups = state.groups.filterNot { it.id == id }) }
        return true
    }

    suspend fun block(user: String): Boolean {
        if (!perform { it.block(user) }) return false
        _state.update { it.copy(blocked = it.blocked + user.lowercase()) }
        return true
    }

    suspend fun report(kind: ContentKind, id: String, reason: ReportReason): Boolean = perform { it.report(kind, id, reason) }
}
