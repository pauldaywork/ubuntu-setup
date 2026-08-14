// Multi-line box for typing a new task, tagged with the focused workspace.
//
// This exists because fuzzel can't do it. The fuzzel add box (task-add.sh) is a
// single line roughly 48 characters wide, and the popup can't grow much past 52
// before it runs out of screen — so a long task was typed half-blind. The
// obvious fixes all meant launching something (a terminal, a GTK dialog), and
// launching anything was the part that felt slow. Living inside the shell
// process that's already running costs no launch at all.
//
// FloatingWindow rather than a layer shell surface: it's what
// Modals/WorkspaceRenameModal.qml uses for the same job, and a fixed min == max
// size is what makes niri float it (see the auto-float note in config.kdl)
// without needing a window rule of its own.
import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Common
import qs.Widgets

FloatingWindow {
    id: root

    // Workspace tag the task will get, without the leading "+". The daemon
    // resolves it before opening — an empty one never gets this far.
    property string tag: ""

    signal submitted(string description)

    objectName: "taskAddModal"
    title: "Add Task"
    // Wide enough for a sentence and tall enough for about five lines. Fixed,
    // because a resizable window here would be a decision to make every time
    // rather than a box that's always the same shape.
    minimumSize: Qt.size(560, 300)
    maximumSize: Qt.size(560, 300)
    color: Theme.surfaceContainer
    visible: false

    onClosed: hide()

    function show(workspaceTag) {
        tag = workspaceTag;
        input.text = "";
        visible = true;
        Qt.callLater(() => input.forceActiveFocus());
    }

    function hide() {
        visible = false;
    }

    // The box wraps, but the description that comes out of it is one line.
    //
    // Taskwarrior will store a newline (it does, and `task list` even wraps it
    // over two rows), but everything downstream reads it back on one: jq's
    // @tsv in task-list.sh escapes the newline, so the picker would show a
    // literal "\n" in the middle of the task, and the bar widget has the same
    // problem. So the extra room here is for seeing what you type, not for
    // storing shape — whitespace collapses on the way out.
    function submitAndClose() {
        const description = input.text.replace(/\s+/g, " ").trim();
        hide();
        if (description.length > 0)
            root.submitted(description);
    }

    onVisibleChanged: {
        if (visible) {
            Qt.callLater(() => input.forceActiveFocus());
            return;
        }
        input.text = "";
    }

    FocusScope {
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: event => {
            hide();
            event.accepted = true;
        }

        Column {
            id: contentCol
            anchors.centerIn: parent
            width: parent.width - Theme.spacingL * 2
            spacing: Theme.spacingM

            Item {
                width: contentCol.width
                height: Math.max(headerText.height, closeButton.height)

                MouseArea {
                    anchors.left: parent.left
                    anchors.right: closeButton.left
                    anchors.rightMargin: Theme.spacingM
                    height: parent.height
                    onPressed: windowControls.tryStartMove()
                }

                StyledText {
                    id: headerText
                    // The tag is the whole point of the box — it's what scopes
                    // the task to the project you're looking at — so it's in
                    // the header rather than left implicit.
                    text: "New task in +" + root.tag
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceTextMedium
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - closeButton.width - Theme.spacingM
                    elide: Text.ElideRight
                }

                DankActionButton {
                    id: closeButton
                    anchors.right: parent.right
                    iconName: "close"
                    iconSize: Theme.iconSize - 4
                    iconColor: Theme.surfaceText
                    onClicked: hide()
                }
            }

            Rectangle {
                width: parent.width
                height: 140
                radius: Theme.cornerRadius
                color: Theme.surfaceHover
                border.color: input.activeFocus ? Theme.primary : Theme.outlineStrong
                border.width: input.activeFocus ? 2 : 1
                clip: true

                ScrollView {
                    id: inputScroll
                    anchors.fill: parent
                    anchors.margins: Theme.spacingS

                    TextArea {
                        id: input

                        wrapMode: TextArea.Wrap
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                        selectByMouse: true
                        // The Rectangle above is the background; TextArea's own
                        // would draw a second box inside it.
                        background: null
                        // Zeroed so the placeholder below can line up with the
                        // real text by matching the ScrollView's margin alone.
                        padding: 0

                        // TextArea's own placeholderText draws nothing under the
                        // style DMS runs — Notepad's editor doesn't use it
                        // either. Drawing it here is a few lines and behaves.
                        StyledText {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            text: "New task…"
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceTextMedium
                            visible: input.text.length === 0
                        }

                        cursorDelegate: DankTextCursor {
                            width: 1.5
                            color: Theme.surfaceText
                            x: input.cursorRectangle.x
                            y: input.cursorRectangle.y
                            height: input.cursorRectangle.height
                            shown: input.cursorVisible
                        }

                        // Enter has to insert a newline for a multi-line box to
                        // be worth having, so submitting moves to Ctrl+Enter.
                        Keys.onPressed: event => {
                            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                    && (event.modifiers & Qt.ControlModifier)) {
                                root.submitAndClose();
                                event.accepted = true;
                            }
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: 36

                StyledText {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    // Ctrl+Enter isn't guessable the way Enter was in the
                    // fuzzel box, so the box says so.
                    text: "Ctrl+Enter to add · Esc to cancel"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceTextMedium
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingM

                    Rectangle {
                        width: Math.max(70, cancelText.contentWidth + Theme.spacingM * 2)
                        height: 36
                        radius: Theme.cornerRadius
                        color: cancelArea.containsMouse ? Theme.surfaceTextHover : Theme.withAlpha(Theme.surfaceTextHover, 0)
                        border.color: Theme.surfaceVariantAlpha
                        border.width: 1

                        StyledText {
                            id: cancelText
                            anchors.centerIn: parent
                            text: "Cancel"
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            font.weight: Font.Medium
                        }

                        MouseArea {
                            id: cancelArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: hide()
                        }
                    }

                    Rectangle {
                        width: Math.max(80, addText.contentWidth + Theme.spacingM * 2)
                        height: 36
                        radius: Theme.cornerRadius
                        color: addArea.containsMouse ? Qt.darker(Theme.primary, 1.1) : Theme.primary

                        StyledText {
                            id: addText
                            anchors.centerIn: parent
                            text: "Add"
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.background
                            font.weight: Font.Medium
                        }

                        MouseArea {
                            id: addArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.submitAndClose()
                        }

                        Behavior on color {
                            ColorAnimation {
                                duration: Theme.shortDuration
                                easing.type: Theme.standardEasing
                            }
                        }
                    }
                }
            }
        }
    }

    FloatingWindowControls {
        id: windowControls
        targetWindow: root
    }
}
