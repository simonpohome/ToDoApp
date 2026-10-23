package com.deadlinesapp.deadlines;

import android.app.Activity;
import android.content.Context;

/** Leaving the app with the back button, the way Android apps normally do. */
public final class AppTask {

    /** Called by the app (main.cpp) when back is pressed with nothing left to close: the app goes
     *  to the background (still running, as it was), rather than being closed. */
    public static void moveToBack(Context context) {
        if (!(context instanceof Activity))
            return;
        final Activity activity = (Activity) context;
        activity.runOnUiThread(() -> activity.moveTaskToBack(true));
    }
}
