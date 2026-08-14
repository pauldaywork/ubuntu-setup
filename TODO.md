# TODO

- [ ] store longer detail against a task with taskwarrior annotations (`task <uuid> annotate`): add an "Annotate" action to the menu in task-list.sh alongside Edit/Delete/Complete/Set active, mark annotated rows in the list (export carries them as `.annotations[]`), and consider an "Open in editor" action shelling out to `task <uuid> edit` for anything longer.

## Done

- [x] add tasks plugin and make it appear in the second nav bar via install.sh
- [x] add docker install and make sure it is setup with the correct permissions.
- [x] when the open_project_workspace.sh script runs and a project is selected, if workspace name already exists just move to that workspace instead of creating a new one
- [x] add nvidia-container-toolkit to docker install process. make sure to double check there isn't any user permissions issues with any part of the docker install process
- [x] add a create task script that uses fuzzel and when i have typed my task and pressed enter it creates that task using the task cli and adds a tag that is the name of the workspace I am currently in. documentation for task cli is here: https://taskwarrior.org/
- [x] I want to have a shortcut that opens up a list of tasks from the task cli and filter by a tag with the same name as the current workspace I am in. show this list in fuzzel. documentation for task cli is here: https://taskwarrior.org/
- [x] when I select I ask it gives me the option to edit, delete, complete, active (active sets this task as active using the task start command and all other tasks with this workspace tag as inactive by using the task stop command on any). documentation for task cli is here: https://taskwarrior.org/
- [x] I want to display somewhere in the UI the current active task for this workspace. maybe in the second nav menu at the bottom of the screen. make sure to show the active task for that workspace only and when I move to a different workspace update to find the current active task with that new workspace name as it's tag and if none are found show nothing.
- [x] can we style fuzzel to be similar to how the ghostty terminal on this desktop is currently styled with the blury transparent background?
- [x] top nav bar has a dropdown shadow when it shouldn't. this might need to be updated for DMS settings in a config file somewhere.
- [x] animated GIF wallpapers — DMS renders one still frame, so swww draws the background instead and wallpaper-sync.sh keeps it pointed at whatever the DMS picker selected
