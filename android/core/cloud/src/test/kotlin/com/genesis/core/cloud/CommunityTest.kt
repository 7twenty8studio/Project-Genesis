package com.genesis.core.cloud

import com.genesis.core.cloud.community.CommunityApi
import com.genesis.core.cloud.community.CommunityError
import com.genesis.core.cloud.community.GroupStanding
import com.genesis.core.cloud.community.InviteCode
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertTrue

class CommunityTest {
    private val me = "aaaaaaaa-0000-0000-0000-000000000001"

    private fun api(respond: (HttpRequest) -> HttpResponse): Pair<CommunityApi, MutableList<HttpRequest>> {
        val sent = mutableListOf<HttpRequest>()
        val client = SupabaseClient("https://x.supabase.co", "anon", { request ->
            sent += request
            respond(request)
        })
        return CommunityApi(client, token = { "t" }, userId = { me.uppercase() }) to sent
    }

    @Test
    fun myGroupsLeavesOutClosedOnesAndSortsByName() {
        val (api, sent) = api {
            HttpResponse(200, """[
              {"role":"member","notifications":true,"group":{"id":"G2","name":"zion","description":"","invite_code":"ABCDE12345","deleted_at":null,"owner_id":"x"}},
              {"role":"leader","notifications":false,"preacher":false,"group":{"id":"G1","name":"Acts Group","invite_code":"Q","owner_id":"$me","sermons_enabled":true}},
              {"role":"member","notifications":true,"group":{"id":"G3","name":"Closed","deleted_at":"2026-11-01T00:00:00Z"}},
              {"role":"member","notifications":true,"group":null}
            ]""")
        }
        val groups = api.myGroups()
        assertEquals(listOf("Acts Group", "zion"), groups.map { it.name })
        assertEquals(GroupStanding.OWNER, groups[0].standing)
        assertTrue(groups[0].isChurch)
        assertEquals(GroupStanding.MEMBER, groups[1].standing)
        assertEquals("ABCDE-12345", groups[1].formattedInviteCode)
        assertEquals("g2", groups[1].id)
        val url = sent.single().url
        assertTrue(url.startsWith("https://x.supabase.co/rest/v1/group_members?select="), url)
        assertTrue("user_id=eq.$me" in url, url)
        assertEquals("Bearer t", sent.single().headers["Authorization"])
    }

    @Test
    fun joiningReadsTheOutcome() {
        val (api, sent) = api { HttpResponse(200, """{"group_id":"ABC","name":"Acts","status":"requested"}""") }
        val outcome = api.requestToJoin("ABCDE12345")
        assertEquals("abc", outcome.groupId)
        assertEquals(false, outcome.joined)
        assertEquals("https://x.supabase.co/rest/v1/rpc/request_to_join_group", sent.single().url)
        assertEquals("""{"p_code":"ABCDE12345"}""", sent.single().body)
    }

    @Test
    fun databaseCodesBecomeErrors() {
        val (api, _) = api { HttpResponse(400, """{"message":"invalid_code"}""") }
        assertEquals(CommunityError.Code("invalid_code"), assertFailsWith<CommunityError.Code> { api.requestToJoin("x") })
        val (dup, _) = api { HttpResponse(409, """{"message":"duplicate key value violates unique constraint"}""") }
        // A second "I prayed" is fine.
        dup.setPrayed(true, "p")
        val (denied, _) = api { HttpResponse(403, """{"message":"new row violates row-level security policy"}""") }
        assertIs<CommunityError.NotAllowed>(runCatching { denied.addPrayer("Pray", "g") }.exceptionOrNull())
    }

    @Test
    fun postsComeOldestFirst() {
        val (api, _) = api {
            HttpResponse(200, """[
              {"id":"2","group_id":"g","user_id":"u","display_name":"Ruth","body":"Second","created_at":"2026-11-27T10:00:00Z"},
              {"id":"1","group_id":"g","user_id":"u","display_name":"Ruth","day":3,"body":"First","created_at":"2026-11-27T09:00:00Z"}
            ]""")
        }
        assertEquals(listOf("First", "Second"), api.posts("g").map { it.body })
    }

    @Test
    fun inviteCodes() {
        assertEquals("ABCDE12345", InviteCode.clean(" abcde-12345 "))
        assertEquals("ABCDE-12345", InviteCode.format("ABCDE12345"))
        assertEquals("ABC", InviteCode.format("ABC"))
        assertEquals(false, InviteCode.isPlausible("ab-1"))
        assertEquals(true, InviteCode.isPlausible("abc-123"))
    }
}
