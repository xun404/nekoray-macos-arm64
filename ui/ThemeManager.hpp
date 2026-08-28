#pragma once

#include <QString>

// Native appearance controller (macOS).
// "auto": follow system light/dark; "light"/"dark": force a scheme.
class ThemeManager {
public:
    QString current_appearance = "auto";

    void ApplyTheme(const QString &appearance);
};

extern ThemeManager *themeManager;
