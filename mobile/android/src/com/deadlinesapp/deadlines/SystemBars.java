package com.deadlinesapp.deadlines;

import android.app.Activity;
import android.content.Context;
import android.os.Build;
import android.view.View;
import android.view.Window;
import android.view.WindowInsetsController;

/** Light or dark icons in the status and navigation bars, to match the app's light/dark look. */
public final class SystemBars {

    /** Called by the app (main.cpp) whenever it switches between light and dark. */
    public static void setDark(Context context, final boolean dark) {
        if (!(context instanceof Activity))
            return;
        final Activity activity = (Activity) context;
        activity.runOnUiThread(() -> {
            Window window = activity.getWindow();
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                WindowInsetsController controller = window.getInsetsController();
                if (controller == null)
                    return;
                int light = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
                          | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
                controller.setSystemBarsAppearance(dark ? 0 : light, light);   // light bars = dark icons
            } else {
                View decor = window.getDecorView();
                int light = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR;
                int flags = decor.getSystemUiVisibility();
                decor.setSystemUiVisibility(dark ? flags & ~light : flags | light);
            }
        });
    }
}
