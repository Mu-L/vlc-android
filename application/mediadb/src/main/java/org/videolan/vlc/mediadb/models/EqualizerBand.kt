/*
 * ************************************************************************
 *  EqualizerBand.kt
 * *************************************************************************
 * Copyright © 2024 VLC authors and VideoLAN
 * Author: Nicolas POMEPUY
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 * **************************************************************************
 *
 *
 */

package org.videolan.vlc.mediadb.models

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey

@Entity(
        tableName = "equalizer_band",
        primaryKeys = ["index", "equalizer_entry"],
        foreignKeys = [ForeignKey(entity = EqualizerEntry::class,
                parentColumns = ["id"],
                childColumns = ["equalizer_entry"],
                onDelete = ForeignKey.CASCADE)]
)
data class EqualizerBand(
        @ColumnInfo(name = "index")
        val index: Int,
        @ColumnInfo(name = "value")
        val bandValue: Float,
) {
        @ColumnInfo(name = "equalizer_entry")
        var equalizerEntry: Long = 0
}
