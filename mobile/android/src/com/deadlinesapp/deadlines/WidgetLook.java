package com.deadlinesapp.deadlines;

import android.content.Context;
import android.content.res.Configuration;
import android.graphics.Color;
import android.os.Build;
import android.widget.RemoteViews;

/**
 * The widget's light/dark look: always light, always dark (the app's appearance setting is Light
 * or Dark), or following the phone (System).
 *
 * Every colour and background is set explicitly in every mode, never left to the layout's default:
 * the launcher reuses the widget's views, so anything not set again would keep the previous mode's
 * colour (light cards left over after switching to dark, for example).
 */
final class WidgetLook {
    // The app's colours (Main.qml), as {light, dark}.
    static final int[] TEXT = pair("#1c1c1e", "#eef2f7");
    static final int[] MUTED = pair("#8e8e93", "#8b95a5");
    static final int[] CARD = pair("#ffffff", "#1d2430");
    static final int[] DONE = pair("#c7c7cc", "#5c6676");
    static final int[] GREEN = pair("#8fd6a5", "#7cc795");    // more than a week left
    static final int[] YELLOW = pair("#f5d77a", "#e3c66c");   // 3-7 days left
    static final int[] RED = pair("#f2a0a0", "#e39595");      // 2 days or less
    static final int[] PURPLE = pair("#c4b1f5", "#b29de6");   // no due date
    static final int[] OVERDUE = pair("#d9686b", "#f08e90");

    private final Context context;
    private final int look;   // 0 = always light, 1 = always dark, -1 = follow the phone

    WidgetLook(Context context, WidgetData data) {
        this.context = context;
        this.look = data.forcedLook();
    }

    /** Calls `method` (e.g. "setTextColor") on the view with this look's colour from {light, dark}. */
    void color(RemoteViews views, int viewId, String method, int[] lightDark) {
        if (look >= 0)
            views.setInt(viewId, method, lightDark[look]);
        else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            views.setColorInt(viewId, method, lightDark[0], lightDark[1]);   // the launcher switches live
        else
            views.setInt(viewId, method, lightDark[phoneIsDark() ? 1 : 0]);
    }

    /** Sets the view's background: the fixed light or dark drawable, or the one that follows the phone. */
    void background(RemoteViews views, int viewId, int followPhone, int light, int dark) {
        views.setInt(viewId, "setBackgroundResource", look == 1 ? dark : look == 0 ? light : followPhone);
    }

    private boolean phoneIsDark() {
        int mode = context.getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK;
        return mode == Configuration.UI_MODE_NIGHT_YES;
    }

    private static int[] pair(String light, String dark) {
        return new int[] { Color.parseColor(light), Color.parseColor(dark) };
    }
}
