// Daemon half of the activetask plugin: owns the add-task modal and the IPC
// call that opens it.
//
//     dms ipc call taskAdd open
//
// is what Mod+Alt+T runs. The point of doing it this way is that nothing
// starts: DMS is already running, so the shortcut is a message to a live
// process rather than a program launch. That was the whole complaint about
// every other multi-line option.
//
// A daemon component is instantiated exactly once (the bar widget next door is
// instantiated per bar per screen), which is what makes it the right place for
// an IpcHandler and a single shared window.
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

    // Resolving the tag is a shell question (which workspace is focused, and
    // what does its name reduce to), and task-lib.sh already answers it for the
    // three shell scripts. Asking the same script keeps one definition of the
    // rule instead of a second one written in QML.
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

    // Adding is a shell question too — taskwarrior's attribute syntax only
    // works when the description reaches `task` word-split, and that splitting
    // (with globbing off, so a "*" in a task stays a "*") is already written
    // and commented in task-add-text.sh. Calling it means the modal and the
    // fuzzel fallback can't drift apart.
    Process {
        id: addProcess
        running: false
    }

    TaskAddModal {
        id: modal

        onSubmitted: description => {
            addProcess.command = [root.scriptDir + "/task-add-text.sh", modal.tag, description];
            addProcess.running = true;
        }
    }

    IpcHandler {
        target: "taskAdd"

        // Returns immediately; the modal opens once task-tag.sh answers. `dms
        // ipc call` would otherwise sit waiting on a window the user is still
        // typing into.
        function open(): string {
            tagProcess.running = true;
            return "opening";
        }

        function close(): string {
            modal.hide();
            return "closed";
        }
    }
}
