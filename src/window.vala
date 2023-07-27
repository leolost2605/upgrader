/* window.vala
 *
 * Copyright 2023 Leonhard
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

public class Updater.MainWindow : Gtk.ApplicationWindow {
    private const string BACKUP_SUFFIX = "save";

    private Gtk.Button button;

    private enum ProgressStep {
        PREPARING,
        UPDATING_REPOS,
        INSTALLING_UPDATES,
        FINISHED
    }

    private ProgressStep current_step;
    private Cancellable cancellable;
    private GenericSet<string> updated_repo_files;

    public MainWindow (Application app) {
        application = app;
    }

    construct {
        cancellable = new Cancellable ();
        updated_repo_files = new GenericSet<string> (str_hash, str_equal);

        current_step = PREPARING;

        button = new Gtk.Button.with_label ("start update");
        child = button;
        default_width = 500;
        default_height = 500;

        button.clicked.connect (() => {
            cancellable.reset ();
            button.sensitive = false;
            next ();
        });
    }

    private void next () {
        if (cancellable.is_cancelled ()) {
            return;
        }

        switch (current_step) {
            case PREPARING:
                current_step = UPDATING_REPOS;
                update_repo_files.begin ();
                break;

            case UPDATING_REPOS:
                current_step = INSTALLING_UPDATES;
                update_packages.begin ();
                break;

            case INSTALLING_UPDATES:
                current_step = FINISHED;
                next ();
                break;

            case FINISHED:
                try {
                    Pk.offline_trigger (REBOOT, null);
                    button.label = "Trigger set, we are finished!";
                } catch (Error e) {
                    warning ("Failed to set offline trigger: %s", e.message);
                }
                break;

            default:
                break;
        }
    }

    private void throw_fatal_error (Error? e = null, string? step = null) {
        cancellable.cancel ();
        revert_update_repos.begin ();
        critical (step + e.message);
    }

    private async void revert_update_repos () {
        foreach (var file_name in updated_repo_files.get_values ()) {
            var file = File.new_for_path (file_name);
            var backup_file = File.new_for_path (file_name + "." + BACKUP_SUFFIX);

            if (!backup_file.query_exists ()) {
                critical ("Couldn't find backup file!");
                continue;
            }

            try {
                yield backup_file.copy_async (file, OVERWRITE);
            } catch (Error e) {
                critical ("Failed to backup from file %s: %s", backup_file.get_path (), e.message);
            }
        }
    }

    private async void update_repo_files () {
        var task = new Pk.Task ();
        try {
            var result = task.get_repo_list (0, null, () => {});

            if (result.get_exit_code () != SUCCESS) {
                // throw_fatal_error (result.get_error_code ());
                return;
            }

            foreach (var repo in result.get_repo_detail_array ()) {
                if (cancellable.is_cancelled ()) {
                    return;
                }

                var parts = repo.repo_id.split (":", 2);
                if (parts[0] in updated_repo_files) {
                    continue;
                }

                updated_repo_files.add (parts[0]);

                var file = File.new_for_path (parts[0]);
                yield update_repo_file ("jammy", "lunar", file);
            }

            next ();
        } catch (Error e) {
            throw_fatal_error (e, "Getting Repo List");
        }
    }

    private async void update_repo_file (string old_codename, string new_codename, File file) throws Error {
        if (!file.query_exists ()) {
            return;
        }

        var backup_file = File.new_for_path (file.get_path () + "." + BACKUP_SUFFIX);
        try {
            if (!yield file.copy_async (backup_file, OVERWRITE)) {
                throw_fatal_error (
                    new IOError.FAILED ("Failed to create backup of repo file %s".printf (file.get_path ())),
                    "Backing up repo file %s.".printf (file.get_path ())
                );
                return;
            }
        } catch (Error e) {
            throw_fatal_error (e, "Backing up repo file %s.".printf (file.get_path()));
            return;
        }

        try {
            uint8[] old_contents = {};
            yield file.load_contents_async (null, out old_contents, null);

            var new_contents = ((string)old_contents).replace (old_codename, new_codename);
            yield file.replace_contents_async (new_contents.data, null, true, NONE, null, null);
        } catch (Error e) {
            throw_fatal_error (e, "Updating repo file %s".printf (file.get_path ()));
        }
    }

    private async void update_packages () {
        var task = new Pk.Task ();

        try {
            var refresh_result = yield task.refresh_cache_async (false, null, () => {});

            if (refresh_result.get_exit_code () != SUCCESS) {
                // throw_fatal_error (refresh_result.get_error_code (), "Refreshing apt cache.");
                return;
            }
        } catch (Error e) {
            throw_fatal_error (e, "Refreshing apt cache.");
            return;
        }

        try {
            var upgradable_packes_result = yield task.get_updates_async (0, null, () => {});
            string[] package_ids = {};
            foreach (var package in upgradable_packes_result.get_package_array ()) {
                package_ids += package.package_id;
            }

            yield task.update_packages_async (package_ids, null, (progress, type) => {
                if (type == PERCENTAGE) {
                    button.label = "%i %".printf (progress.percentage);
                }
            });

            next ();
        } catch (Error e) {
            throw_fatal_error (e, "Updating packages.");
        }
    }
}
