// Starts the Deadlines phone app; everything else is in Main.qml (and logic.js), apart from the
// home-screen widget, which is Android code (android/src/.../DeadlinesWidget.java).
#include <QFont>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#ifdef Q_OS_ANDROID
#include <QDir>
#include <QJniObject>
#include <QSaveFile>
#include <QStandardPaths>
#endif

// What Main.qml calls (as "widgetBridge") for the Android-only parts: keeping the home-screen
// widget up to date, the status/navigation bar icons in light or dark, and leaving with back.
class WidgetBridge : public QObject
{
    Q_OBJECT
public:
    // Saves the list for the widget (files/widget.json) and has every placed widget redraw.
    Q_INVOKABLE void update(const QString &json)
    {
#ifdef Q_OS_ANDROID
        const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
        QDir().mkpath(dir);
        QSaveFile file(dir + "/widget.json");   // all or nothing: the widget never reads half a file
        if (!file.open(QIODevice::WriteOnly))
            return;
        file.write(json.toUtf8());
        if (!file.commit())
            return;
        QJniObject::callStaticMethod<void>("com/deadlinesapp/deadlines/DeadlinesWidget", "refresh",
                                           "(Landroid/content/Context;)V",
                                           QNativeInterface::QAndroidApplication::context().object());
#else
        Q_UNUSED(json)
#endif
    }

    // The back button with nothing left to close: the app goes to the background.
    Q_INVOKABLE void moveToBack()
    {
#ifdef Q_OS_ANDROID
        QJniObject::callStaticMethod<void>("com/deadlinesapp/deadlines/AppTask", "moveToBack",
                                           "(Landroid/content/Context;)V",
                                           QNativeInterface::QAndroidApplication::context().object());
#endif
    }

    // Light icons in the phone's status and navigation bars while the app is dark (dark icons otherwise).
    Q_INVOKABLE void setDarkBars(bool dark)
    {
#ifdef Q_OS_ANDROID
        QJniObject::callStaticMethod<void>("com/deadlinesapp/deadlines/SystemBars", "setDark",
                                           "(Landroid/content/Context;Z)V",
                                           QNativeInterface::QAndroidApplication::context().object(),
                                           jboolean(dark));
#else
        Q_UNUSED(dark)
#endif
    }
};

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setOrganizationName("Deadlines");
    app.setApplicationName("Deadlines");

    // The rounded font (Nunito, see fonts/OFL.txt) as every text's default.
    QString family;
    for (const char *name : {"NunitoRounded-Regular.ttf", "NunitoRounded-Bold.ttf"}) {
        const int id = QFontDatabase::addApplicationFont(QString(":/qt/qml/Deadlines/fonts/") + name);
        if (id >= 0)
            family = QFontDatabase::applicationFontFamilies(id).value(0);
    }
    QFont font(family);
    font.setPixelSize(15);
    app.setFont(font);

    // (Main.qml imports the plain Basic controls by name and styles them itself, and picks light
    // or dark: following the phone, or as chosen in its settings.)

    WidgetBridge widgetBridge;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("widgetBridge", &widgetBridge);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Deadlines", "Main");
    return app.exec();
}

#include "main.moc"
