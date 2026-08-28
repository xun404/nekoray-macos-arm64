#include "QvProxyConfigurator.hpp"

#include <QStandardPaths>
#include <QProcess>

#include "3rdparty/fix_old_qt.h"
#include "3rdparty/qv2ray/wrapper.hpp"
#include "fmt/Preset.hpp"
#include "main/NekoGui.hpp"

#define QV_MODULE_NAME "SystemProxy"

#define QSTRN(num) QString::number(num)

namespace Qv2ray::components::proxy {

    using ProcessArgument = QPair<QString, QStringList>;

    QStringList macOSgetNetworkServices() {
        QProcess p;
        p.setProgram("/usr/sbin/networksetup");
        p.setArguments(QStringList{"-listallnetworkservices"});
        p.start();
        p.waitForStarted();
        p.waitForFinished();
        LOG(p.errorString());
        auto str = p.readAllStandardOutput();
        auto lines = SplitLines(str);
        QStringList result;

        // Start from 1 since first line is unneeded.
        for (auto i = 1; i < lines.count(); i++) {
            // * means disabled.
            if (!lines[i].contains("*")) {
                result << lines[i];
            }
        }

        LOG("Found " + QSTRN(result.size()) + " network services: " + result.join(";"));
        return result;
    }

    void SetSystemProxy(int httpPort, int socksPort) {
        const QString &address = "127.0.0.1";
        bool hasHTTP = (httpPort > 0 && httpPort < 65536);
        bool hasSOCKS = (socksPort > 0 && socksPort < 65536);

        if (!hasHTTP && !hasSOCKS) {
            LOG("Nothing?");
            return;
        }

        if (hasHTTP) {
            LOG("Qv2ray will set system proxy to use HTTP");
        }

        if (hasSOCKS) {
            LOG("Qv2ray will set system proxy to use SOCKS");
        }

        for (const auto &service: macOSgetNetworkServices()) {
            LOG("Setting proxy for interface: " + service);
            if (hasHTTP) {
                QProcess::execute("/usr/sbin/networksetup", {"-setwebproxystate", service, "on"});
                QProcess::execute("/usr/sbin/networksetup", {"-setsecurewebproxystate", service, "on"});
                QProcess::execute("/usr/sbin/networksetup", {"-setwebproxy", service, address, QSTRN(httpPort)});
                QProcess::execute("/usr/sbin/networksetup", {"-setsecurewebproxy", service, address, QSTRN(httpPort)});
            }

            if (hasSOCKS) {
                QProcess::execute("/usr/sbin/networksetup", {"-setsocksfirewallproxystate", service, "on"});
                QProcess::execute("/usr/sbin/networksetup", {"-setsocksfirewallproxy", service, address, QSTRN(socksPort)});
            }
        }
    }

    void ClearSystemProxy() {
        LOG("Clearing System Proxy");

        for (const auto &service: macOSgetNetworkServices()) {
            LOG("Clearing proxy for interface: " + service);
            QProcess::execute("/usr/sbin/networksetup", {"-setautoproxystate", service, "off"});
            QProcess::execute("/usr/sbin/networksetup", {"-setwebproxystate", service, "off"});
            QProcess::execute("/usr/sbin/networksetup", {"-setsecurewebproxystate", service, "off"});
            QProcess::execute("/usr/sbin/networksetup", {"-setsocksfirewallproxystate", service, "off"});
        }
    }
} // namespace Qv2ray::components::proxy
