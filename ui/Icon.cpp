#include "Icon.hpp"

#include "main/NekoGui.hpp"

#include <QGuiApplication>
#include <QPainter>

// Draw a compact status glyph that stays visible on both light and dark
// menu bars: a rounded-box outline double-stroked in dark and light, with a
// status-colored dot (white-ringed) in the corner when a proxy mode is active.
static QPixmap DrawVectorTrayIcon(Icon::TrayIconStatus status) {
    auto dpr = qGuiApp->devicePixelRatio();
    if (dpr < 1) dpr = 1;
    const int side = 22;

    QPixmap pm(int(side * dpr), int(side * dpr));
    pm.setDevicePixelRatio(dpr);
    pm.fill(Qt::transparent);

    QPainter p(&pm);
    p.setRenderHint(QPainter::Antialiasing);

    QRectF box(2.5, 2.5, side - 5.0, side - 5.0);
    qreal radius = box.width() * 0.30;

    p.setBrush(Qt::NoBrush);
    // outer light halo + inner dark stroke -> contrast on any menubar
    p.setPen(QPen(QColor(255, 255, 255, 230), 3.2));
    p.drawRoundedRect(box, radius, radius);
    p.setPen(QPen(QColor(25, 25, 25, 225), 1.5));
    p.drawRoundedRect(box, radius, radius);

    if (status != Icon::NONE) {
        QColor color;
        if (status == Icon::RUNNING) {
            color = QColor(46, 160, 67); // green
        } else if (status == Icon::SYSTEM_PROXY) {
            color = QColor(31, 111, 235); // blue
        } else { // VPN
            color = QColor(218, 54, 51); // red
        }
        QPointF c(side - 6.2, side - 6.2);
        p.setPen(QPen(QColor(255, 255, 255, 240), 1.8));
        p.setBrush(color);
        p.drawEllipse(c, 3.4, 3.4);
    }

    p.end();
    return pm;
}

QPixmap Icon::GetTrayIcon(Icon::TrayIconStatus status) {
    QPixmap pixmap;

    // user icon (pack / custom, placed next to the app)
    pixmap = QPixmap("../" + software_name.toLower() + ".png");
    if (pixmap.isNull()) pixmap = QPixmap("./" + software_name.toLower() + ".png");

    if (pixmap.isNull()) {
        // no (custom) icon asset: draw the native vector tray glyph
        return DrawVectorTrayIcon(status);
    }

    if (status == TrayIconStatus::NONE) return pixmap;

    auto p = QPainter(&pixmap);

    auto side = pixmap.width();
    auto radius = side * 0.4;
    auto d = side * 0.3;
    auto margin = side * 0.05;

    if (status == TrayIconStatus::RUNNING) {
        p.setBrush(QBrush(Qt::darkGreen));
    } else if (status == TrayIconStatus::SYSTEM_PROXY) {
        p.setBrush(QBrush(Qt::blue));
    } else if (status == TrayIconStatus::VPN) {
        p.setBrush(QBrush(Qt::red));
    }
    p.drawRoundedRect(
        QRect(side - d - margin,
              side - d - margin,
              d,
              d),
        radius,
        radius);
    p.end();

    return pixmap;
}

QPixmap Icon::GetMaterialIcon(const QString &name) {
    QPixmap pixmap(":/icon/material/" + name + ".svg");
    return pixmap;
}
