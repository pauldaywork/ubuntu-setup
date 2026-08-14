// Bar widget showing the one started Taskwarrior task belonging to the focused
// niri workspace, and nothing at all when there isn't one.
//
// All the logic lives in ~/.config/niri/task-active.sh — the same workspace
// name -> tag rule that task-add.sh and task-list.sh use, in one place. This
// file only decides when to ask and how to draw the answer.
//
// Refreshes on niri's event stream rather than on a fast timer: switching
// workspace has to update the bar immediately, and polling `task export` a few
// times a second to achieve that would be silly. The slow timer underneath it
// catches changes made outside the shortcuts (a `task start` typed into a
// terminal), where there's no event to hang off.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root
    layerNamespacePlugin: "activetask"

    property string activeTask: ""
    readonly property bool hasActiveTask: activeTask.length > 0

    // Long descriptions would otherwise push every other widget along the bar.
    readonly property int maxTextWidth: 260

    Process {
        id: activeTaskProcess
        running: false
        command: ["sh", "-c", "$HOME/.config/niri/task-active.sh"]

        stdout: StdioCollector {
            onStreamFinished: root.activeTask = text.trim()
        }
    }

    // Fires on every workspace switch, rename, and creation. WorkspacesChanged
    // also arrives once on connect, which doubles as the initial read.
    Process {
        id: workspaceWatcher
        running: true
        command: ["niri", "msg", "--json", "event-stream"]

        stdout: SplitParser {
            onRead: line => {
                if (line.indexOf("WorkspaceActivated") !== -1
                        || line.indexOf("WorkspacesChanged") !== -1)
                    activeTaskProcess.running = true
            }
        }

        // niri restarting (or a config reload dropping the socket) ends the
        // stream. Without this the widget would freeze on its last value for
        // the rest of the session.
        onExited: watcherRestart.start()
    }

    Timer {
        id: watcherRestart
        interval: 2000
        repeat: false
        onTriggered: workspaceWatcher.running = true
    }

    // Setting a task active changes taskwarrior's data but emits no niri event,
    // so the pill used to sit stale until the timer below came round — up to
    // 30 seconds of "why hasn't it updated". Watch the task database directly
    // instead. This also catches a `task start` typed into a terminal, which
    // the event stream never saw either.
    //
    // The path follows data.location in home/.taskrc. If that's ever moved this
    // watch quietly does nothing and the timer still covers it, so a wrong path
    // can't leave the widget worse off than it was before.
    FileView {
        path: Paths.expandTilde("~/.task/pending.data")
        watchChanges: true
        printErrors: false

        // reload() is what re-arms the watch for the next write.
        onFileChanged: {
            reload()
            activeTaskProcess.running = true
        }
    }

    // Fallback only, now that the file watch carries the common case: covers a
    // moved task database, and anything that changes what's active without
    // touching pending.data.
    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: activeTaskProcess.running = true
    }

    Component.onCompleted: activeTaskProcess.running = true

    horizontalBarPill: Component {
        Item {
            // Collapse to nothing rather than leaving a gap in the bar.
            implicitWidth: root.hasActiveTask ? row.implicitWidth : 0
            implicitHeight: row.implicitHeight
            visible: root.hasActiveTask

            Row {
                id: row
                spacing: (root.barConfig?.noBackground ?? false) ? 1 : 4

                DankIcon {
                    name: "play_circle"
                    size: Theme.barIconSize(root.barThickness, -4)
                    color: Theme.widgetIconColor
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: root.activeTask
                    font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale)
                    color: Theme.widgetTextColor
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, root.maxTextWidth)
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    verticalBarPill: Component {
        Item {
            // A vertical bar has no room for the description — the icon alone
            // says "something is running on this workspace", and the tooltip
            // carries the text.
            implicitWidth: icon.implicitWidth
            implicitHeight: root.hasActiveTask ? icon.implicitHeight : 0
            visible: root.hasActiveTask

            DankIcon {
                id: icon
                name: "play_circle"
                size: Theme.barIconSize(root.barThickness)
                color: Theme.widgetIconColor
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
