package com.deadlinesapp.deadlines;

import android.content.Context;
import android.content.Intent;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.os.Build;
import android.text.SpannableString;
import android.text.Spanned;
import android.text.style.StrikethroughSpan;
import android.view.View;
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
        static final int LINE = Color.parseColor("#dde6f1");   // a subject without a colour yet
        static final DateTimeFormatter DAY = DateTimeFormatter.ofPattern("EEE d MMM", Locale.UK);

        private final Context context;
        private List<WidgetData.Item> items = new ArrayList<>();
        private WidgetLook look;

        Cards(Context context) {
            this.context = context;
            this.look = new WidgetLook(context, new WidgetData());
        }

        @Override public void onCreate() {}
        @Override public void onDestroy() {}
        @Override public void onDataSetChanged() {
            WidgetData data = WidgetData.load(context);
            items = data.items;
            look = new WidgetLook(context, data);
        }
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

            // Everything coloured follows the time left, as in the app; finished ones go grey, and
            // ones without a date are purple.
            // The date is in the heading above the card, so the card itself only has the time and
            // the days left (pinned ones, under "Pinned", keep their date).
            int[] mark;
            String when;
            boolean overdue = false;
            if (item.due.isEmpty()) {
                mark = WidgetLook.PURPLE;
                when = item.pinned ? "No due date" : "";
            } else {
                long days = daysLeft(item.due);
                when = item.time;
                if (item.pinned)
                    when = (day(item.due) + " " + when).trim();
                when = (when.isEmpty() ? "" : when + "  ·  ") + relative(days);
                mark = days > 7 ? WidgetLook.GREEN : days > 2 ? WidgetLook.YELLOW : WidgetLook.RED;
                overdue = days < 0;
            }
            if (item.done)
                mark = WidgetLook.DONE;

            // A heading over the first card of each day, as in the app.
            String group = groupOf(item);
            boolean first = position == 0 || !groupOf(items.get(position - 1)).equals(group);
            card.setViewVisibility(R.id.item_header, first ? View.VISIBLE : View.GONE);
            card.setTextViewText(R.id.item_header, groupTitle(group));
            look.color(card, R.id.item_header, "setTextColor",
                       group.equals("pinned") ? WidgetLook.TEXT
                       : !item.due.isEmpty() && daysLeft(item.due) < 0 ? WidgetLook.OVERDUE : WidgetLook.MUTED);

            // Every colour set every time (see WidgetLook): the launcher reuses card views.
            look.background(card, R.id.item_card, R.drawable.widget_card,
                            R.drawable.widget_card_light, R.drawable.widget_card_dark);
            look.color(card, R.id.item_pin, "setColorFilter", WidgetLook.TEXT);
            look.color(card, R.id.item_border, "setColorFilter", item.done ? WidgetLook.CARD : mark);
            look.color(card, R.id.item_dot, "setColorFilter", mark);
            card.setViewVisibility(R.id.item_pin, item.pinned ? View.VISIBLE : View.GONE);
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
            look.color(card, R.id.item_when, "setTextColor",
                       item.done ? WidgetLook.DONE : overdue ? WidgetLook.OVERDUE : WidgetLook.MUTED);
            card.setTextViewText(R.id.item_title, struck(item.assignment, item.done));
            look.color(card, R.id.item_title, "setTextColor", item.done ? WidgetLook.DONE : WidgetLook.TEXT);
            card.setOnClickFillInIntent(R.id.item_root, new Intent());   // opens the app
            return card;
        }

        static String groupOf(WidgetData.Item item) {
            return item.pinned ? "pinned" : item.due.isEmpty() ? "none" : item.due;
        }

        static String groupTitle(String group) {
            if (group.equals("pinned")) return "Pinned";
            if (group.equals("none")) return "No due date";
            long days = daysLeft(group);
            String day = day(group);
            return days == 0 ? "Today · " + day : days == 1 ? "Tomorrow · " + day
                 : days == -1 ? "Yesterday · " + day : day;
        }

        static long daysLeft(String due) {
            try {
                return ChronoUnit.DAYS.between(LocalDate.now(), LocalDate.parse(due));
            } catch (Exception e) {
                return 0;
            }
        }

        static String day(String due) {
            try {
                return LocalDate.parse(due).format(DAY);
            } catch (Exception e) {
                return due;
            }
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
