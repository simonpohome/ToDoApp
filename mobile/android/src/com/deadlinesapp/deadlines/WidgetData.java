package com.deadlinesapp.deadlines;

import android.content.Context;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.List;

/** The deadlines list as the app last saved it for the widget (files/widget.json, see main.cpp). */
final class WidgetData {

    static final class Item {
        String subject, assignment, due, time, color;   // due "" = no due date
        boolean done, pinned;
    }

    final List<Item> items = new ArrayList<>();
    int upcoming;
    // The app's appearance setting: "system" (follow the phone), "light" or "dark".
    String theme = "system";

    /** 0 = always light, 1 = always dark, -1 = follow the phone. */
    int forcedLook() {
        return theme.equals("light") ? 0 : theme.equals("dark") ? 1 : -1;
    }

    static WidgetData load(Context context) {
        WidgetData data = new WidgetData();
        try {
            File file = new File(context.getFilesDir(), "widget.json");
            if (!file.exists())
                return data;
            String text = new String(Files.readAllBytes(file.toPath()), StandardCharsets.UTF_8);
            JSONObject root = new JSONObject(text);
            data.theme = root.optString("theme", "system");
            JSONArray tasks = root.getJSONArray("tasks");
            for (int i = 0; i < tasks.length(); i++) {
                JSONObject t = tasks.getJSONObject(i);
                Item item = new Item();
                item.subject = t.optString("subject");
                item.assignment = t.optString("assignment");
                item.due = t.optString("due");
                item.time = t.optString("time");
                item.color = t.optString("color");
                item.done = t.optBoolean("done");
                item.pinned = t.optBoolean("pinned");
                if (!item.done)
                    data.upcoming++;
                data.items.add(item);
            }
        } catch (Exception e) {
            // Unreadable or half-written: show what we have (nothing) rather than crash the launcher.
        }
        return data;
    }

    String subtitle() {
        return items.isEmpty() ? "Nothing due yet" : upcoming + " upcoming";
    }
}
