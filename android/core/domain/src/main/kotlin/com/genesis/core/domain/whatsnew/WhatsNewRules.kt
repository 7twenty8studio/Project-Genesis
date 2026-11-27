package com.genesis.core.domain.whatsnew

/**
 * Which one-time notes to show, as WhatsNewService on iOS: unseen ones whose
 * switch (if any) is on, newest first. A note with no switch is news only to
 * people who had the app before it shipped.
 */
object WhatsNewRules {
    data class Entry(val id: String, val flag: String? = null)

    fun pending(catalog: List<Entry>, seen: Set<String>, flagsOn: (String) -> Boolean): List<Entry> =
        catalog.reversed().filter { it.id !in seen && (it.flag == null || flagsOn(it.flag)) }

    /** A new install: features that shipped with the app aren't news; switched ones still are when they turn on. */
    fun shippedIds(catalog: List<Entry>): Set<String> = catalog.filter { it.flag == null }.mapTo(mutableSetOf()) { it.id }
}
