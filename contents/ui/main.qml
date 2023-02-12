import QtQuick 2.0
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore

Item {
    id: root

    property var inhibitingAppList: []
    property var mediaAppList: []
    property var messageList: {
        let messages = [];
        // laptop lid warning
        if (pmSource.data["PowerDevil"] && pmSource.data["PowerDevil"]["Is Lid Present"] && !pmSource.data["PowerDevil"]["Triggers Lid Action"]) {
            messages.push({
                iconSource: "computer-laptop",
                text: i18n("Your notebook is configured not to sleep when closing the lid while an external monitor is connected.")
            });
        }
        // inhibiting applications
        if (inhibitingAppList.length > 0) {
            messages.push({
                text: (() => {
                    if (inhibitingAppList.length > 1)
                        return i18np("%1 application is preventing sleep and screen locking:",
                                     "%1 applications are preventing sleep and screen locking:",
                                     inhibitingAppList.length);
                        if (1 === inhibitingAppList.length)
                            return i18n("An application is preventing sleep and screen locking:");
                        return "";
                })(),
                children: inhibitingAppList.map((inhibitingApp) => {
                    return {
                        iconSource: inhibitingApp.Icon,
                        text: (() => {
                            if (inhibitingApp.Reason)
                                return i18nc("Application name: reason for preventing sleep and screen locking", "%1: %2", inhibitingApp.Name, inhibitingApp.Reason);
                            return i18nc("Application name: reason for preventing sleep and screen locking", "%1: unknown reason", inhibitingApp.Name);
                        })()
                    };
                })
            });
        }
        // media applications
        if (mediaAppList.length > 0) {
            messages.push({
                text: (() => {
                    if (mediaAppList.length > 1)
                        return i18np("%1 media application:",
                                     "%1 media applications:",
                                     mediaAppList.length);
                        if (1 === mediaAppList.length)
                            return i18n("An media application:");
                        return "";
                })(),
                children: mediaAppList.map((mediaApp) => {
                    return {
                        iconSource: mediaApp.Playing ? "media-playback-playing" : "media-playback-paused",
                        text: (() => {
                            return i18nc("Application name: process name", "%1 (%2)", mediaApp.Name, mediaApp.Process);
                        })()
                    };
                })
            });
        }
        return messages;
    }

    Plasmoid.icon: "exception"
    Plasmoid.switchWidth: PlasmaCore.Units.gridUnit * 10
    Plasmoid.switchHeight: PlasmaCore.Units.gridUnit * 10
    Plasmoid.toolTipMainText: i18n("Media Flow")
    Plasmoid.compactRepresentation: CompactRepresentation {}
    Plasmoid.fullRepresentation: FullRepresentation {}
    Plasmoid.toolTipSubText: {
        if (messageList.length > 0)
            return i18np("%1 message", "%1 messages", messageList.length);
        return i18n("No messages");
    }
    Plasmoid.status: {
        if (messageList.length > 0)
            return PlasmaCore.Types.ActiveStatus;
        return PlasmaCore.Types.PassiveStatus;
    }

    PlasmaCore.DataSource {
        id: pmSource

        engine: "powermanagement"
        connectedSources: sources

        onSourceAdded: {
            disconnectSource(source);
            connectSource(source);
        }

        onSourceRemoved: {
            disconnectSource(source);
        }

        onDataChanged: {
            root.updateInhibitingAppList();
        }
    }

    function updateInhibitingAppList() {
        let inhibitingApps = [];
        if (pmSource.data["Inhibitions"]) {
            for (let key in pmSource.data["Inhibitions"])
                inhibitingApps.push(pmSource.data["Inhibitions"][key]);
        }
        root.inhibitingAppList = inhibitingApps;
    }

    // media

    PlasmaCore.DataSource {
        id: mediaSource

        property var state: ({})
        property var active: false

        property int spotifyInhibitionCookie: -1

        property var blacklist: ['@multiplex', 'plasma-browser-integration']

        engine: "mpris2"
        connectedSources: sources

        onSourceAdded: {
            disconnectSource(source);
            if (!blacklist.includes(source)) {
                connectSource(source);
            }
        }

        onSourceRemoved: {
            disconnectSource(source);
        }

        onDataChanged: {
            root.updateMediaAppList();
        }

        onNewData: (key, data) => {
            if (!blacklist.includes(key)) {
                const Playing = (data.PlaybackStatus === 'Playing');

                state[key] = {
                    Name: data.Identity,
                    Playing,
                }

                if (Plasmoid.configuration.autoPause) {
                    if (!active && Playing) {
                        active = key 
                    }

                    if (key === active && !Playing) {
                        active = false
                    }

                    if (Playing && active && key != active) {
                        var service = serviceForSource(active);
                        var operation = service.operationDescription("Pause");
                        service.startOperationCall(operation);
                        active = key;
                    }
                }

                // fix spotifi inhibtion
                if (key === 'spotify') {
                    if (Playing && spotifyInhibitionCookie === -1) {
                        var service = pmSource.serviceForSource('PowerDevil');
                        var operation = service.operationDescription("beginSuppressingSleep");
                        operation.reason = data.Identity + ': ' + data.PlaybackStatus;
                        var serviceJob = service.startOperationCall(operation);
                        serviceJob.finished.connect(job => {
                            spotifyInhibitionCookie = job.result;
                        })
                    } else if (!Playing && spotifyInhibitionCookie !== -1) {
                        var service = pmSource.serviceForSource('PowerDevil');
                        var operation = service.operationDescription("stopSuppressingSleep");
                        operation.cookie = spotifyInhibitionCookie;
                        var serviceJob = service.startOperationCall(operation);
                        serviceJob.finished.connect(job => {
                            spotifyInhibitionCookie = -1;
                        })
                    }
                }
            }
        }
    }

    function updateMediaAppList() {
        let mediaApps = [];
        for (let key in mediaSource.state) {
            mediaApps.push({
                Process: key,
                Name: mediaSource.state[key].Name,
                Playing: mediaSource.state[key].Playing,
            })
        }
        root.mediaAppList = mediaApps;
    }


    function action_autoPause() {
        if (!Plasmoid.configuration.autoPause) {
            Plasmoid.configuration.autoPause = true;
        } else {
            Plasmoid.configuration.autoPause = false;
        }
    }

    Component.onCompleted: {
        root.updateInhibitingAppList();
        root.updateMediaAppList();

        Plasmoid.setAction("autoPause", i18n("Auto pause previous player"), "media-playback-pause");
        Plasmoid.action("autoPause").checkable = true;
        Plasmoid.action("autoPause").checked = Qt.binding(() => Plasmoid.configuration.autoPause);
    }
}
