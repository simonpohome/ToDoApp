package com.deadlinesapp.deadlines;

import android.content.Context;
import android.content.Intent;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.os.Build;
import android.text.SpannableString;
import android.text.Spanned;
import android.text.style.StrikethroughSpan;
import android.widget.RemoteViews;
import android.widget.RemoteViewsService;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/** Makes the widget's cards: one per deadline, styled like the app's Deadlines tab. */
public class DeadlinesWidgetService extends RemoteViewsService {

    @Override
    public RemoteViewsFactory onGetViewFactory(Intent intent) {
        return new Cards(getApplicationContext());
    }

    static final class Cards implements RemoteViewsFactory {
        // The app's colours (Main.qml).
        static final int TEXT = Color.parseColor("#1c1c1e");
        static final int MUTED = Color.parseColor("#8e8e93");
        static final int LINE = Color.parseColor("#dde6f1");
        static final int DONE = Color.parseColor("#c7c7cc");
        static final int GREEN = Color.parseColor("#8fd6a5");    // more than a week left
        static final int YELLOW = Color.parseColor("#f5d77a");   // 3-7 days left
        static final int RED = Color.parseColor("#f2a0a0");      // 2 days or less
        static final int OVERDUE = Color.parseColor("#d9686b");
        static final DateTimeFormatter DAY = DateTimeFormatter.ofPattern("EEE d MMM", Locale.UK);

        private final Context context;
        private List<WidgetData.Item> items = new ArrayList<>();

        Cards(Context context) { this.context = context; }

        @Override public void onCreate() {}
        @Override public void onDestroy() {}
        @Override public void onDataSetChanged() { items = WidgetData.load(context).items; }
        @Override public int getCount() { return items.size(); }
        @Override public RemoteViews getLoadingView() { return null; }
        @Override public int getViewTypeCount() { return 1; }
        @Override public long getItemId(int position) { return position; }
        @Override public boolean hasStableIds() { return false; }

        @Override
        public RemoteViews getViewAt(int position) {
            RemoteViews card = new RemoteViews(context.getPackageName(), R.layout.widget_item);
            if (position >= items.size())
                return card;
            WidgetData.Item item = items.get(position);

            long days;
            String when;
            try {
                LocalDate due = LocalDate.parse(item.due);
                days = ChronoUnit.DAYS.between(LocalDate.now(), due);
                when = due.format(DAY);
            } catch (Exception e) {
                days = 0;
                when = item.due;
            }
            if (!item.time.isEmpty())
                when += " " + item.time;
            when += "  ·  " + relative(days);

            // Everything coloured follows the time left, as in the app; finished ones go grey.
            int mark = item.done ? DONE : days > 7 ? GREEN : days > 2 ? YELLOW : RED;
            card.setInt(R.id.item_border, "setColorFilter", item.done ? Color.WHITE : mark);
            card.setInt(R.id.item_dot, "setColorFilter", mark);
            // The subject tag in the subject's colour: tint its rounded background (Android 12+),
            // or on older phones give it a plain coloured background.
            int subjectColor = parseColor(item.color, LINE);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                card.setColorStateList(R.id.item_subject, "setBackgroundTintList", ColorStateList.valueOf(subjectColor));
            else
                card.setInt(R.id.item_subject, "setBackgroundColor", subjectColor);
            card.setFloat(R.id.item_subject, "setAlpha", item.done ? 0.45f : 1f);
            card.setTextViewText(R.id.item_subject, item.subject);
            card.setTextViewText(R.id.item_when, struck(when, item.done));
            card.setTextColor(R.id.item_when, item.done ? DONE : days < 0 ? OVERDUE : MUTED);
            card.setTextViewText(R.id.item_title, struck(item.assignment, item.done));
            card.setTextColor(R.id.item_title, item.done ? DONE : TEXT);
            card.setOnClickFillInIntent(R.id.item_root, new Intent());   // opens the app
            return card;
        }

        static String relative(long days) {
            if (days == 0) return "today";
            if (days == 1) return "tomorrow";
            if (days == -1) return "yesterday";
            return days > 0 ? "in " + days + " days" : (-days) + " days ago";
        }

        static CharSequence struck(String text, boolean done) {
            if (!done)
                return text;
            SpannableString s = new SpannableString(text);
            s.setSpan(new StrikethroughSpan(), 0, s.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
            return s;
        }

        static int parseColor(String color, int fallback) {
            try {
                return Color.parseColor(color);
            } catch (Exception e) {
                return fallback;
            }
        }
    }
}
