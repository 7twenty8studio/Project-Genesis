package com.genesis.app.widget

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.FileNotFoundException

/**
 * Hands the launcher the widget's moving frames by name, so it reads them
 * itself. Sending ten pictures inside the widget's update is too big for
 * Android (the update fails and the widget never draws). Read-only, and only
 * the painted frames in WidgetArt/frames: nothing personal is in them.
 */
class WidgetFrameProvider : ContentProvider() {
    override fun onCreate() = true

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw SecurityException("Read only")
        val context = context ?: throw FileNotFoundException()
        val name = uri.lastPathSegment ?: throw FileNotFoundException()
        if (!NAME.matches(name)) throw FileNotFoundException()
        val file = File(WidgetFrames.folder(context), name)
        if (!file.exists()) throw FileNotFoundException()
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun getType(uri: Uri) = "image/jpeg"
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?) = 0

    private companion object {
        val NAME = Regex("v\\d+-[A-Za-z0-9_]+-[a-z]+-\\d+\\.jpg")
    }
}
