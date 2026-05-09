package com.nm.nm_messenger

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

/**
 * Android home screen widget that displays the shared whiteboard.
 * The whiteboard image is rendered by Flutter and saved to shared storage.
 * Tapping the widget opens the app (directly to the whiteboard screen).
 */
class WhiteboardWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.whiteboard_widget)

            // Load the rendered whiteboard image from home_widget storage
            val imagePath = widgetData.getString("whiteboard_image", null)
            if (imagePath != null) {
                val imageFile = File(imagePath)
                if (imageFile.exists()) {
                    val bitmap = BitmapFactory.decodeFile(imageFile.absolutePath)
                    if (bitmap != null) {
                        views.setImageViewBitmap(R.id.whiteboard_image, bitmap)
                    }
                }
            }

            // Set click handler to open the app → whiteboard screen
            val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("nmwidget://whiteboard")
            )
            views.setOnClickPendingIntent(R.id.widget_container, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
