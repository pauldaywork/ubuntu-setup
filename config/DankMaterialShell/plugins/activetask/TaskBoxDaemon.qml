// Daemon half of the activetask plugin: owns the task box and the IPC calls
// that open it.
//
//     dms ipc call taskBox open               # Mod+Alt+T
//     dms ipc call taskBox edit <uuid>        # the Edit action in task-list.sh
//     dms ipc call taskBox annotate <uuid>    # the Note action in task-list.sh
//
// The point of doing it this way is that nothing starts: DMS is already
// running, so the shortcut is a message to a live process rather than a
// program launch. That was the whole complaint about every other multi-line
// option.
//
// A daemon component is instantiated exactly once (the bar widget next door is
// instantiated per bar per screen), which is what makes it the right place for
// an IpcHandler and a single shared window.
//
// Only a uuid ever crosses the IPC boundary — never task text. The description
// to pre-fill an edit with is fetched here, by uuid, so nothing depends on how
// `dms ipc call` quotes an argument containing spaces or punctuation.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

Item {
    id: root

    // The daemon surface contract — DMS sets these when it loads the component.
    property var pluginService: null
    property string pluginId: "activetask"

    readonly property string scriptDir: Paths.expandTilde("~/.config/niri")

    // Held while the shell answers, since the fetches are asynchronous and the
    // modal needs everything at once. Annotating takes two of them — the
    // description to head the box with, then the notes to list — so the mode
    // has to survive the first one to know whether a second is coming.
    property string pendingUuid: ""
    property string pendingMode: ""
    property string pendingDescription: ""

    // Resolving the tag is a shell question (which workspace is focused, and
    // what does its name reduce to), and task-lib.sh already answers it for the
    // shell scripts. Asking the same script keeps one definition of the rule
    // instead of a second one written in QML.
    Process {
        id: tagProcess
        running: false
        command: [root.scriptDir + "/task-tag.sh"]

        stdout: StdioCollector {
            id: tagCollector
        }

        onExited: exitCode => {
            const tag = tagCollector.text.trim();
            if (exitCode !== 0 || tag.length === 0) {
                // Same refusal the shell scripts make, for the same reason: a
                // task with no tag is invisible to every list that reads it
                // back, so it's worse than no task at all.
                ToastService.showWarning("No workspace tag",
                                         "Name this workspace with Mod+Shift+Alt+W before adding a task.");
                return;
            }
            modal.show(tag);
        }
    }

    Process {
        id: descriptionProcess
        running: false

        stdout: StdioCollector {
            id: descriptionCollector
        }

        onExited: exitCode => {
            const description = descriptionCollector.text;
            if (exitCode !== 0 || description.length === 0) {
                // The uuid came from a list that was current when it was drawn,
                // so the usual way to land here is a task completed or deleted
                // in another window since.
                ToastService.showWarning("Task not found",
                                         "It may have been completed or deleted already.");
                root.clearPending();
                return;
            }
            if (root.pendingMode === "annotate") {
                root.pendingDescription = description;
                notesProcess.command = [root.scriptDir + "/task-get-notes.sh", root.pendingUuid];
                notesProcess.running = true;
                return;
            }
            modal.showEdit(root.pendingUuid, description);
            root.clearPending();
        }
    }

    Process {
        id: notesProcess
        running: false

        stdout: StdioCollector {
            id: notesCollector
        }

        onExited: exitCode => {
            // A task with no notes yet is the normal case, not a failure, so an
            // empty answer still opens the box — just without the list.
            const existingNotes = exitCode === 0 ? notesCollector.text.trim() : "";
            modal.showAnnotate(root.pendingUuid, root.pendingDescription, existingNotes);
            root.clearPending();
        }
    }

    function clearPending() {
        pendingUuid = "";
        pendingMode = "";
        pendingDescription = "";
    }

    // Both per-task openers start the same way — the description is needed to
    // pre-fill an edit and to head a note box — so they differ only in the mode
    // carried through to the other side of the fetch.
    function openForTask(uuid, wantedMode) {
        if (!uuid)
            return "no uuid given";
        pendingUuid = uuid;
        pendingMode = wantedMode;
        pendingDescription = "";
        descriptionProcess.command = [scriptDir + "/task-get-text.sh", uuid];
        descriptionProcess.running = true;
        return "opening";
    }

    // Writing is a shell question too. Adding word-splits the description so
    // taskwarrior's attribute syntax works ("ship it due:friday"); editing and
    // noting quote it, so a "due:" typed mid-rename or inside a note stays text
    // rather than setting a date. Those rules are already written and commented
    // in their scripts, and calling them means the box and the fuzzel fallbacks
    // can't drift apart.
    Process {
        id: writeProcess
        running: false
    }

    TaskBoxModal {
        id: modal

        onSubmitted: text => {
            if (modal.annotating)
                writeProcess.command = [root.scriptDir + "/task-annotate-text.sh", modal.taskUuid, text];
            else if (modal.editing)
                writeProcess.command = [root.scriptDir + "/task-edit-text.sh", modal.taskUuid, text];
            else
                writeProcess.command = [root.scriptDir + "/task-add-text.sh", modal.tag, text];
            writeProcess.running = true;
        }
    }

    IpcHandler {
        target: "taskBox"

        // Both openers return immediately; the window appears once the shell
        // call behind it answers. `dms ipc call` would otherwise sit waiting on
        // a box the user is still typing into.
        function open(): string {
            tagProcess.running = true;
            return "opening";
        }

        function edit(uuid: string): string {
            return root.openForTask(uuid, "edit");
        }

        function annotate(uuid: string): string {
            return root.openForTask(uuid, "annotate");
        }

        function close(): string {
            modal.hide();
            return "closed";
        }
    }
}
