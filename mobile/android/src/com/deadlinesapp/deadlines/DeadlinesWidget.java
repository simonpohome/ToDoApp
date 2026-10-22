package com.deadlinesapp.deadlines;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.widget.RemoteViews;

/**
 * The home-screen widget: the Deadlines tab as a scrollable list.
 *
 * The app writes the list to files/widget.json whenever it saves and then calls refresh();
 * Android also calls onUpdate() every 30 minutes, so "today" / "in 3 days" stay right.
 * The cards themselves are made by DeadlinesWidgetService.
 */
public class DeadlinesWidget extends AppWidgetProvider {

    @Override
    public void onUpdate(Context context, AppWidgetManager manager, int[] ids) {
        updateAll(context, manager, ids);
        manager.notifyAppWidgetViewDataChanged(ids, R.id.widget_list);
    }

    /** Called by the app (main.cpp) after it has saved, so the widgets show the new list. */
    public static void refresh(Context context) {
        AppWidgetManager manager = AppWidgetManager.getInstance(context);
        int[] ids = manager.getAppWidgetIds(new ComponentName(context, DeadlinesWidget.class));
        if (ids.length == 0)
            return;
        updateAll(context, manager, ids);
        manager.notifyAppWidgetViewDataChanged(ids, R.id.widget_list);
    }

    /** Opens Android's "Add to home screen" dialog for the widget. False if the launcher can't. */
    public static boolean requestPin(Context context) {
        AppWidgetManager manager = AppWidgetManager.getInstance(context);
        if (!manager.isRequestPinAppWidgetSupported())
            return false;
        return manager.requestPinAppWidget(new ComponentName(context, DeadlinesWidget.class), null, null);
    }

    static void updateAll(Context context, AppWidgetManager manager, int[] ids) {
        WidgetData data = WidgetData.load(context);
        for (int id : ids) {
            RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_deadlines);
            views.setTextViewText(R.id.widget_subtitle, data.subtitle());

            // The scrolling list gets its cards from DeadlinesWidgetService. (The data URI keeps
            // each widget's adapter separate.)
            Intent service = new Intent(context, DeadlinesWidgetService.class);
            service.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id);
            service.setData(Uri.parse(service.toUri(Intent.URI_INTENT_SCHEME)));
            views.setRemoteAdapter(R.id.widget_list, service);
            views.setEmptyView(R.id.widget_list, R.id.widget_empty);

            // Tapping the header, the empty message or any card opens the app.
            PendingIntent open = openApp(context, 0, PendingIntent.FLAG_IMMUTABLE);
            views.setOnClickPendingIntent(R.id.widget_header, open);
            views.setOnClickPendingIntent(R.id.widget_empty, open);
            views.setPendingIntentTemplate(R.id.widget_list, openApp(context, 1, PendingIntent.FLAG_MUTABLE));

            manager.updateAppWidget(id, views);
        }
    }

    static PendingIntent openApp(Context context, int requestCode, int mutability) {
        Intent intent = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
        return PendingIntent.getActivity(context, requestCode, intent,
                                         PendingIntent.FLAG_UPDATE_CURRENT | mutability);
    }
}
