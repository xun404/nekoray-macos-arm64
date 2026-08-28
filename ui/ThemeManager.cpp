#include <QApplication>
#include <QPalette>
#include <QStyleHints>

#include "ThemeManager.hpp"
#include "main/NekoGui.hpp"

ThemeManager *themeManager = new ThemeManager;

extern QString ReadFileText(const QString &path);

// Palette-driven QSS for the sidebar & cards. Colors are derived from the
// active palette at call time so both light and dark appearances work.
static QString PolishQss() {
    auto pal = qApp->palette();
    auto window = pal.color(QPalette::Window);
    auto base = pal.color(QPalette::Base);
    auto highlight = pal.color(QPalette::Highlight);
    auto highlightedText = pal.color(QPalette::HighlightedText);
    auto windowText = pal.color(QPalette::WindowText);

    auto blend = [](const QColor &a, const QColor &b, qreal t) {
        return QColor(
            int(a.red() * (1 - t) + b.red() * t),
            int(a.green() * (1 - t) + b.green() * t),
            int(a.blue() * (1 - t) + b.blue() * t),
            int(a.alpha() * (1 - t) + b.alpha() * t));
    };
    auto rgba = [](const QColor &c, qreal alpha) {
        return QString("rgba(%1, %2, %3, %4)").arg(c.red()).arg(c.green()).arg(c.blue()).arg(alpha, 0, 'f', 3);
    };

    auto isDark = window.lightness() < 128;
    auto sidebarBg = blend(window, QColor(0, 0, 0), isDark ? 0.18 : 0.035);
    auto cardBg = blend(window, isDark ? QColor(255, 255, 255) : QColor(255, 255, 255), isDark ? 0.05 : 0.65);
    auto borderColor = blend(window, isDark ? QColor(255, 255, 255) : QColor(0, 0, 0), 0.14);
    auto captionColor = blend(windowText, window, 0.45);
    auto hoverBg = rgba(windowText, 0.06);

    return QString(qApp->styleSheet() + R"(
QFrame#nekoSidebar { background: %SIDEBAR%; border-right: 1px solid %BORDER%; }
QLabel#logoText { color: palette(window-text); }
QListWidget#nekoNav { background: transparent; border: none; outline: none; font-size: 14px; color: palette(window-text); }
QListWidget#nekoNav::item { padding: 9px 10px; margin: 2px 6px; border-radius: 8px; color: palette(window-text); }
QListWidget#nekoNav::item:hover { background: %HOVER%; }
QListWidget#nekoNav::item:selected { background: %HL%; color: %HLTEXT%; }
QFrame#cardStatus, QFrame#cardMode, QFrame#cardInbound { background: %CARD%; border: 1px solid %BORDER%; border-radius: 12px; }
QLabel#labelModeTitle, QLabel#labelInboundTitle { color: %CAPTION%; font-size: 12px; }
QLabel#label_speed { color: %CAPTION%; }
)")
                        .replace("%SIDEBAR%", sidebarBg.name())
                        .replace("%CARD%", cardBg.name())
                        .replace("%BORDER%", borderColor.name())
                        .replace("%HL%", highlight.name())
                        .replace("%HLTEXT%", highlightedText.name())
                        .replace("%CAPTION%", captionColor.name())
                        .replace("%HOVER%", hoverBg);
}

void ThemeManager::ApplyTheme(const QString &appearance) {
    current_appearance = appearance;

    auto hints = qApp->styleHints();
    static bool colorSchemeHooked = false;
    if (!colorSchemeHooked) {
        colorSchemeHooked = true;
        QObject::connect(hints, &QStyleHints::colorSchemeChanged, hints, [=] { ApplyTheme(current_appearance); });
    }

    // Qt::ColorScheme::Unknown lets the platform appearance decide.
    auto scheme = Qt::ColorScheme::Unknown;
    if (appearance == "light") {
        scheme = Qt::ColorScheme::Light;
    } else if (appearance == "dark") {
        scheme = Qt::ColorScheme::Dark;
    }
    hints->setColorScheme(scheme);

    // Keep QMessageBox text selectable; the only rule left in neko.css.
    qApp->setStyleSheet(ReadFileText(":/neko/neko.css"));
    // sidebar & cards, derived from the (possibly updated) palette
    qApp->setStyleSheet(PolishQss());
}
