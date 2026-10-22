// Starts the Deadlines phone app; everything else is in Main.qml (and logic.js).
#include <QFont>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QStyleHints>

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

    // (Main.qml imports the plain Basic controls by name and styles them itself.)
    // The app is light; keeping the scheme light also keeps the status bar icons dark on it.
    app.styleHints()->setColorScheme(Qt::ColorScheme::Light);

    QQmlApplicationEngine engine;
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Deadlines", "Main");
    return app.exec();
}
